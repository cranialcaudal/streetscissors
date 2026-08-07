defmodule Web.Pc.Index do
  @moduledoc """
  A flat index of everything the `/pc` terminal can jump to.

  The terminal's whole point is reaching a piece of content faster than clicking
  to it, addressed by the name it actually has on the machine — a contact sheet
  is `roll007_2026-07-22_120_bw`, not `ROLL007_2026_07_22_120_BW`. So entries
  carry the **real host filename, in its real case**, and matching is done
  case-insensitively rather than by mangling names into DOS shape.

  Entries deliberately store `kind` + `id` rather than a route string, so
  `WebWeb.PcLive` can build routes through `~p` sigils and keep them verified.

  Sources are the existing content functions; nothing here reads content itself:

    * `Web.Negatives.list_contact_sheets/2` and `list_frames/1`
    * `Web.Blog.list_posts/0`
    * `Web.Audio.list_published_logs/0`
  """

  @type kind :: :sheet | :frame | :post | :log

  @type entry :: %{
          kind: kind(),
          name: String.t(),
          file: String.t(),
          dir: [String.t()],
          id: map(),
          label: String.t(),
          # Bytes to render inline for `view` / `play`; nil for text content.
          media_url: String.t() | nil,
          haystack: [String.t()]
        }

  @doc """
  Builds the whole index. Called once on mount and cached in socket assigns —
  it touches the filesystem (one `File.ls` per roll) and the database.
  """
  @spec build() :: [entry()]
  def build do
    sheets = safe(fn -> Web.Negatives.list_contact_sheets() end, [])

    sheet_entries = Enum.map(sheets, &sheet_entry/1)
    frame_entries = Enum.flat_map(sheets, &frame_entries/1)
    post_entries = safe(fn -> Enum.map(Web.Blog.list_posts(), &post_entry/1) end, [])
    log_entries = safe(fn -> Enum.map(Web.Audio.list_published_logs(), &log_entry/1) end, [])

    sheet_entries ++ frame_entries ++ post_entries ++ log_entries
  end

  @doc """
  The terminal path an entry sits at, e.g.
  `"C:\\\\NEGATIVES\\\\Contact Sheets\\\\roll007_2026-07-22_120_bw.png"`.
  """
  @spec path(entry()) :: String.t()
  def path(entry), do: Enum.join(["C:" | entry.dir] ++ [entry.file], "\\")

  @doc """
  Ranked name search. Returns entries best-match first.

  Ranking is deliberately simple and predictable, because the point is that
  typing `roll007` lands somewhere without ceremony:

    0. exact name, exact filename, or an exact roll reference (`7`, `007`, `roll7`)
    1. name starts with the query
    2. name contains the query
    3. title / description contains the query
  """
  @spec search([entry()], String.t()) :: [entry()]
  def search(index, query) do
    index |> ranked(query) |> Enum.map(fn {_, entry} -> entry end)
  end

  @doc """
  Resolves a query to a single destination where that is unambiguous.

  An exact hit wins outright even when weaker matches exist, because typing a
  full name has to go straight there: `roll007_2026-07-22_120_bw` also appears
  inside every one of that roll's frame names, and offering a menu at that
  point would defeat the purpose.
  """
  @spec best([entry()], String.t()) :: {:one, entry()} | {:many, [entry()]} | :none
  def best(index, query) do
    case ranked(index, query) do
      [] ->
        :none

      [{_, entry}] ->
        {:one, entry}

      [{0, entry} | _] = all ->
        if Enum.count(all, fn {rank, _} -> rank == 0 end) == 1,
          do: {:one, entry},
          else: {:many, Enum.map(all, fn {_, e} -> e end)}

      all ->
        {:many, Enum.map(all, fn {_, e} -> e end)}
    end
  end

  defp ranked(index, query) do
    q = normalize(query)

    if q == "" do
      []
    else
      index
      |> Enum.map(&{rank(&1, q), &1})
      |> Enum.reject(fn {rank, _} -> is_nil(rank) end)
      |> Enum.sort_by(fn {rank, entry} -> {rank, kind_order(entry.kind), entry.name} end)
    end
  end

  # Within equal relevance, offer the whole thing before its parts: a roll
  # before that roll's individual frames. Sorting on the atom alone put
  # :frame ahead of :sheet, so "120" offered frame 1 as choice 1.
  defp kind_order(:sheet), do: 0
  defp kind_order(:post), do: 1
  defp kind_order(:log), do: 2
  defp kind_order(:frame), do: 3

  @doc """
  Full-text search across post bodies, log descriptions and keywords.

  Post bodies are read here rather than by the caller so each body is read at
  most once per query — the previous implementation re-read every post from
  disk for every search.
  """
  @spec grep([entry()], String.t()) :: [{entry(), String.t()}]
  def grep(index, query) do
    q = normalize(query)

    if q == "" do
      []
    else
      index
      |> Enum.flat_map(fn entry ->
        case first_hit(entry, q) do
          nil -> []
          line -> [{entry, line}]
        end
      end)
    end
  end

  # ── Entry construction ────────────────────────────────────────────

  defp sheet_entry(sheet) do
    %{
      kind: :sheet,
      name: sheet.slug,
      file: sheet.filename,
      dir: ["NEGATIVES", "Contact Sheets"],
      id: %{slug: sheet.slug, roll: sheet.roll, roll_num: sheet.roll_num},
      label: "#{sheet.format} · #{sheet.color} · #{sheet.frames} frames · #{sheet.date}",
      media_url: sheet.preview_url,
      haystack: [sheet.slug, sheet.filename, sheet.date, sheet.format, sheet.color]
    }
  end

  # Frames live under the roll's own folder, mirroring the disk layout
  # (`120 Film/roll007_.../roll007_..._03.tiff`).
  defp frame_entries(sheet) do
    sheet.slug
    |> then(fn _ -> safe(fn -> Web.Negatives.list_frames(sheet.roll) end, []) end)
    |> Enum.map(fn %{frame: frame, url: url} ->
      padded = frame |> Integer.to_string() |> String.pad_leading(2, "0")

      %{
        kind: :frame,
        name: "#{sheet.slug}_#{padded}",
        file: "#{sheet.slug}_#{padded}.tiff",
        dir: ["NEGATIVES", "#{sheet.format} Film", sheet.slug],
        id: %{roll_num: sheet.roll_num, frame: frame, slug: sheet.slug},
        label: "frame #{frame} of roll #{sheet.roll}",
        media_url: url,
        haystack: ["#{sheet.slug}_#{padded}"]
      }
    end)
  end

  defp post_entry(post) do
    %{
      kind: :post,
      name: post.slug,
      file: "#{post.slug}.md",
      dir: ["BLOG"],
      id: %{slug: post.slug},
      label: "#{post.title} · #{post.date}",
      media_url: nil,
      haystack: [post.slug, post.title | post.keywords]
    }
  end

  defp log_entry(log) do
    %{
      kind: :log,
      name: log.slug,
      file: "#{log.slug}.mp3",
      dir: ["LOGS"],
      id: %{slug: log.slug},
      label: "#{log.title} · #{log.recorded_on}",
      media_url: log.file_path,
      haystack: [log.slug, log.title | Web.Audio.Log.keyword_list(log)]
    }
  end

  # ── Matching ──────────────────────────────────────────────────────

  defp rank(entry, q) do
    name = normalize(entry.name)
    file = normalize(entry.file)

    cond do
      name == q or file == q -> 0
      roll_match?(entry, q) -> 0
      String.starts_with?(name, q) -> 1
      String.contains?(name, q) -> 2
      Enum.any?(entry.haystack, &String.contains?(normalize(&1), q)) -> 3
      true -> nil
    end
  end

  # A roll can be referred to the way a person says it: 7, 007, roll7, roll007.
  # Only whole-roll targets answer to this — a frame needs its own name.
  defp roll_match?(%{kind: :sheet, id: %{roll: roll, roll_num: roll_num}}, q) do
    stripped = String.replace_prefix(q, "roll", "")

    case Integer.parse(stripped) do
      {n, ""} -> n == roll_num
      _ -> normalize(roll) == stripped
    end
  end

  defp roll_match?(_entry, _q), do: false

  # Returns the first matching line of body text, for grep output.
  defp first_hit(%{kind: :post, id: %{slug: slug}} = entry, q) do
    body =
      case Web.Blog.get_post(slug) do
        {:ok, post} -> post.body
        _ -> ""
      end

    matching_line(body, q) || haystack_hit(entry, q)
  end

  defp first_hit(%{kind: :log, id: %{slug: slug}} = entry, q) do
    description =
      case Web.Audio.get_published_log_by_slug(slug) do
        {:ok, log} -> log.description || ""
        _ -> ""
      end

    matching_line(description, q) || haystack_hit(entry, q)
  end

  defp first_hit(entry, q), do: haystack_hit(entry, q)

  defp matching_line(text, q) do
    text
    |> String.split("\n")
    |> Enum.find(&String.contains?(normalize(&1), q))
    |> case do
      nil -> nil
      line -> line |> String.trim() |> String.slice(0, 110)
    end
  end

  defp haystack_hit(entry, q) do
    if Enum.any?(entry.haystack, &String.contains?(normalize(&1), q)),
      do: entry.label,
      else: nil
  end

  defp normalize(value), do: value |> to_string() |> String.downcase() |> String.trim()

  # The terminal must still open when a content source is unavailable — the
  # negatives volume lives outside the repo and the blog directory can be empty.
  defp safe(fun, default) do
    fun.()
  rescue
    _ -> default
  end
end
