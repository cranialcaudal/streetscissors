defmodule Web.Backup.MirrorWatcher do
  @moduledoc """
  Backs the site up onto the external drive as soon as it is plugged in.

  Without this the mirror only moved during a scheduled or boot run, so a drive
  connected at nine in the morning got nothing until the cron fired that
  evening — and if it was unplugged again first, nothing at all. Plugging the
  drive in is the moment the user expects a backup to happen, so that is when
  it happens.

  Covers everything that has an off-disk copy: the database snapshots
  (`Web.Backup.sync_mirror/0`), the written content
  (`Web.Backup.Content.sync_mirror/0`), the negatives archive
  (`Web.Backup.Photos.sync/0`) and the recordings (`Web.Backup.Uploads.sync/0`).

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
  alias Web.Backup.Content
  alias Web.Backup.Photos
  alias Web.Backup.Uploads

  @default_interval_ms :timer.seconds(30)

  # The first photo sync moves 317 MB to a USB drive, and it runs inside this
  # process so that two syncs can never overlap. Both the call timeout and the
  # supervisor's shutdown grace have to tolerate that.
  @call_timeout :timer.minutes(30)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Forces a check immediately instead of waiting for the next tick."
  def check_now, do: GenServer.call(__MODULE__, :check, @call_timeout)

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
    present? = drive_present?()

    if present? do
      Logger.info("backup: mirror drive present at startup, syncing")
      sync_everything()
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
    present? = drive_present?()

    cond do
      present? and not was_present? ->
        Logger.info("backup: mirror drive connected, backing up")
        sync_everything()

      was_present? and not present? ->
        Logger.info("backup: mirror drive disconnected")

      true ->
        :ok
    end

    %{state | present?: present?}
  end

  # The database and the writing first: they are small, fast, and the things
  # most likely to have changed since the last connection. The negatives and
  # the recordings follow, and only move what is new after the first run.
  defp sync_everything do
    Backup.sync_mirror()
    Content.sync_mirror()
    Photos.sync()
    Uploads.sync()
  end

  # Any one destination being there means the drive is.
  defp drive_present? do
    Backup.mirror_available?() or Content.mirror_available?() or Photos.available?() or
      Uploads.available?()
  end

  defp schedule, do: Process.send_after(self(), :tick, interval_ms())

  defp interval_ms,
    do: Application.get_env(:web, :backup_mirror_watch_interval_ms, @default_interval_ms)

  # Any one destination is reason enough to watch: each can be mirrored
  # without the others being.
  defp enabled? do
    Application.get_env(:web, :backup_mirror_watch, true) and
      Enum.any?(
        [Backup.mirror_dir(), Content.mirror_dir(), Photos.mirror_dir(), Uploads.mirror_dir()],
        &(not is_nil(&1))
      )
  end
end
