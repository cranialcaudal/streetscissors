defmodule Web.SystemStatus do
  @moduledoc """
  The machine's own state, as the admin overview reports it: the things that
  should be quietly true on a self-hosted site, each checked and said plainly.

  Every check is cheap — a directory listing, a settings read, one count
  query — so the overview runs them all on each mount rather than caching.
  Each returns a map:

      %{key: atom, label: String.t(), state: :ok | :warn | :fail | :off,
        detail: String.t(), at: DateTime.t() | nil}

  `:off` means "not set up here" (no mirror configured, Komoot disabled),
  which is an ordinary condition, not a fault. `at` is when the thing last
  happened, for the view to render as "4 h ago".
  """

  import Ecto.Query

  alias Web.Backup
  alias Web.Repo
  alias Web.Rides.KomootSync

  # The hourly pass that hasn't been heard from in this long has stopped.
  @komoot_quiet_hours 3

  def checks do
    [
      database_snapshots(),
      backup_mirror(),
      negatives_mirror(),
      written_content(),
      komoot(),
      mail_queue()
    ]
  end

  def database_snapshots do
    case Backup.list() do
      [] ->
        check(:database, "Database snapshots", :fail, "none on disk")

      [newest | _] = all ->
        state = if Backup.stale?(), do: :warn, else: :ok
        kept = "#{length(all)} kept"
        check(:database, "Database snapshots", state, kept, mtime_to_datetime(newest.mtime))
    end
  end

  def backup_mirror do
    cond do
      is_nil(Backup.mirror_dir()) ->
        check(:mirror, "Off-disk copy", :off, "no mirror drive configured")

      Backup.mirror_available?() ->
        check(:mirror, "Off-disk copy", :ok, "drive present — snapshots mirrored")

      true ->
        check(:mirror, "Off-disk copy", :warn, "drive not plugged in")
    end
  end

  def negatives_mirror do
    cond do
      is_nil(Backup.Photos.mirror_dir()) ->
        check(:negatives, "Negatives copy", :off, "no mirror drive configured")

      Backup.Photos.available?() ->
        check(:negatives, "Negatives copy", :ok, "drive present — scans mirrored")

      true ->
        check(:negatives, "Negatives copy", :warn, "drive not plugged in")
    end
  end

  # A standing warning until content/ joins the nightly backup (roadmap §3):
  # the posts, the fitness vault and the email templates are copied nowhere
  # on a schedule.
  def written_content do
    check(:content, "Written content", :warn, "content/ has no automatic backup yet")
  end

  def komoot do
    if KomootSync.enabled?() do
      %{at: at, status: status, detail: detail} = KomootSync.last_run()

      cond do
        is_nil(at) ->
          check(:komoot, "Komoot sync", :off, "no pass recorded yet")

        status == :failed ->
          check(:komoot, "Komoot sync", :fail, detail, at)

        quiet?(at) ->
          check(:komoot, "Komoot sync", :warn, "no pass in #{@komoot_quiet_hours} h", at)

        status == :partial ->
          check(:komoot, "Komoot sync", :warn, detail, at)

        true ->
          check(:komoot, "Komoot sync", :ok, detail, at)
      end
    else
      check(:komoot, "Komoot sync", :off, "disabled — no Komoot credentials")
    end
  end

  def mail_queue do
    case failed_mail_count() do
      0 -> check(:mail, "Mail queue", :ok, "no failed sends")
      n -> check(:mail, "Mail queue", :fail, "#{n} #{plural(n, "send")} failed or retrying")
    end
  end

  @doc "Newsletter deliveries Oban is retrying or has given up on."
  def failed_mail_count do
    from(j in Oban.Job,
      where: j.queue == "mailers" and j.state in ["retryable", "discarded"],
      select: count(j.id)
    )
    |> Repo.one()
  end

  defp check(key, label, state, detail, at \\ nil) do
    %{key: key, label: label, state: state, detail: detail, at: at}
  end

  defp quiet?(at), do: DateTime.diff(DateTime.utc_now(), at, :hour) >= @komoot_quiet_hours

  defp plural(1, word), do: word
  defp plural(_, word), do: word <> "s"

  # File.stat/1 reports mtime as an erlang datetime in UTC by default.
  defp mtime_to_datetime({{_, _, _}, {_, _, _}} = erl),
    do: erl |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")

  defp mtime_to_datetime(_), do: nil
end
