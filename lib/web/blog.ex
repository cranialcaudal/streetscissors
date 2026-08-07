defmodule Web.Blog do
  @moduledoc """
  Context for the streetscissors blog: markdown posts read from disk at
  request time so they can be authored directly from the Obsidian vault in
  `content/`. Posts may carry a YAML frontmatter block (title, description,
  date, keywords) — see `content/templates/blog-template.md`; every field
  falls back to filename/mtime-derived values when absent.

  The blog is strictly typed work. Spoken-word pieces are captain's logs
  (`Web.Audio`), which are DB-backed and live at `/logs` — a post no longer
  picks up a sidecar `.mp3` by filename.
  """

  alias Web.Keywords

  @default_base_path "/home/cesar/streetscissors/content/blog"

  # Frontmatter is the file-leading block delimited by `---` lines.
  @frontmatter_re ~r/\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*\r?\n?(.*)\z/s
  @yaml_line_re ~r/^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$/
  @yaml_list_item_re ~r/^\s*-\s+(.+)$/
  # Obsidian's native key is `tags`; this site's is `keywords`. Both read.
  @keyword_key_re ~r/^\s*(keywords|tags):/i

  @doc """
  Root directory blog markdown lives in. Configurable via
  `config :web, :blog_path` (sourced from the `BLOG_PATH` env var in
  `config/runtime.exs`). Falls back to the repo's content dir.
  """
  def base_path, do: Application.get_env(:web, :blog_path, @default_base_path)

  @doc """
  Lists all posts (without bodies), newest first by frontmatter date then
  file mtime. Returns `[]` when the blog directory does not exist.
  """
  def list_posts do
    path = base_path()

    if File.exists?(path) do
      path
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.map(fn filename ->
        slug = String.replace_suffix(filename, ".md", "")

        Path.join(path, filename)
        |> read_post(slug)
        |> Map.delete(:body)
      end)
      |> Enum.sort_by(
        &{Date.to_iso8601(&1.date), NaiveDateTime.to_iso8601(&1.mtime)},
        :desc
      )
    else
      []
    end
  end

  @doc """
  Fetches a single post including its markdown `:body` (frontmatter
  stripped). Guards the slug against directory traversal.
  """
  def get_post(slug) do
    with {:ok, path} <- resolve_path(slug) do
      {:ok, read_post(path, slug)}
    end
  end

  @doc """
  Every keyword in use across the blog, most-used first. Powers the filter
  bar on `/blog`.
  """
  def list_keywords do
    list_posts() |> Enum.map(& &1.keywords) |> Keywords.tally()
  end

  @doc """
  Rewrites a post's frontmatter `keywords:` line in place, preserving the
  rest of the block and the body. Used by the admin to fill in keywords for
  a post that arrived without them; the vault file stays the source of truth.

  Passing an empty list removes the key entirely.
  """
  def set_keywords(slug, keywords) do
    with {:ok, path} <- resolve_path(slug) do
      {yaml, body} = split_raw_frontmatter(File.read!(path))
      yaml = replace_keyword_lines(yaml, Keywords.parse(keywords))
      File.write(path, "---\n" <> yaml <> "\n---\n\n" <> String.trim_leading(body))
    end
  end

  def create_post(slug, content) do
    File.mkdir_p!(base_path())
    File.write(Path.join(base_path(), slug <> ".md"), content)
  end

  def delete_post(slug) do
    File.rm(Path.join(base_path(), slug <> ".md"))
  end

  defp resolve_path(slug) do
    with {:ok, rel} <- Path.safe_relative(slug <> ".md"),
         path = Path.join(base_path(), rel),
         true <- File.regular?(path) do
      {:ok, path}
    else
      _ -> {:error, :not_found}
    end
  end

  defp read_post(path, slug) do
    stat = File.stat!(path)
    mtime = NaiveDateTime.from_erl!(stat.mtime)
    {meta, body} = split_frontmatter(File.read!(path))

    words = body |> String.split(~r/\s+/, trim: true) |> length()

    %{
      slug: slug,
      title: presence(meta["title"]) || title_from_slug(slug),
      date: parse_date(meta["date"], mtime),
      mtime: mtime,
      excerpt: presence(meta["description"]) || extract_excerpt(body),
      keywords: Keywords.parse(meta["keywords"] || meta["tags"]),
      word_count: words,
      read_min: max(1, div(words, 200)),
      body: body
    }
  end

  defp split_frontmatter(content) do
    {yaml, body} = split_raw_frontmatter(content)
    {parse_yaml(yaml), body}
  end

  defp split_raw_frontmatter(content) do
    case Regex.run(@frontmatter_re, content) do
      [_, yaml, body] -> {yaml, body}
      nil -> {"", content}
    end
  end

  defp parse_yaml(yaml) do
    yaml
    |> String.split(~r/\r?\n/)
    |> Enum.reduce({%{}, nil}, &parse_yaml_line/2)
    |> elem(0)
  end

  # Frontmatter reduces to a flat `%{key => scalar}` map. A key may be
  # followed by `- item` lines (Obsidian writes tag lists that way); those
  # collapse into the same comma-separated scalar a `key: a, b` line yields,
  # so readers never have to care which form was authored.
  defp parse_yaml_line(line, {acc, last_key}) do
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

  # Replaces the keywords/tags key (and any block-list lines hanging off it)
  # with one canonical `keywords:` line, leaving every other key untouched.
  defp replace_keyword_lines(yaml, keywords) do
    new_line = if keywords == [], do: nil, else: "keywords: " <> Keywords.format(keywords)

    {lines, _dropping, seen?} =
      yaml
      |> String.split(~r/\r?\n/)
      |> Enum.reduce({[], false, false}, fn line, {acc, dropping, seen} ->
        cond do
          Regex.match?(@keyword_key_re, line) ->
            {maybe_prepend(acc, if(seen, do: nil, else: new_line)), true, true}

          dropping and Regex.match?(@yaml_list_item_re, line) ->
            {acc, true, seen}

          true ->
            {[line | acc], false, seen}
        end
      end)

    lines
    |> Enum.reverse()
    |> then(fn kept -> if seen? or is_nil(new_line), do: kept, else: kept ++ [new_line] end)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> Enum.join("\n")
  end

  defp maybe_prepend(acc, nil), do: acc
  defp maybe_prepend(acc, line), do: [line | acc]

  defp parse_date(nil, mtime), do: NaiveDateTime.to_date(mtime)

  defp parse_date(value, mtime) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> NaiveDateTime.to_date(mtime)
    end
  end

  # First substantial paragraph: skip blank lines, headers, and short lines.
  defp extract_excerpt(body) do
    body
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn line ->
      line == "" or String.starts_with?(line, "#") or String.length(line) < 40
    end)
    |> List.first("")
    |> String.slice(0, 280)
    |> then(fn text -> if String.length(text) >= 275, do: text <> "…", else: text end)
  end

  defp presence(nil), do: nil
  defp presence(value), do: if(String.trim(value) == "", do: nil, else: value)

  defp title_from_slug(slug) do
    slug
    |> String.replace("-", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
