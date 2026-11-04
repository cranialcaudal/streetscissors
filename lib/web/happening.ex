defmodule Web.Happening do
  @moduledoc """
  The newest work for the homepage: its tiles and the corner card
  (`#home-new`) read `lately`, the three newest posts with their pictures,
  the newest roll and the newest captain's log.

  Everything comes from the public functions the pages themselves read, so a
  draft or an unpublished log cannot turn up. Each part fails to nothing
  rather than taking the homepage down. The whole is kept for
  `:happening_ttl_ms` (ten minutes), since the homepage is the most visited
  page and the parts read files.
  """

  use GenServer

  alias Web.{Blog, Clock, Negatives}

  @table :happening

  # ── The cache ──────────────────────────────────────────────────────

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @doc "The section's contents, from the cache when it is fresh."
  def get do
    ttl = Application.get_env(:web, :happening_ttl_ms, :timer.minutes(10))
    now = System.monotonic_time(:millisecond)

    case lookup() do
      {at, value} when ttl > 0 and now - at < ttl ->
        value

      _ ->
        value = build()
        store(now, value)
        value
    end
  end

  defp lookup do
    case :ets.lookup(@table, :value) do
      [{:value, at, value}] -> {at, value}
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp store(at, value) do
    :ets.insert(@table, {:value, at, value})
  rescue
    ArgumentError -> :ok
  end

  # ── The parts ──────────────────────────────────────────────────────

  @doc "Builds the section afresh: `%{lately: %{posts, roll, log}}`."
  def build(_today \\ Clock.local_today()) do
    %{
      lately: %{
        posts: safe(fn -> lately_posts() end, []),
        roll: safe(fn -> lately_roll() end, nil),
        log: safe(fn -> lately_log() end, nil)
      }
    }
  end

  # ── Lately: the newest work, with its pictures, for the homepage's tiles
  # and strip. Published things only, through the same public lists the
  # pages read.

  # The three newest posts, each with its picture (Blog.cover/1). The list
  # carries no bodies, so the three are read whole.
  defp lately_posts do
    for %{slug: slug} <- Enum.take(Blog.list_posts(), 3),
        {:ok, post} <- [Blog.get_post(slug)] do
      %{
        title: post.title,
        path: "/blog/#{post.slug}",
        date: post.date,
        excerpt: post.excerpt,
        read_min: post.read_min,
        cover: Blog.cover(post)
      }
    end
  end

  # The newest roll by its sheet's date, with up to four of its prints.
  defp lately_roll do
    sheet =
      Negatives.list_contact_sheets()
      |> Enum.flat_map(fn sheet ->
        case Date.from_iso8601(to_string(sheet.date)) do
          {:ok, date} -> [{date, sheet}]
          _ -> []
        end
      end)
      |> Enum.max_by(fn {date, sheet} -> {Date.to_gregorian_days(date), sheet.roll_num} end, fn ->
        nil
      end)

    case sheet do
      nil ->
        nil

      {date, sheet} ->
        prints = safe(fn -> Negatives.list_frames(sheet.roll) end, [])
        meta = sheet.meta || %{}

        %{
          roll: sheet.roll,
          path: "/negatives/roll/#{sheet.roll}",
          date: date,
          preview_url: sheet.preview_url,
          film: Map.get(meta, :film),
          camera: Map.get(meta, :camera),
          place: Map.get(meta, :place),
          count: length(prints),
          prints:
            prints
            |> Enum.take(4)
            |> Enum.map(fn f ->
              %{
                frame: f.frame,
                url: f.url,
                path: "/negatives/roll/#{sheet.roll}/frame/#{f.frame}"
              }
            end)
        }
    end
  end

  defp lately_log do
    case Web.Logs.list_ready_logs() do
      [l | _] ->
        %{
          title: Web.Logs.Log.title(l),
          caption: l.caption,
          path: "/logs/#{l.slug}",
          poster: Web.Logs.Log.poster_url(l),
          duration: l.duration,
          video: if(Web.Logs.Log.video?(l), do: Web.Logs.Log.media_url(l)),
          date: l.recorded_on
        }

      [] ->
        nil
    end
  end

  defp safe(fun, fallback) do
    fun.()
  rescue
    error ->
      require Logger
      Logger.warning("happening: #{Exception.message(error)}")
      fallback
  end

  @doc "The kind of the single newest piece published in lately: :log, :post, or :roll."
  def latest_piece(lately) do
    candidates =
      [
        (post = List.first(lately.posts || [])) && %{kind: :post, date: post.date},
        (log = lately.log) && %{kind: :log, date: log.date},
        (roll = lately.roll) && %{kind: :roll, date: roll.date}
      ]
      |> Enum.reject(&is_nil/1)

    case Enum.max_by(candidates, &Date.to_gregorian_days(&1.date), fn -> nil end) do
      nil -> nil
      %{kind: kind} -> kind
    end
  end
end
