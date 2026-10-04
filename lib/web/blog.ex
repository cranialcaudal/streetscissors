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

  **Drafts.** A post whose frontmatter says `draft: true` is off the site:
  `list_posts/0` and `get_post/1` do not see it, so neither does anything
  built on them — the index, the feeds, the sitemap, the almanac, the `/pc`
  terminal, letters. Only the admin asks for drafts, with `list_all_posts/0`
  and `get_post(slug, drafts: true)`.

  **Editing from the admin.** `read_source/1` hands back a file's text with a
  revision (the SHA-256 of what is on disk), and `write_source/4` refuses to
  save over a file whose revision has moved on. The vault is edited in
  Obsidian as well, and the site does not get to win that race by being last.
  """

  alias Web.Keywords

  @default_base_path "content/blog"

  # Frontmatter is the file-leading block delimited by `---` lines.
  @frontmatter_re ~r/\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*\r?\n?(.*)\z/s
  @yaml_line_re ~r/^([A-Za-z_][A-Za-z0-9_-]*):\s*(.*)$/
  @yaml_list_item_re ~r/^\s*-\s+(.+)$/
  # Obsidian's native key is `tags`; this site's is `keywords`. Both read.
  @keyword_key_re ~r/^\s*(keywords|tags):/i

  @default_template """
  ---
  title: "Your Blog Post Title"
  description: "A short, 1-2 sentence description for the index page."
  date: "2026-01-01"
  keywords:
  ---

  Start writing your post here...
  """

  @doc """
  Root directory blog markdown lives in. Configurable via
  `config :web, :blog_path` (sourced from the `BLOG_PATH` env var in
  `config/runtime.exs`). Falls back to the repo's content dir.
  """
  def base_path, do: Application.get_env(:web, :blog_path) || Path.expand(@default_base_path)

  @doc """
  Lists the published posts (without bodies), newest first by frontmatter
  date then file mtime. Returns `[]` when the blog directory does not exist.
  """
  def list_posts, do: Enum.reject(list_all_posts(), & &1.draft)

  @doc "Every post on disk, drafts included, in the same order. For the admin."
  def list_all_posts do
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

  A draft is `{:error, :not_found}`, the same as a post that does not exist,
  unless `drafts: true` is passed.
  """
  def get_post(slug, opts \\ []) do
    with {:ok, path} <- resolve_path(slug),
         post = read_post(path, slug),
         true <- not post.draft or Keyword.get(opts, :drafts, false) do
      {:ok, post}
    else
      _ -> {:error, :not_found}
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

  @doc """
  Starts a post from the vault's own template, as a draft dated today.

  The template is `content/templates/blog-template.md` — the one Obsidian
  inserts — so a post begun here carries the same frontmatter as one begun
  there. Returns `{:ok, slug}`, `{:error, :exists}` when a file by that name
  is already there, or `{:error, :blank}` for a title that slugifies to
  nothing.
  """
  def create_draft(title, today \\ Web.Clock.local_today()) do
    slug = Keywords.slugify(title)
    path = Path.join(base_path(), slug <> ".md")

    cond do
      slug == "" ->
        {:error, :blank}

      File.exists?(path) ->
        {:error, :exists}

      true ->
        {yaml, body} = split_raw_frontmatter(template())

        yaml =
          yaml
          |> replace_key("title", ~s("#{String.replace(String.trim(title), "\"", "'")}"))
          |> replace_key("date", ~s("#{Date.to_iso8601(today)}"))
          |> replace_key("description", ~s(""))
          # The template's sample keywords go, in whichever form it wrote
          # them; an empty key stays, as a place to type them.
          |> replace_keyword_lines([])
          |> replace_key("keywords", "")
          |> replace_key("draft", "true")

        File.mkdir_p!(base_path())

        with :ok <- File.write(path, join_frontmatter(yaml, body)) do
          {:ok, slug}
        end
    end
  end

  @doc """
  Publishes a draft (`false`) or takes a post back off the site (`true`) by
  rewriting its `draft:` line. Publishing removes the key rather than writing
  `draft: false`: a published post reads the same as one that never was one.
  """
  def set_draft(slug, draft?) when is_boolean(draft?) do
    with {:ok, path} <- resolve_path(slug) do
      write_atomic(path, mark_draft(File.read!(path), draft?))
    end
  end

  @doc """
  A post's file as it is on disk, with the revision `write_source/4` checks.

  Returns `{:ok, %{content: text, revision: sha}}`.
  """
  def read_source(slug) do
    with {:ok, path} <- resolve_path(slug) do
      content = File.read!(path)
      {:ok, %{content: content, revision: revision(content)}}
    end
  end

  @doc """
  Saves a post's whole file, but only over the revision it was opened at.

  Returns `{:ok, revision}` with the new revision, or
  `{:error, :conflict, %{content: text, revision: sha}}` with what is on disk
  when the file has changed since `revision` was read — an edit made in
  Obsidian in the meantime, most likely.

  `force: true` saves anyway, and first moves the version it replaces into
  the vault's `.trash/`, where Obsidian keeps what it deletes. Overwriting is
  sometimes the right call; destroying the other edit never is.
  """
  def write_source(slug, content, revision, opts \\ []) do
    with {:ok, path} <- resolve_path(slug) do
      on_disk = File.read!(path)

      cond do
        revision(on_disk) == revision ->
          save(path, content)

        Keyword.get(opts, :force, false) ->
          keep_replaced(slug, on_disk)
          save(path, content)

        true ->
          {:error, :conflict, %{content: on_disk, revision: revision(on_disk)}}
      end
    end
  end

  # A post with nothing in its frontmatter has no frontmatter block.
  defp join_frontmatter(yaml, body) do
    if String.trim(yaml) == "",
      do: String.trim_leading(body),
      else: "---\n" <> yaml <> "\n---\n\n" <> String.trim_leading(body)
  end

  defp save(path, content) do
    with :ok <- write_atomic(path, content), do: {:ok, revision(content)}
  end

  # Written beside the file and renamed over it, so nothing reading the vault
  # at that moment — Obsidian, a request — ever sees half a post.
  defp write_atomic(path, content) do
    tmp = path <> ".saving"

    with :ok <- File.write(tmp, content),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      error ->
        File.rm(tmp)
        error
    end
  end

  defp keep_replaced(slug, content) do
    trash = Path.join(Path.dirname(base_path()), ".trash")
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")

    File.mkdir_p!(trash)
    File.write!(Path.join(trash, "#{Path.basename(slug)} (replaced #{stamp}).md"), content)
  end

  defp revision(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  defp template do
    path = Path.join([Path.dirname(base_path()), "templates", "blog-template.md"])

    case File.read(path) do
      {:ok, template} -> template
      {:error, _} -> @default_template
    end
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

  @doc """
  A post as `text` would read if it were saved under `slug`: the same map
  `get_post/2` returns, built without touching the disk. The admin's editor
  previews from this, so what it shows is what the site will parse.
  """
  def preview(slug, text, now \\ NaiveDateTime.utc_now()), do: build_post(slug, text, now)

  @doc """
  A post's body as the page shows it: markdown through Earmark, then the
  vault's embeds (`![[roll012]]`, `![[ride:123]]`) through `Web.Blog.Embeds`.
  """
  def to_html(body) do
    html =
      case Earmark.as_html(body, gfm: true) do
        {:ok, html, _} -> html
        {:error, html, _} -> html
      end

    Web.Blog.Embeds.transform(html)
  end

  @doc """
  `text` with its `draft:` line set or removed. Pure: `set_draft/2` and the
  editor's "Publish" both go through it.
  """
  def mark_draft(text, draft?) when is_boolean(draft?) do
    {yaml, body} = split_raw_frontmatter(text)
    join_frontmatter(replace_key(yaml, "draft", if(draft?, do: "true")), body)
  end

  defp read_post(path, slug) do
    stat = File.stat!(path)
    build_post(slug, File.read!(path), NaiveDateTime.from_erl!(stat.mtime))
  end

  defp build_post(slug, text, mtime) do
    {meta, body} = split_frontmatter(text)

    words = body |> String.split(~r/\s+/, trim: true) |> length()

    %{
      slug: slug,
      title: presence(meta["title"]) || title_from_slug(slug),
      date: parse_date(meta["date"], mtime),
      mtime: mtime,
      excerpt: presence(meta["description"]) || extract_excerpt(body),
      keywords: Keywords.parse(meta["keywords"] || meta["tags"]),
      draft: truthy?(meta["draft"]),
      # Whether the excerpt is the author's own line or the first paragraph
      # standing in for one (the admin's content health asks).
      described: presence(meta["description"]) != nil,
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

  # Sets one scalar key in a frontmatter block: rewritten where it stands,
  # appended when it is new, removed when `value` is nil. Comment lines and
  # every other key are left exactly as written.
  defp replace_key(yaml, key, value) do
    line = value && String.trim_trailing("#{key}: #{value}")
    key_re = Regex.compile!("^\\s*#{Regex.escape(key)}:", "i")
    lines = String.split(yaml, ~r/\r?\n/)

    if Enum.any?(lines, &Regex.match?(key_re, &1)) do
      lines
      |> Enum.flat_map(fn existing ->
        cond do
          not Regex.match?(key_re, existing) -> [existing]
          is_nil(line) -> []
          true -> [line]
        end
      end)
      |> Enum.join("\n")
    else
      [yaml, line] |> Enum.reject(&(is_nil(&1) or &1 == "")) |> Enum.join("\n")
    end
  end

  defp truthy?(nil), do: false
  defp truthy?(value), do: String.downcase(String.trim(value)) in ~w(true yes on 1)

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
