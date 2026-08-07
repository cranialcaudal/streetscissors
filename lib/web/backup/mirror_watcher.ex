defmodule Web.Backup.MirrorWatcher do
  @moduledoc """
  Backs the site up onto the external drive as soon as it is plugged in.

  Without this the mirror only moved during a scheduled or boot run, so a drive
  connected at nine in the morning got nothing until the cron fired that
  evening — and if it was unplugged again first, nothing at all. Plugging the
  drive in is the moment the user expects a backup to happen, so that is when
  it happens.

  **Why polling and not udev or a systemd path unit.** Both of those would fire
  instantly, but neither can call into the running application; they would have
  to re-implement snapshotting, verification and retention in a shell script,
  or boot a second copy of the app that fights the first one for the port and
  the database. Checking whether one directory exists is close to free, so the
  cheap approach wins on every axis except a few seconds of latency.

  Edge-triggered: it acts on the transition from absent to present, not on
  every tick, so a drive left plugged in does not cause repeated work. It also
  syncs once at startup if the drive is already there, which covers the
  ordinary case of the drive never being unplugged at all.

  Configure with `:backup_mirror_watch` (set false to disable) and
  `:backup_mirror_watch_interval_ms`.
  """

  use GenServer

  require Logger

  alias Web.Backup

  @default_interval_ms :timer.seconds(30)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Forces a check immediately instead of waiting for the next tick."
  def check_now, do: GenServer.call(__MODULE__, :check, 60_000)

  @impl true
  def init(_opts) do
    if enabled?() do
      # Sync on the way up when the drive is already connected — otherwise a
      # machine that never has it unplugged would never see a transition.
      send(self(), :startup)
      schedule()
      {:ok, %{present?: false}}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:startup, state) do
    present? = Backup.mirror_available?()

    if present? do
      Logger.info("backup: mirror drive present at startup, syncing")
      Backup.sync_mirror()
    end

    {:noreply, %{state | present?: present?}}
  end

  @impl true
  def handle_info(:tick, state) do
    schedule()
    {:noreply, check(state)}
  end

  @impl true
  def handle_call(:check, _from, state) do
    state = check(state)
    {:reply, {:ok, state.present?}, state}
  end

  defp check(%{present?: was_present?} = state) do
    present? = Backup.mirror_available?()

    cond do
      present? and not was_present? ->
        Logger.info("backup: mirror drive connected, backing up")
        Backup.sync_mirror()

      was_present? and not present? ->
        Logger.info("backup: mirror drive disconnected")

      true ->
        :ok
    end

    %{state | present?: present?}
  end

  defp schedule, do: Process.send_after(self(), :tick, interval_ms())

  defp interval_ms,
    do: Application.get_env(:web, :backup_mirror_watch_interval_ms, @default_interval_ms)

  defp enabled? do
    Application.get_env(:web, :backup_mirror_watch, true) and not is_nil(Backup.mirror_dir())
  end
end
