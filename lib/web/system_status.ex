defmodule Web.SystemStatus do
  @moduledoc """
  The machine's own state, as the admin overview reports it: the things that
  should be quietly true on a self-hosted site, each checked and said plainly.

  Every check made here is cheap — a directory listing, a settings read, one
  count query — so the overview runs them all on each mount rather than
  caching. The ones that are not cheap (a TLS handshake, a DNS query, a child
  process) belong to `Web.Monitor`, which makes them on a schedule; `checks/0`
  only reads what its last pass found. Each returns a map:

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

  @doc "Everything the overview lists: this module's own checks, then the monitor's."
  def checks, do: local_checks() ++ Web.Monitor.last().checks ++ [alerts()]

  @doc """
  The checks made here, on the spot. `Web.Monitor` watches these too, and
  cannot call `checks/0` for them without reading its own last pass back.
  """
  def local_checks do
    [
      database_snapshots(),
      backup_mirror(),
      negatives_mirror(),
      written_content(),
      content_mirror(),
      recordings_mirror(),
      restore_drill(),
      komoot(),
      ride_privacy(),
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

  # `at` is when the vault was last *checked*: a night with nothing new writes
  # no version, and is still a night the backup ran.
  def written_content do
    case Backup.Content.list() do
      [] ->
        check(:content, "Written content", :fail, "no version on disk")

      all ->
        state = if Backup.Content.stale?(), do: :warn, else: :ok
        kept = "#{length(all)} #{plural(length(all), "version")} kept"
        check(:content, "Written content", state, kept, Backup.Content.last_run())
    end
  end

  def content_mirror do
    cond do
      is_nil(Backup.Content.mirror_dir()) ->
        check(:content_mirror, "Content copy", :off, "no mirror drive configured")

      Backup.Content.mirror_available?() ->
        check(:content_mirror, "Content copy", :ok, "drive present — versions mirrored")

      true ->
        check(:content_mirror, "Content copy", :warn, "drive not plugged in")
    end
  end

  def recordings_mirror do
    cond do
      is_nil(Backup.Uploads.mirror_dir()) ->
        check(:recordings, "Recordings copy", :off, "no mirror drive configured")

      Backup.Uploads.available?() ->
        check(:recordings, "Recordings copy", :ok, "drive present — logs mirrored")

      true ->
        check(:recordings, "Recordings copy", :warn, "drive not plugged in")
    end
  end

  # The weekly rehearsal (Web.Backup.Drill): the newest snapshot and the
  # newest archive, restored to scratch copies and read back.
  def restore_drill do
    case Backup.Drill.last() do
      nil ->
        check(:restore, "Restore drill", :off, "none run yet")

      %{at: at, database: database, content: content} ->
        cond do
          not database.ok ->
            check(:restore, "Restore drill", :fail, "database: " <> database.detail, at)

          not content.ok ->
            check(:restore, "Restore drill", :fail, "content: " <> content.detail, at)

          Backup.Drill.stale?() ->
            check(:restore, "Restore drill", :warn, "none in over a week", at)

          true ->
            check(
              :restore,
              "Restore drill",
              :ok,
              "database and content restored and read back",
              at
            )
        end
    end
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

  # The tripwire on what Komoot shows of a tour (Web.Rides.Privacy). Komoot's
  # privacy zone is what hides home, and it lives on Komoot's side, so this is
  # the one check here whose failure means a stranger could see where the
  # activities start. It fails for a tour that begins or ends at a private
  # place, which a working zone trims. A tour that only passes one mid-way is
  # ordinary use, held back and mentioned, and never a fault. It says how
  # many, never which or where.
  def ride_privacy do
    case Web.Rides.Privacy.zones() do
      :invalid ->
        check(
          :ride_privacy,
          "Ride privacy",
          :fail,
          "RIDE_PRIVACY_ZONES can't be read, so every embed and map is withheld"
        )

      {:ok, []} ->
        check(:ride_privacy, "Ride privacy", :off, "not checked — no private places on file")

      {:ok, _zones} ->
        views = Web.Rides.stranger_views()

        case Map.get(views, "exposed", 0) do
          0 ->
            check(
              :ride_privacy,
              "Ride privacy",
              :ok,
              "no activity begins or ends at a private place" <> held_back(views)
            )

          n ->
            check(
              :ride_privacy,
              "Ride privacy",
              :fail,
              "#{n} #{plural(n, "activity begins or ends", "activities begin or end")} at a " <>
                "private place as a stranger is shown #{plural(n, "it", "them")} — check the " <>
                "privacy zone in Komoot"
            )
        end
    end
  end

  defp held_back(views) do
    case Map.get(views, "passing", 0) do
      0 -> ""
      n -> " · #{n} held back for passing one mid-tour"
    end
  end

  def mail_queue do
    case failed_mail_count() do
      0 -> check(:mail, "Mail queue", :ok, "no failed sends")
      n -> check(:mail, "Mail queue", :fail, "#{n} #{plural(n, "send")} failed or retrying")
    end
  end

  # The monitor mails a fault to this address. Without one it still checks
  # and still records, and nobody is told.
  def alerts do
    case Web.Notify.address() do
      nil -> check(:alerts, "Alerts", :warn, "no address set — faults are not mailed to anyone")
      address -> check(:alerts, "Alerts", :ok, "faults are mailed to #{address}")
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

  defp plural(1, one, _many), do: one
  defp plural(_, _one, many), do: many

  # File.stat/1 reports mtime as an erlang datetime in UTC by default.
  defp mtime_to_datetime({{_, _, _}, {_, _, _}} = erl),
    do: erl |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")

  defp mtime_to_datetime(_), do: nil
end
