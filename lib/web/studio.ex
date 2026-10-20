defmodule Web.Studio do
  @moduledoc """
  What the studio floor shows (`/admin/dashboard`): one small map for each of
  the site's programs, gathered from the functions that already know the
  answer, so the page is a few `program_card`s and a status strip and never
  does arithmetic of its own.

      Web.Studio.floor()
      #=> %{darkroom: %{...}, cuts: %{...}, writing: %{...}, training: %{...},
      #     mail: %{...}, on_file: %{...}}

  **Cheap by rule.** Everything here is a directory listing, a settings read
  or one small query; nothing renders a page, probes the network or starts a
  process, because the overview is opened more often than anything else in
  the admin. What is expensive stays behind its own link and is never built
  here: `Web.ContentHealth` renders every page it checks, so the Writing card
  only points at it; `Web.Darkroom.Archive.prints/0` measures every print, so
  the Darkroom card counts edits by listing the `edits/` folders instead; and
  the machine's checks are `Web.Monitor.last/0`'s stored pass
  (`Web.SystemStatus.checks/0`), never a fresh probe.

  Dates and times come back as `DateTime`s and numbers as numbers: the view
  puts the words round them.
  """

  import Ecto.Query

  alias Web.{Blog, Clock, Contact, Guestbook, Logs, Negatives, Newsletter, Repo, Rides}
  alias Web.Logs.Log
  alias Web.Contact.Message
  alias Web.Cuts
  alias Web.Cuts.Timeline
  alias Web.Darkroom.Taste
  alias Web.Fitness.Vault
  alias Web.Negatives.SheetLayout
  alias Web.Rides.KomootSync
  alias Web.Scanner.Pipeline

  # How many prints the Darkroom card's picture shows, and how many cuts it
  # lists.
  @recent_prints 3
  @listed_cuts 2

  @doc """
  Every program's state, from one read of what they share (the logs' counts,
  the posts, the activities).

  Options: `:counts` is the rail's count map (`WebWeb.AdminNav.counts/0`; the
  admin's mount has it already in `@admin_counts`, and it is read when not
  given), `:now` the moment to answer for.
  """
  def floor(opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())
    counts = opts[:counts] || WebWeb.AdminNav.counts()
    logs = Logs.count_by_status()
    posts = Blog.list_all_posts()
    rides = Rides.list_rides()

    %{
      darkroom: darkroom(),
      cuts: cuts(logs),
      writing: writing(posts),
      training: training(rides, now),
      mail: mail(counts),
      on_file: on_file(posts, logs, rides),
      logs: logs
    }
  end

  # ── Darkroom ──────────────────────────────────────────────────────────

  @doc """
  The Darkroom: the roll on the scanner's bench (`Pipeline.roll_in_progress/0`,
  with its strips, prints and singles still owed), the rolls scanned and
  waiting to be published, the prints edited lately with their pictures, and
  how many Taste choices are kept.

  `:recent` is up to #{@recent_prints} edited prints, newest edit first, each
  `%{roll, frame, url, at}` with `url` a 480-pixel copy of the print. A
  darkroom with no edits has `:newest_print` instead, the last print of the
  newest roll that has any, so the card has a picture to show.
  """
  def darkroom do
    bench = bench()

    {edited, recent} = recent_edits(@recent_prints)

    %{
      bench: bench,
      waiting: waiting_rolls(bench),
      edited: edited,
      recent: recent,
      newest_print: if(recent == [], do: newest_print()),
      choices: length(Taste.choices())
    }
  end

  defp bench do
    case Pipeline.roll_in_progress() do
      nil ->
        nil

      {number, date, format, color} ->
        dir = Pipeline.roll_dir(number, date, format, color)

        %{
          roll: number,
          date: date,
          format: format,
          color: color,
          strips: count_strips(dir),
          prints: length(Pipeline.printed_frames(dir)),
          owed: length(Pipeline.owed_singles(dir))
        }
    end
  end

  # Every other roll on disk that the catalog does not list yet: scanned, and
  # waiting for Publish.
  defp waiting_rolls(bench) do
    for {number, _date, format, color} <-
          Pipeline.unpublished_rolls(except: bench && bench.roll) do
      %{roll: number, format: format, color: color}
    end
  end

  # The strip scans in a roll folder, counted without opening one (the
  # pipeline's own `list_strips/1` reads each file's size).
  defp count_strips(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        Enum.count(files, fn file ->
          Path.extname(file) |> String.downcase() |> Kernel.in(SheetLayout.strip_exts()) and
            File.regular?(Path.join(dir, file))
        end)

      _ ->
        0
    end
  end

  @doc """
  The prints edited in the darkroom, newest edit first, as
  `{how many edits there are, [%{roll, frame, url, at}]}` for the `limit`
  newest. An edit is `edits/NN.json` in a roll's folder
  (`Web.Darkroom.edits_path/2`), so this lists the `edits/` folder of every
  roll folder under the archive (one `File.ls` each, a stat for each recipe)
  and never reads a picture. A recipe whose print is gone is not shown.
  """
  def recent_edits(limit) do
    edits = edit_files()

    recent =
      edits
      |> Enum.sort_by(& &1.mtime, :desc)
      |> Enum.take(limit * 2)
      |> Enum.group_by(& &1.roll, & &1)
      |> Enum.flat_map(fn {roll, files} ->
        printed = Map.new(Negatives.list_frames(roll), &{&1.frame, &1})

        for %{frame: frame, mtime: mtime} <- files, print = printed[frame] do
          %{
            roll: roll,
            frame: frame,
            url: Negatives.sized_url(print.url, 480),
            at: DateTime.from_unix!(mtime)
          }
        end
      end)
      |> Enum.sort_by(& &1.at, {:desc, DateTime})
      |> Enum.take(limit)

    {length(edits), recent}
  end

  # `%{roll: "065", frame: 6, mtime: posix}` for every recipe in the archive.
  defp edit_files do
    base = Negatives.base_path()

    for format <- ls_dirs(base),
        folder <- ls_dirs(Path.join(base, format)),
        [_, roll] <- [Regex.run(~r/\Aroll(\d+)_/i, folder)],
        file <- ls(Path.join([base, format, folder, "edits"])),
        [_, digits] <- [Regex.run(~r/\A(\d+)\.json\z/, file)],
        {:ok, %File.Stat{mtime: mtime}} <-
          [File.stat(Path.join([base, format, folder, "edits", file]), time: :posix)] do
      %{roll: roll, frame: String.to_integer(digits), mtime: mtime}
    end
  end

  # Folders that are not hidden (`.darkroom`, `.trash`) and not the contact
  # sheets, which are files in a folder of their own.
  defp ls_dirs(dir) do
    for name <- ls(dir),
        not String.starts_with?(name, "."),
        File.dir?(Path.join(dir, name)),
        do: name
  end

  defp ls(dir) do
    case File.ls(dir) do
      {:ok, names} -> names
      _ -> []
    end
  end

  # The last print of the newest roll that has one: what the card shows
  # before anything has been edited.
  defp newest_print do
    Enum.find_value(Negatives.list_contact_sheets(), fn sheet ->
      case List.last(Negatives.list_frames(sheet.roll)) do
        nil ->
          nil

        print ->
          %{roll: sheet.roll, frame: print.frame, url: Negatives.sized_url(print.url, 480)}
      end
    end)
  end

  # ── Cutting room and the logs ─────────────────────────────────────────

  @doc """
  The cutting room and the Captain's Logs: the newest cuts (name, length,
  clips, and whether one has been rendered into a log), and the logs' state
  from `Logs.count_by_status/0`: how many are ready and not yet published,
  transcoding, and failed, with the newest log and its poster.
  """
  def cuts(logs \\ Logs.count_by_status()) do
    all = Cuts.list_cuts()

    %{
      total: length(all),
      cuts: all |> Enum.take(@listed_cuts) |> Enum.map(&cut/1),
      logs: %{
        unpublished: count_logs(published: false, status: "ready"),
        transcoding: Map.get(logs, "pending", 0) + Map.get(logs, "processing", 0),
        failed: Map.get(logs, "failed", 0)
      },
      newest_log: newest_log()
    }
  end

  defp cut(cut) do
    clips = cut.timeline["clips"] || []

    %{
      id: cut.id,
      name: cut.name,
      length_ms: Timeline.layout(cut.timeline).length,
      clips: length(clips),
      status: cut.status,
      rendered?: cut.status == "done",
      log: cut.audio_log && Log.title(cut.audio_log),
      at: cut.updated_at
    }
  end

  defp count_logs(published: published, status: status) do
    Repo.aggregate(
      from(l in Log, where: l.published == ^published and l.status == ^status),
      :count
    )
  end

  defp newest_log do
    case Repo.one(from l in Log, order_by: [desc: l.recorded_on, desc: l.seq], limit: 1) do
      nil ->
        nil

      log ->
        %{
          title: Log.title(log),
          recorded_on: log.recorded_on,
          caption: log.caption,
          kind: log.kind,
          status: log.status,
          published: log.published,
          poster: Log.poster_url(log)
        }
    end
  end

  # ── Writing ───────────────────────────────────────────────────────────

  @doc """
  The writing desk, from the posts on disk (drafts included): how many are
  drafts and which is newest, the last one published, and the published posts
  missing a description or keywords. Content health (`Web.ContentHealth`)
  renders every page it checks, so it is never worked out here.
  """
  def writing(posts \\ Blog.list_all_posts()) do
    {drafts, published} = Enum.split_with(posts, & &1.draft)

    %{
      drafts: length(drafts),
      newest_draft: drafts |> List.first() |> post(),
      published: length(published),
      last: published |> List.first() |> post(),
      no_description: Enum.count(published, &(not &1.described)),
      no_keywords: Enum.count(published, &(&1.keywords == []))
    }
  end

  defp post(nil), do: nil
  defp post(post), do: %{slug: post.slug, title: post.title, date: post.date}

  # ── Training ──────────────────────────────────────────────────────────

  @doc """
  Training: today's regimen (`theme:` of the fitness vault's day for today by
  `Web.Clock`), the newest activity with Komoot's picture of it when the ride
  is clear and the picture is cached, how many are on file, and Komoot's last
  pass (`KomootSync.last_run/0`).
  """
  def training(rides \\ Rides.list_rides(), now \\ DateTime.utc_now()) do
    %{
      today: today(Clock.today_slug(now)),
      newest: rides |> List.first() |> activity(),
      activities: length(rides),
      sync: KomootSync.last_run()
    }
  end

  defp today(slug) do
    case Enum.find(Vault.list_days(), &(&1.slug == slug)) do
      nil ->
        nil

      day ->
        %{
          slug: slug,
          word: presence(day.theme),
          # "Friday — Swim or Run" without the weekday, for a day with no word
          title: day.title |> String.split(" — ", parts: 2) |> List.last()
        }
    end
  end

  defp activity(nil), do: nil

  defp activity(ride) do
    %{
      id: ride.id,
      name: ride.name,
      sport: ride.sport,
      distance_m: ride.distance_m,
      started_at: ride.started_at,
      picture: Rides.thumb_src(ride)
    }
  end

  # ── Mail ──────────────────────────────────────────────────────────────

  @doc """
  Mail: open messages and letters (inbox and flagged), held signatures and
  held citations, from the rail's own counts (`WebWeb.AdminNav.counts/0`,
  passed in or read), and the newest open message: who wrote and its first
  line. `:flagged` is the part of `:open` marked for attention, which needs
  the one grouped count the rail does not keep.
  """
  def mail(counts \\ WebWeb.AdminNav.counts()) do
    %{
      open: counts.inbox,
      flagged: Map.get(Contact.count_by_status(), "attention", 0),
      held: counts.guestbook,
      citations: counts.citations,
      newest: newest_message()
    }
  end

  defp newest_message do
    query =
      from m in Message,
        where: m.status in ["inbox", "attention"],
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: 1

    case Repo.one(query) do
      nil ->
        nil

      message ->
        %{
          name: message.name,
          line: first_line(message.message),
          letter?: message.piece != nil,
          at: DateTime.from_naive!(message.inserted_at, "Etc/UTC")
        }
    end
  end

  @doc "The first line with something in it, cut to a phrase at a word."
  def first_line(text, max \\ 90) when is_binary(text) do
    line =
      text
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.find("", &(&1 != ""))

    if String.length(line) <= max do
      line
    else
      cut = String.slice(line, 0, max)
      cut = if String.contains?(cut, " "), do: String.replace(cut, ~r/\s+\S*\z/, ""), else: cut
      String.trim_trailing(cut, ".,;:") <> "…"
    end
  end

  # ── What is on file ───────────────────────────────────────────────────

  @doc "The counts the status strip carries."
  def on_file(
        posts \\ Blog.list_all_posts(),
        logs \\ Logs.count_by_status(),
        rides \\ Rides.list_rides()
      ) do
    %{
      posts: Enum.count(posts, &(not &1.draft)),
      logs: logs |> Map.drop(["draft"]) |> Map.values() |> Enum.sum(),
      log_drafts: Map.get(logs, "draft", 0),
      subscribers: length(Newsletter.list_active_emails()),
      activities: length(rides),
      signatures: Guestbook.count_guestbook_entries()
    }
  end

  defp presence(nil), do: nil

  defp presence(text) do
    case String.trim(text) do
      "" -> nil
      text -> text
    end
  end
end
