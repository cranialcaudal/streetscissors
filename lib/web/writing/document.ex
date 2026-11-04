defmodule Web.Writing.Document do
  @moduledoc """
  A markdown piece of writing read as the workbench and its exports see it: frontmatter, outline, citations and prose.

  **Frontmatter** reduces to a flat `%{key => scalar}` map. A key may be
  followed by `- item` lines (Obsidian writes lists that way); those collapse
  into the same comma-separated scalar a `key: a, b` line yields. The blog
  reads its posts with the same reader.

  **A project** is one file and the settings in its frontmatter, so Obsidian
  shows and edits them like any other key:

    * `zotero:` the Zotero folder (by name) its sources come from;
    * `csl:` a citation style for exports, a `.csl` file beside the piece or
      in the styles folder (`Web.Writing.Export`);
    * `author:`, `affiliation:`, `date:`, `target_words:`.

  `build/3` is what the workbench previews for a paper (`Web.Writing.Papers`):
  the same keys a blog post's map has, so one panel shows both.
  """

  alias Web.Writing.{Citations, Outline}

  @yaml_line_re ~r/^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$/
  @yaml_list_item_re ~r/^\s*-\s+(.+)$/

  @doc "`{meta, body}` for a file's text: its frontmatter as a flat map, and the rest."
  def split(text) when is_binary(text) do
    {yaml, body} = Web.Frontmatter.split(text)
    {parse(yaml), body}
  end

  @doc "A frontmatter block's text as a flat `%{key => scalar}` map."
  def parse(yaml) when is_binary(yaml) do
    yaml
    |> String.split(~r/\r?\n/)
    |> Enum.reduce({%{}, nil}, &parse_line/2)
    |> elem(0)
  end

  defp parse_line(line, {acc, last_key}) do
    case Regex.run(@yaml_list_item_re, line) do
      [_, item] when is_binary(last_key) ->
        {Map.update(acc, last_key, scalar(item), &join_scalar(&1, scalar(item))), last_key}

      _ ->
        case Regex.run(@yaml_line_re, line) do
          [_, key, value] -> {Map.put(acc, key, scalar(value)), key}
          nil -> {acc, last_key}
        end
    end
  end

  defp scalar(value), do: value |> String.trim() |> String.trim("\"") |> String.trim("'")

  defp join_scalar("", item), do: item
  defp join_scalar(existing, item), do: existing <> ", " <> item

  @doc """
  The piece `text` is, saved under `slug`: `%{slug, title, date, meta,
  keywords, excerpt, described, word_count, read_min, outline, raw_body, body,
  draft, related, image}`. `body` has the scaffolding taken out and the
  citations rendered (with References); `raw_body` is the file below its
  frontmatter. `draft` is always false: a paper is not published.
  """
  def build(slug, text, mtime \\ NaiveDateTime.utc_now()) do
    {meta, raw_body} = split(text)
    outline = Outline.analyze(raw_body, meta)

    {prose, references} =
      raw_body
      |> Outline.strip()
      |> Citations.render(Citations.sources(outline.research.items))

    words = prose |> String.split(~r/\s+/, trim: true) |> length()

    %{
      slug: slug,
      title: presence(meta["title"]) || title_from_slug(slug),
      date: parse_date(meta["date"], mtime),
      mtime: mtime,
      meta: meta,
      excerpt: presence(meta["description"]) || presence(meta["abstract"]) || excerpt(prose),
      described: presence(meta["description"] || meta["abstract"]) != nil,
      keywords: Web.Keywords.parse(meta["keywords"] || meta["tags"]),
      related: [],
      image: nil,
      draft: false,
      word_count: words,
      read_min: max(1, div(words, 200)),
      outline: outline,
      raw_body: raw_body,
      body: prose <> references
    }
  end

  @doc "The piece's project settings from its frontmatter (see the moduledoc)."
  def project(meta) when is_map(meta) do
    %{
      zotero: presence(meta["zotero"]),
      csl: presence(meta["csl"]),
      author: presence(meta["author"]),
      affiliation: presence(meta["affiliation"])
    }
  end

  defp parse_date(nil, mtime), do: NaiveDateTime.to_date(mtime)

  defp parse_date(value, mtime) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> NaiveDateTime.to_date(mtime)
    end
  end

  defp excerpt(body) do
    body
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.find("", fn line ->
      line != "" and not String.starts_with?(line, ["#", ">", "-", "*", "|", "!"]) and
        String.length(line) >= 40
    end)
    |> Web.Markdown.to_text()
  end

  defp presence(nil), do: nil
  defp presence(value), do: if(String.trim(value) == "", do: nil, else: value)

  defp title_from_slug(slug) do
    slug |> String.split("-") |> Enum.map_join(" ", &String.capitalize/1)
  end
end
