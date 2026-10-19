defmodule Web.Happening do
  @moduledoc """
  The homepage's "Happening" section, in three parts:

    * **Now**: the training block's week and phase, the newest activity
      that is clear of every private place (its day, sport and distance:
      never a time, a place or a route), and what is being read, from
      `content/now.md` when there is one;
    * **Fresh**: the newest post, captain's log, roll and change to the
      regimen;
    * **Witnessed**: the three public pieces the most people looked at in
      the last seven days (distinct `ip_hash` in `analytics_hits`).

  Everything comes from the public functions the pages themselves read, so
  a draft, an unpublished log or an unlisted page cannot turn up; the
  witnessed list also refuses `/food`, `/england2026`, `/Christ` and
  `/admin` by name. Each part fails to nothing rather than taking the
  homepage down. The whole is kept for `:happening_ttl_ms` (ten minutes),
  since the homepage is the most visited page and the parts read files.
  """

  use GenServer

  import Ecto.Query

  alias Web.{Blog, Clock, Negatives, Pieces, Repo, Rides}
  alias Web.Analytics.Hit
  alias Web.Fitness.{Block, Changelog, Vault}
  alias Web.Rides.Units

  @table :happening
  @never ~w(/food /england2026 /Christ /christ /faith /admin)

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

  @doc "Builds the section afresh: `%{now: map, fresh: list, witnessed: list}`."
  def build(today \\ Clock.local_today()) do
    %{
      now: %{
        block: safe(fn -> block_line(today) end, nil),
        ride: safe(fn -> ride() end, nil),
        reading: safe(fn -> reading() end, nil)
      },
      fresh: safe(fn -> fresh(today) end, []),
      witnessed: safe(fn -> witnessed(today) end, [])
    }
  end

  @doc "The block's week in a line: `Get Sharp · Week 1 of 8 — Baseline`."
  def block_line(today) do
    case Block.current(today) do
      nil -> nil
      b -> "#{b.title} · Week #{b.week} of #{b.weeks} — #{b.phase}"
    end
  end

  defp ride do
    case Rides.latest_clear() do
      nil ->
        nil

      ride ->
        %{
          date: Clock.local_today(ride.started_at),
          sport: Units.sport(ride.sport),
          distance: Units.distance(ride.distance_m),
          path: "/fitness/rides/#{ride.id}"
        }
    end
  end

  # `content/now.md`: a `reading:` line in its frontmatter, else the first
  # line of its text. No file, no line.
  defp reading do
    path = Path.join(Path.dirname(Vault.base_path()), "now.md")

    with {:ok, text} <- File.read(path) do
      case Vault.parse_frontmatter(path)["reading"] do
        r when is_binary(r) and r != "" ->
          r

        _ ->
          text
          |> String.replace(~r/\A---\n.*?\n---\n?/s, "")
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim(&1, "# "))
          |> Enum.find(&(&1 != ""))
      end
    else
      _ -> nil
    end
  end

  defp fresh(today) do
    [
      safe(fn -> post() end, nil),
      safe(fn -> log() end, nil),
      safe(fn -> roll() end, nil),
      safe(fn -> regimen(today) end, nil)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp post do
    case Blog.list_posts() do
      [p | _] -> %{kind: "Writing", title: p.title, path: "/blog/#{p.slug}", date: p.date}
      [] -> nil
    end
  end

  defp log do
    case Web.Audio.list_ready_logs() do
      [l | _] ->
        %{
          kind: "Captain's log",
          title: Web.Audio.Log.title(l),
          path: "/logs/#{l.slug}",
          date: l.recorded_on
        }

      [] ->
        nil
    end
  end

  defp roll do
    Negatives.list_contact_sheets()
    |> Enum.flat_map(fn sheet ->
      case Date.from_iso8601(to_string(sheet.date)) do
        {:ok, date} ->
          [
            %{
              kind: "Negatives",
              title: "Roll #{sheet.roll}",
              path: "/negatives/roll/#{sheet.roll}",
              date: date
            }
          ]

        _ ->
          []
      end
    end)
    |> Enum.max_by(&Date.to_gregorian_days(&1.date), fn -> nil end)
  end

  defp regimen(today) do
    case Changelog.entries_until(today) do
      [e | _] -> %{kind: "Training", title: e.title, path: "/fitness", date: e.date}
      [] -> nil
    end
  end

  @doc """
  The three public pieces most people looked at in the seven days to
  `today`: `[%{kind, title, path, people}]`.
  """
  def witnessed(today) do
    since = today |> Date.add(-6) |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    from(h in Hit,
      where:
        h.inserted_at >= ^DateTime.to_naive(since) and not is_nil(h.ip_hash) and
          (like(h.path, "/blog/%") or like(h.path, "/logs/%") or like(h.path, "/negatives/roll/%")),
      group_by: h.path,
      select: {h.path, count(h.ip_hash, :distinct)},
      order_by: [desc: count(h.ip_hash, :distinct)],
      limit: 40
    )
    |> Repo.all()
    |> Enum.reject(fn {path, _} -> Enum.any?(@never, &String.starts_with?(path, &1)) end)
    |> Enum.flat_map(fn {path, people} ->
      case piece(path) do
        {:ok, piece} -> [Map.put(piece, :people, people)]
        :error -> []
      end
    end)
    # A post read at two addresses is one piece: its people are summed.
    |> Enum.group_by(& &1.path)
    |> Enum.map(fn {_path, [first | _] = same} ->
      %{first | people: Enum.sum(Enum.map(same, & &1.people))}
    end)
    |> Enum.sort_by(&{-&1.people, &1.title})
    |> Enum.take(3)
  end

  defp piece(path) do
    path = path |> String.split("?") |> hd() |> URI.decode()

    with {:ok, ref} <- Pieces.from_path(path),
         {:ok, piece} <- Pieces.resolve(ref) do
      {:ok, %{kind: kind_word(piece.kind), title: piece.title, path: piece.path}}
    else
      _ -> roll_piece(path)
    end
  end

  defp roll_piece(path) do
    with ["negatives", "roll", roll] <- String.split(path, "/", trim: true),
         %{roll: padded} <- Enum.find(Negatives.list_contact_sheets(), &(&1.roll == pad(roll))) do
      {:ok, %{kind: "Negatives", title: "Roll #{padded}", path: "/negatives/roll/#{padded}"}}
    else
      _ -> :error
    end
  end

  defp pad(roll) do
    case Integer.parse(String.replace_prefix(roll, "roll", "")) do
      {n, ""} -> n |> Integer.to_string() |> String.pad_leading(3, "0")
      _ -> roll
    end
  end

  defp kind_word(:post), do: "Writing"
  defp kind_word(:log), do: "Captain's log"
  defp kind_word(:frame), do: "Photograph"

  defp safe(fun, fallback) do
    fun.()
  rescue
    error ->
      require Logger
      Logger.warning("happening: #{Exception.message(error)}")
      fallback
  end
end
