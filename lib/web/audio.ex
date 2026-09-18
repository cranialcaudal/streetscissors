defmodule Web.Audio do
  @moduledoc """
  Context for the captain's logs: recordings — video or audio — each with its
  own address at `/logs/:slug`. Independent of `Web.Blog`, which is strictly
  typed work.

  This context owns where a log's media lands on disk (`Web.Uploads`), so
  creating and deleting a log keeps the row and its directory in step. It does
  not own the transcode; that is `Web.Media.Transcoder`, which writes back
  through `mark_*` here.
  """

  import Ecto.Query, warn: false
  alias Web.Audio.Log
  alias Web.Audio.Play
  alias Web.Keywords
  alias Web.Repo
  alias Web.Uploads

  @doc "Every log, newest recording first — the admin's view, drafts and failures included."
  def list_logs do
    Repo.all(from l in Log, order_by: [desc: l.recorded_on, desc: l.seq])
  end

  @doc """
  The logs `/logs` renders: published *and* transcoded, newest first.

  Both halves matter. An entry exists from the moment its upload lands, long
  before there is anything to play, so `published` alone would put a spinner
  on the public page.
  """
  def list_ready_logs do
    Repo.all(from l in listed(), order_by: [desc: l.recorded_on, desc: l.seq])
  end

  @doc """
  Fetches one public log by its slug. Drafts and entries still transcoding are
  invisible here, so their URLs 404 rather than leaking a half-built page.
  """
  def get_ready_log_by_slug(slug) when is_binary(slug) do
    case Repo.one(from l in listed(), where: l.slug == ^slug) do
      nil -> {:error, :not_found}
      log -> {:ok, log}
    end
  end

  def get_ready_log_by_slug(_slug), do: {:error, :not_found}

  # One place decides what the public may see, and both the list and the
  # by-slug lookup compose on it — so an entry can never be reachable by
  # guessing its address while being absent from the index.
  defp listed, do: from(l in Log, where: l.published == true and l.status == "ready")

  @doc """
  Every keyword in use across public logs, most-used first. Powers the filter
  bar on `/logs`.
  """
  def list_keywords do
    list_ready_logs() |> Enum.map(&Log.keyword_list/1) |> Keywords.tally()
  end

  def get_log!(id), do: Repo.get!(Log, id)

  @doc "A log by id, or nil — safe to call with an id straight off a URL or a form."
  def get_log(id) when is_integer(id), do: Repo.get(Log, id)

  def get_log(id) when is_binary(id) do
    if id =~ ~r/^\d+$/, do: Repo.get(Log, id)
  end

  def get_log(_id), do: nil

  @doc """
  Creates a log, assigning its ordinal within the day when one isn't given.

  The count has to happen here rather than in the changeset because it needs
  the repo. Two recordings finishing in the same instant would compute the
  same ordinal; the unique index on `(recorded_on, seq)` is what actually
  decides between them, and this retries against it rather than pretending the
  race can't happen.
  """
  def create_log(attrs \\ %{}), do: insert_log(attrs, 3)

  defp insert_log(attrs, attempts_left) do
    case %Log{} |> Log.changeset(put_seq(attrs)) |> Repo.insert() do
      {:ok, log} ->
        {:ok, log}

      {:error, changeset} = error ->
        if attempts_left > 0 and ordinal_taken?(changeset),
          do: insert_log(attrs, attempts_left - 1),
          else: error
    end
  end

  defp ordinal_taken?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {field, _} -> field in [:seq, :slug] end)
  end

  defp put_seq(attrs) do
    with nil <- attr(attrs, :seq),
         %Date{} = date <- as_date(attr(attrs, :recorded_on)) do
      put_attr(attrs, :seq, next_seq(date))
    else
      _ -> attrs
    end
  end

  @doc "The next free ordinal for a day: 1 when nothing was recorded, 2 after one entry."
  def next_seq(%Date{} = date) do
    (Repo.one(from l in Log, where: l.recorded_on == ^date, select: max(l.seq)) || 0) + 1
  end

  # Attrs reach here both from forms (string keys) and from code (atom keys).
  defp attr(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))

  defp put_attr(attrs, key, value) do
    if Enum.any?(Map.keys(attrs), &is_binary/1),
      do: Map.put(attrs, Atom.to_string(key), value),
      else: Map.put(attrs, key, value)
  end

  defp as_date(%Date{} = date), do: date

  defp as_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp as_date(_value), do: nil

  def update_log(%Log{} = log, attrs) do
    log
    |> Log.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a log and the media directory it owns, so purging from the admin
  does not leave a transcode orphaned on disk forever.
  """
  def delete_log(%Log{} = log) do
    with {:ok, deleted} <- Repo.delete(log) do
      Uploads.destroy_entry(deleted.media_dir)
      {:ok, deleted}
    end
  end

  def change_log(%Log{} = log, attrs \\ %{}) do
    Log.changeset(log, attrs)
  end

  # --- Transcode state, written back by Web.Media.Transcoder ---

  @doc "Marks a log as being worked on, clearing any error from a previous attempt."
  def mark_processing(%Log{} = log) do
    update_log(log, %{status: "processing", transcode_error: nil})
  end

  @doc """
  Marks a log playable and points it at its finished media.

  If the log already had a directory — a re-transcode — the old one is
  destroyed only after the row points at the new one, so a crash in between
  leaves a stale directory rather than a log with no media.
  """
  def mark_ready(%Log{} = log, attrs) do
    previous = log.media_dir

    with {:ok, updated} <-
           update_log(log, Map.merge(attrs, %{status: "ready", transcode_error: nil})) do
      if previous && previous != updated.media_dir, do: Uploads.destroy_entry(previous)
      {:ok, updated}
    end
  end

  @doc "Marks a log's transcode as failed, keeping the reason for the admin to read."
  def mark_failed(%Log{} = log, reason) do
    update_log(log, %{status: "failed", transcode_error: to_string(reason)})
  end

  @doc """
  Every log whose transcode never finished.

  Read once on boot: a restart mid-encode would otherwise strand an entry at
  `processing` with no process left to move it.
  """
  def list_unfinished_logs do
    Repo.all(from l in Log, where: l.status in ["pending", "processing"], order_by: [asc: l.id])
  end

  # --- Totals ---

  @doc """
  Totals for each calendar year, newest first: `%{year, entries, seconds}`.

  Years are Pacific-local (via `Web.Clock`), so an entry recorded on a New
  Year's Eve evening counts toward the year it was recorded in rather than the
  UTC year it was filed under.
  """
  def yearly_totals(logs) do
    logs
    |> Enum.group_by(&year_of/1)
    |> Enum.map(fn {year, entries} ->
      %{
        year: year,
        entries: length(entries),
        seconds: entries |> Enum.map(&(&1.duration || 0)) |> Enum.sum()
      }
    end)
    |> Enum.sort_by(& &1.year, :desc)
  end

  defp year_of(%Log{recorded_at: %DateTime{} = at}), do: Web.Clock.local_today(at).year
  defp year_of(%Log{recorded_on: %Date{} = on}), do: on.year

  @doc "Total runtime across the given logs, in seconds."
  def total_runtime(logs), do: logs |> Enum.map(&(&1.duration || 0)) |> Enum.sum()

  # --- Play tracking ---

  @doc """
  Records a play event for a log. This is the "witnessed" count — the hook
  fires on the media element's `play` event, once per mount, so seeking does
  not inflate it. `<video>` and `<audio>` both fire it, so the same hook
  serves either kind.
  """
  def record_play(audio_log_id, ip_address, user_agent \\ nil) do
    %Play{}
    |> Play.changeset(%{
      audio_log_id: audio_log_id,
      ip_address: ip_address,
      user_agent: user_agent
    })
    |> Repo.insert()
  end

  @doc "The total play count for one log."
  def get_play_count(audio_log_id) do
    Repo.one(from p in Play, where: p.audio_log_id == ^audio_log_id, select: count(p.id)) || 0
  end

  @doc "Play counts for every log, as `%{audio_log_id => count}`."
  def get_all_play_counts do
    Repo.all(
      from p in Play,
        group_by: p.audio_log_id,
        select: {p.audio_log_id, count(p.id)}
    )
    |> Map.new()
  end
end
