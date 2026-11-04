defmodule Web.Writing.Citations do
  @moduledoc """
  Pandoc-style citations (`[@boym2001, p. 41]`) in a draft, resolved against the
  draft's own reading list.

  **Keys.** A reading-list line carries its key as an Obsidian block id at the
  end of the line (`- [x] **Boym, Svetlana.** *The Future of Nostalgia* (2001). ^boym2001`),
  so Obsidian can link to it (`[[#^boym2001]]`) and nothing else in the file
  has to change. Keys are letters, digits and dashes, as block ids allow.

  **Citations.** A bracket holding one or more `@key`s, separated by `;`, each
  with an optional prefix, a `-` to leave the author out, and a locator after
  a comma: `[@boym2001]`, `[see @boym2001, p. 41; -@lowenthal1985]`. A bracket
  that is a link (`[@x](…)`) or a wiki link is left alone, as is code.

  **Rendering.** `render/2` writes each citation author-date, `(Boym 2001, p. 41)`,
  linked to its entry in a `## References` section appended after the prose,
  which lists the cited sources alphabetically as the author wrote them in the
  reading list. A key with no source is left as typed, so the preview shows it;
  `check/2` lists those, and the sources never cited.

  Nothing here knows about the blog: it reads text and reading-list items
  (`%{text: …}` as `Web.Writing.Outline.analyze/2` returns them).
  """

  @key_chars "A-Za-z0-9-"
  @block_id_re ~r/\s+\^([A-Za-z0-9-]+)\s*$/
  @bracket_re ~r/(?<![\[!\w])\[([^\[\]\n]*@[^\[\]\n]*)\](?![\(\[:])/
  @cite_part_re ~r/^(.*?)(?:^|(?<=\s))(-?)@([A-Za-z0-9][A-Za-z0-9-]*)(?:(?:,\s*|\s+)(.*))?$/s
  @fence_re ~r/^\s*(?:```|~~~)/
  @inline_code_re ~r/`[^`\n]*`/

  @type source :: %{key: String.t(), label: String.t(), year: String.t() | nil, entry: String.t()}

  @doc """
  Splits a reading-list line's text into the text without its block id and the
  key (`nil` when it has none).

      iex> Web.Writing.Citations.split_key("*Nostalgia* (2001). ^boym2001")
      {"*Nostalgia* (2001).", "boym2001"}
  """
  def split_key(text) when is_binary(text) do
    case Regex.run(@block_id_re, text, return: :index) do
      [{start, _len}, {kstart, klen}] ->
        {text |> binary_part(0, start) |> String.trim_trailing(), binary_part(text, kstart, klen)}

      nil ->
        {text, nil}
    end
  end

  @doc """
  The sources the reading list gives keys to, as a map of key to
  `%{key, label, year, entry}`: `label` is the author-date name (`Boym`,
  `Vance and Ortiz`, `Vance et al.`), `entry` the reference as the author
  wrote it, without the checkbox, call number or trailing note.
  """
  def sources(items) when is_list(items) do
    items
    |> Enum.flat_map(fn item ->
      case item_key(item) do
        nil -> []
        key -> [{key, source(key, item_text(item))}]
      end
    end)
    |> Enum.uniq_by(&elem(&1, 0))
    |> Map.new()
  end

  defp item_key(%{key: key}) when is_binary(key), do: key
  defp item_key(%{text: text}), do: text |> split_key() |> elem(1)
  defp item_key(_), do: nil

  defp item_text(%{text: text}), do: text |> split_key() |> elem(0)

  defp source(key, text) do
    parsed = Web.Writing.Zotero.parse_markdown_reading_item(text)

    %{
      key: key,
      label: short_label(parsed.authors, parsed.title),
      year: parsed.year,
      entry: entry(text)
    }
  end

  # "Boym, Svetlana" -> "Boym"; two -> "A and B"; three or "et al." -> "A et al.".
  defp short_label(authors, title) do
    names =
      authors
      |> to_string()
      |> String.replace(~r/,?\s*et al\.?$/i, " & …")
      |> String.split(~r/\s*(?:&|;|\band\b)\s*/, trim: true)
      |> Enum.map(fn name -> name |> String.split(",") |> hd() |> String.trim() end)
      |> Enum.reject(&(&1 == ""))

    case names do
      [] -> short_title(title)
      [one] -> one
      [a, "…"] -> "#{a} et al."
      [a, b] -> "#{a} and #{b}"
      [a | _] -> "#{a} et al."
    end
  end

  defp short_title(title) do
    words = title |> to_string() |> String.split(~r/\s+/, trim: true)
    short = Enum.take(words, 4) |> Enum.join(" ")
    if length(words) > 4, do: "“#{short}…”", else: "“#{short}”"
  end

  defp entry(text) do
    text
    |> String.replace(~r/\s*\*(?:[^*]*?Call Number:\s*)[^*]+\*\.?/i, "")
    |> then(fn t ->
      case String.split(t, ~r/\s+(?:—|--)\s+/, parts: 2) do
        [cit, _note] -> cit
        [cit] -> cit
      end
    end)
    |> String.replace(~r/^\*\*([^*]+?)\*\*/, "\\1")
    |> String.trim()
  end

  @doc """
  Every citation in `text`, in order, as `%{key, prefix, locator, suppress?}`.
  Code (fenced or inline) is skipped.
  """
  def citations(text) when is_binary(text) do
    text
    |> prose_lines()
    |> Enum.flat_map(fn
      {:code, _} -> []
      {:prose, line} -> line |> mask_code() |> brackets() |> Enum.flat_map(& &1.cites)
    end)
  end

  @doc """
  What the citations in `text` and the `sources` (from `sources/1`) say of each
  other: `unknown` keys cited with no source, and `uncited` source keys, in
  reading-list order when `sources` is a list of items.
  """
  def check(text, items) when is_binary(text) and is_list(items) do
    by_key = sources(items)
    cited = text |> citations() |> Enum.map(& &1.key) |> Enum.uniq()

    %{
      cited: cited,
      unknown: Enum.reject(cited, &Map.has_key?(by_key, &1)),
      uncited:
        items
        |> Enum.map(&item_key/1)
        |> Enum.reject(&(is_nil(&1) or &1 in cited))
        |> Enum.uniq()
    }
  end

  @doc """
  `{text, references}`: `text` with each resolvable citation written
  author-date and linked to `#ref-<key>`, and the `## References` markdown for
  the sources cited (`""` when nothing resolved).
  """
  def render(text, by_key) when is_binary(text) and is_map(by_key) do
    if map_size(by_key) == 0 or not String.contains?(text, "@") do
      {text, ""}
    else
      {lines, cited} =
        text
        |> prose_lines()
        |> Enum.map_reduce(MapSet.new(), fn
          {:code, line}, acc -> {line, acc}
          {:prose, line}, acc -> render_line(line, by_key, acc)
        end)

      {Enum.join(lines, "\n"), references(cited, by_key)}
    end
  end

  defp render_line(line, by_key, acc) do
    if String.contains?(line, "@") do
      masked = mask_code(line)

      # Replace from the end so earlier indices stay valid.
      masked
      |> brackets()
      |> Enum.reverse()
      |> Enum.reduce({line, acc}, fn %{range: {start, len}, cites: cites}, {l, a} ->
        if cites != [] and Enum.all?(cites, &Map.has_key?(by_key, &1.key)) do
          rendered = "(" <> Enum.map_join(cites, "; ", &cite_text(&1, by_key)) <> ")"

          {binary_part(l, 0, start) <>
             rendered <>
             binary_part(l, start + len, byte_size(l) - start - len),
           Enum.reduce(cites, a, &MapSet.put(&2, &1.key))}
        else
          {l, a}
        end
      end)
    else
      {line, acc}
    end
  end

  defp cite_text(%{key: key, prefix: prefix, locator: locator, suppress?: suppress?}, by_key) do
    %{label: label, year: year} = Map.fetch!(by_key, key)

    name =
      cond do
        suppress? and year -> year
        suppress? -> label
        year -> "#{label} #{year}"
        true -> label
      end

    [prefix, "[#{escape_link_text(name)}](#ref-#{key})" <> locator_text(locator)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp locator_text(nil), do: ""
  defp locator_text(""), do: ""
  defp locator_text(locator), do: ", " <> locator

  defp escape_link_text(text), do: String.replace(text, ["[", "]"], fn c -> "\\" <> c end)

  defp references(cited, by_key) do
    if MapSet.size(cited) == 0 do
      ""
    else
      entries =
        cited
        |> Enum.map(&Map.fetch!(by_key, &1))
        |> Enum.sort_by(&{String.downcase(&1.label), &1.year || "", &1.key})
        |> Enum.map_join("\n\n", fn s -> "#{s.entry}\n{: .ref-entry #ref-#{s.key}}" end)

      "\n\n## References\n\n" <> entries <> "\n"
    end
  end

  # Each bracket holding a citation: its byte range in the line and its parts.
  defp brackets(masked) do
    @bracket_re
    |> Regex.scan(masked, return: :index)
    |> Enum.flat_map(fn [range, {inner_start, inner_len}] ->
      inner = binary_part(masked, inner_start, inner_len)

      parts =
        inner
        |> String.split(";")
        |> Enum.map(&parse_part/1)

      if parts != [] and Enum.all?(parts, & &1),
        do: [%{range: range, cites: parts}],
        else: []
    end)
  end

  defp parse_part(part) do
    case Regex.run(@cite_part_re, String.trim(part)) do
      [_, prefix, dash, key | rest] ->
        %{
          key: key,
          prefix: blank_to_nil(prefix),
          locator: rest |> List.first() |> blank_to_nil(),
          suppress?: dash == "-"
        }

      nil ->
        nil
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(s) do
    case String.trim(s) do
      "" -> nil
      t -> t
    end
  end

  # Inline code is blanked to the same length, so a citation inside it is not
  # seen and every index still lines up with the real line.
  defp mask_code(line) do
    Regex.replace(@inline_code_re, line, fn code -> String.duplicate(" ", byte_size(code)) end)
  end

  defp prose_lines(text) do
    text
    |> String.split("\n")
    |> Enum.map_reduce(false, fn line, in_fence? ->
      cond do
        Regex.match?(@fence_re, line) -> {{:code, line}, not in_fence?}
        in_fence? -> {{:code, line}, true}
        true -> {{:prose, line}, false}
      end
    end)
    |> elem(0)
  end

  @doc """
  The cited sources as CSL JSON items (`id` the key), for Pandoc's
  `--citeproc`. Each comes from `zotero` (CSL JSON items, matched by title)
  when it is there, else from the reading-list line itself: authors, title,
  container or publisher, year, volume, issue, pages, URL and DOI.
  """
  def csl_items(items, keys, zotero \\ []) when is_list(items) do
    by_title = Map.new(zotero, &{norm_title(&1["title"]), &1})
    keys = MapSet.new(keys)

    items
    |> Enum.flat_map(fn item ->
      key = item_key(item)

      if key && MapSet.member?(keys, key) do
        text = item_text(item)
        parsed = Web.Writing.Zotero.parse_markdown_reading_item(text)

        case Map.get(by_title, norm_title(parsed.title)) do
          %{} = csl -> [Map.put(csl, "id", key)]
          nil -> [csl_from_line(key, text, parsed)]
        end
      else
        []
      end
    end)
    |> Enum.uniq_by(& &1["id"])
  end

  defp csl_from_line(key, text, parsed) do
    type =
      case parsed.item_type do
        "journalArticle" -> "article-journal"
        "newspaperArticle" -> "article-newspaper"
        "webpage" -> "webpage"
        "report" -> "report"
        "document" -> "document"
        _ -> "book"
      end

    plain = Web.Markdown.to_text(text)

    %{
      "id" => key,
      "type" => type,
      "title" => parsed.title,
      "author" => csl_names(parsed.authors),
      "issued" => parsed.year && %{"date-parts" => [[String.to_integer(parsed.year)]]},
      if(type in ["article-journal", "article-newspaper"],
        do: "container-title",
        else: "publisher"
      ) => parsed.publication,
      "volume" =>
        capture(~r/\*\s*(\d+)\s*,\s*no\./, text) || capture(~r/\*\s+(\d+),\s*no\./, plain),
      "issue" => capture(~r/\bno\.\s*(\d+)/i, plain),
      "page" => capture(~r/\):\s*(\d+\s*[–-]\s*\d+)/u, plain),
      "URL" => parsed.url,
      "DOI" => capture(~r/\b(10\.\d{4,9}\/[^\s)*]+)/, text)
    }
    |> Enum.reject(fn {_k, v} -> v in [nil, "", []] end)
    |> Map.new()
  end

  defp csl_names(authors) do
    authors
    |> to_string()
    |> String.replace(~r/,?\s*et al\.?$/i, "")
    |> String.split(~r/\s*(?:&|;|\band\b)\s*/, trim: true)
    |> Enum.map(fn name ->
      case String.split(name, ",", parts: 2) do
        [family, given] -> %{"family" => String.trim(family), "given" => String.trim(given)}
        [literal] -> %{"literal" => String.trim(literal)}
      end
    end)
  end

  defp capture(re, text) do
    case Regex.run(re, text) do
      [_, value | _] -> String.trim(value)
      nil -> nil
    end
  end

  defp norm_title(nil), do: ""

  defp norm_title(title) do
    title
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, " ")
    |> String.trim()
  end

  @doc """
  A new key for a source: its own (`citation_key`, as Zotero or Better BibTeX
  gives it) cleaned to the characters a block id allows, else the first
  author's surname and the year (`boym2001`), else the title's first word,
  with `a`, `b`, … added until it is not in `taken`.
  """
  def new_key(%{} = fields, taken) do
    base =
      clean_key(Map.get(fields, :citation_key)) ||
        clean_key(surname(Map.get(fields, :authors)) <> to_string(Map.get(fields, :year) || "")) ||
        clean_key(first_word(Map.get(fields, :title))) ||
        "source"

    taken = MapSet.new(taken)

    if MapSet.member?(taken, base) do
      Enum.find_value(?a..?z, fn c ->
        candidate = base <> <<c>>
        if not MapSet.member?(taken, candidate), do: candidate
      end) || base <> "-#{System.unique_integer([:positive])}"
    else
      base
    end
  end

  defp surname(nil), do: ""

  defp surname(authors) do
    authors
    |> to_string()
    |> String.split(~r/\s*(?:&|;|,|\band\b)\s*/, trim: true)
    |> List.first()
    |> to_string()
    |> String.split(~r/\s+/)
    |> List.last()
    |> to_string()
  end

  defp first_word(nil), do: ""

  defp first_word(title) do
    title
    |> to_string()
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(String.downcase(&1) in ~w(the a an of on)))
    |> List.first()
    |> to_string()
  end

  defp clean_key(nil), do: nil

  defp clean_key(raw) do
    cleaned =
      raw
      |> to_string()
      |> String.normalize(:nfd)
      |> String.replace(~r/[^#{@key_chars}]/u, "")
      |> String.downcase()

    if cleaned == "" or Regex.match?(~r/^\d+$/, cleaned), do: nil, else: cleaned
  end
end
