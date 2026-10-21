defmodule Web.Editor.Complete do
  @moduledoc """
  What the admin editor offers as you type (`WebWeb.DocumentEditor`): each
  item is `%{label, detail, insert}`, and `insert` is put into the text
  exactly, so the syntax written is always the vault's own.

  | kind | after | offers | inserts |
  |---|---|---|---|
  | `"link"` (blog) | `[[` | posts (drafts too) and logs | `[Title](/blog/slug)` |
  | `"link"` (fitness) | `[[` | the exercise wiki | `[[slug\\|Name]]` |
  | `"embed"` | `![[` | rolls, a roll's frames (`012/`), rides | `![[roll012]]`, `![[roll012/3]]`, `![[ride:123]]` |
  | `"related"` | `related:` | posts, logs, frames | `post:slug`, `log:slug`, `frame:012/3` |
  | `"keyword"` | `keywords:` | the keywords in use | the keyword |

  Blog links are plain Markdown links because the blog has no `[[…]]` link
  syntax (only `![[…]]` embeds, `Web.Blog.Embeds`), and a plain link reads the
  same in Obsidian. Words match at the start of a word, as `Web.Search` does.
  This is the admin's: drafts are offered, marked.
  """

  alias Web.{Blog, Logs, Negatives, Rides}
  alias Web.Fitness.Vault
  alias Web.Logs.Log

  @limit 12

  @doc "Up to #{@limit} items for `q` of `kind` in `scope`."
  def items(q, kind, scope) do
    q = String.trim(q)

    q
    |> candidates(kind, scope)
    |> Enum.filter(&matches?(&1.match, q))
    |> Enum.take(@limit)
    |> Enum.map(&Map.delete(&1, :match))
  rescue
    # A source that can't be read (a missing folder) offers nothing; the
    # editor must never fail for a suggestion.
    _ -> []
  end

  defp candidates(_q, "link", "fitness") do
    for {_group, exercises} <- Vault.list_all_exercises(), e <- exercises do
      item(e.name, e.muscle_group, "[[#{e.slug}|#{e.name}]]", [e.name, e.slug])
    end
  end

  defp candidates(_q, "link", "blog"), do: posts(&"[#{&1.title}](/blog/#{&1.slug})") ++ logs(:link)

  defp candidates(q, "embed", "blog") do
    case frame_query(q) do
      {roll, frame} ->
        frames(roll, frame, fn padded, n -> "![[roll#{padded}/#{n}]]" end)

      nil ->
        rolls() ++ rides()
    end
  end

  defp candidates(q, "related", _scope) do
    case frame_query(String.replace_prefix(q, "frame:", "")) do
      {roll, frame} ->
        frames(roll, frame, fn padded, n -> "frame:#{padded}/#{n}" end)

      nil ->
        posts(&"post:#{&1.slug}") ++ logs(:ref)
    end
  end

  defp candidates(_q, "keyword", _scope) do
    for %{keyword: keyword, count: count} <- Web.Keywords.Index.usage() do
      item(keyword, "#{count} piece#{if count == 1, do: "", else: "s"}", keyword, [keyword])
    end
  end

  defp candidates(_q, _kind, _scope), do: []

  # ── Sources ─────────────────────────────────────────────────────────────

  defp posts(insert) do
    for post <- Blog.list_all_posts() do
      detail = if post.draft, do: "draft", else: "post"
      item(post.title || post.slug, detail, insert.(post), [post.title || "", post.slug])
    end
  end

  defp logs(how) do
    for log <- Logs.list_logs(), log.slug do
      title = Log.title(log)
      label = if log.caption in [nil, ""], do: title, else: "#{title}: #{log.caption}"

      insert =
        case how do
          :link -> "[#{title}](/logs/#{log.slug})"
          :ref -> "log:#{log.slug}"
        end

      item(label, "log", insert, [label, log.slug])
    end
  end

  defp rolls do
    Negatives.list_contact_sheets()
    |> Enum.sort_by(& &1.roll_num, :desc)
    |> Enum.map(fn sheet ->
      detail = Enum.join(Enum.reject([sheet.format, to_string(sheet.date || "")], &(&1 in [nil, ""])), ", ")
      item("Roll #{sheet.roll}", detail, "![[roll#{sheet.roll}]]", [
        "roll#{sheet.roll}",
        sheet.roll,
        to_string(sheet.roll_num)
      ])
    end)
  end

  # A roll's frames whose number begins with what was typed after the slash.
  # The query has already chosen them, so they skip the word match.
  defp frames(roll, frame_prefix, insert) do
    padded = Negatives.Roll.pad(roll)

    for frame <- Negatives.list_frames(padded),
        n = to_string(frame.frame),
        String.starts_with?(n, frame_prefix) do
      %{label: "Roll #{padded}, frame #{n}", detail: "frame", insert: insert.(padded, n), match: :any}
    end
  end

  defp rides do
    for ride <- Rides.list_rides() do
      date = ride.started_at && Calendar.strftime(ride.started_at, "%Y-%m-%d")
      item(ride.name || "Ride #{ride.id}", Enum.join(Enum.reject(["ride", date], &is_nil/1), ", "),
        "![[ride:#{ride.id}]]", [ride.name || "", "ride", to_string(ride.id)])
    end
  end

  defp item(label, detail, insert, match),
    do: %{label: label, detail: detail, insert: insert, match: Enum.join(match, " ")}

  # `012/`, `roll12/3`: the frames of a roll.
  defp frame_query(q) do
    case Regex.run(~r/\A(?:roll)?0*(\d{1,4})\s*\/\s*(\d*)\z/i, q) do
      [_, roll, frame] -> {roll, frame}
      _ -> nil
    end
  end

  # Every word of `q` begins some word of the candidate. An empty query
  # matches everything.
  defp matches?(_text, ""), do: true
  defp matches?(:any, _q), do: true

  defp matches?(text, q) do
    words = text |> String.downcase() |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)

    q
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.all?(fn w -> Enum.any?(words, &String.starts_with?(&1, w)) end)
  end
end
