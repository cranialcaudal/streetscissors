defmodule Web.Writing.Outline do
  @moduledoc """
  Outline-to-draft scaffolding inside one markdown file: a blog post or a paper.

  A piece can be researched, outlined and written in one file (a post in
  `content/blog/`, a paper in a `Web.Writing.Papers` folder):

    1. **Reading list at the top** (`## Reading List` or `## ... Research Checklist`),
       where each `- [ ]` source can be followed by a `> [!thought]` block holding
       what the author thought about that reading in their own phrasings. A
       source's citation key is an Obsidian block id at the end of its line
       (`^boym2001`), cited in the prose as `[@boym2001, p. 41]`
       (`Web.Writing.Citations`).
    2. **Section headings with word goals** (`## I. Introduction (~250 words)`),
       each holding `> [!beat] Title` blocks alongside `> [!thought]` phrasings
       to weave into the draft paragraphs written beneath them.

  `strip/1` removes the reading list, beats, thoughts, `(~250 words)` heading
  suffixes, and unwritten section headers before the post is counted, excerpted
  or rendered. `analyze/2` reads the same text for the workbench: sources read, thoughts recorded, beats answered, and
  drafted words against each section's goal. `from_blueprint/2` turns a raw
  markdown blueprint into a single-file draft with the reading list at the top.
  """

  alias Web.Keywords
  alias Web.Writing.Citations

  @heading_re ~r/^(?:\#{1,6})\s+(.+?)\s*\#*\s*$/
  @heading_parts_re ~r/^(\#{1,6})\s+(.+?)\s*\#*\s*$/
  @target_suffix_re ~r/\s*\(~?([\d,]+)\s+words?(?:\s*\/[^)]*)?\)\s*$/i
  @blueprint_words_re ~r/\(~?([\d,]+)\s+words?(?:\s*\/[^)]*)?\)/i
  @research_heading_re ~r/^(?:master\s+.*?\s+)?(?:research\s+checklist|reading\s+list)\b/i
  @beat_start_re ~r/^>\s*\[!beat\]-?\s*(.*)$/i
  @thought_start_re ~r/^>\s*\[!(?:thought|voice)\]-?\s*(.*)$/i
  @research_callout_re ~r/^>\s*\[!research\]-?\s*(.*)$/i
  @blockquote_cont_re ~r/^>(?:\s?(.*))?$/
  @task_item_re ~r/^\s*[-*]\s+\[([ xX])\]\s+(.+)$/
  @hr_re ~r/^\s*(?:---+|\*\*\*+|___+)\s*$/
  @fence_re ~r/^\s*(?:```|~~~)/

  @doc """
  Removes the reading list / research checklist section, `> [!beat]`,
  `> [!thought]`, `> [!voice]` and `> [!research]` callouts, `(~250 words)`
  heading suffixes, and headings whose sections hold no drafted prose yet.

  A post with no outline marks is returned unchanged.
  """
  def strip(body) when is_binary(body) do
    if has_outline_marks?(body) do
      body
      |> parse_blocks()
      |> strip_blocks()
    else
      body
    end
  end

  @doc """
  Reads the outline and reading-list telemetry from `body` and frontmatter `meta`:

      %{
        has_outline?: boolean(),
        target_words: non_neg_integer() | nil,
        drafted_words: non_neg_integer(),
        beats_total: non_neg_integer(),
        beats_done: non_neg_integer(),
        sections: [%{title, level, target_words, drafted_words, beats_total, beats_done,
                     beats, first_sentence, cites}],
        research: %{
          total: non_neg_integer(),
          checked: non_neg_integer(),
          with_thoughts: non_neg_integer(),
          items: [%{done?: boolean(), text: String.t(), key: String.t() | nil,
                    thoughts: [String.t()], used_in: [String.t()]}]
        }
      }
  """
  def analyze(body, meta \\ %{}) when is_binary(body) and is_map(meta) do
    blocks = parse_blocks(body)
    sections = build_sections(blocks)
    research = build_research(blocks)

    section_target_sum =
      sections
      |> Enum.map(&(&1.target_words || 0))
      |> Enum.sum()

    explicit_target = parse_int(meta["target_words"])

    target_words =
      cond do
        is_integer(explicit_target) and explicit_target > 0 -> explicit_target
        section_target_sum > 0 -> section_target_sum
        true -> nil
      end

    research = link_research(research, sections)

    beats_total = Enum.sum(Enum.map(sections, & &1.beats_total))
    beats_done = Enum.sum(Enum.map(sections, & &1.beats_done))

    drafted_words =
      body
      |> strip()
      |> count_words()

    has_outline? =
      beats_total > 0 or research.total > 0 or not is_nil(target_words)

    %{
      has_outline?: has_outline?,
      target_words: target_words,
      drafted_words: drafted_words,
      beats_total: beats_total,
      beats_done: beats_done,
      sections: Enum.reject(sections, & &1.implicit?),
      research: research
    }
  end

  @doc """
  Renders `body` to HTML with `> [!beat]` blocks and their paired `> [!thought]`
  phrasings shown in place as `<aside>` cards, so the author can preview
  unwritten beats alongside their reading notes and drafted paragraphs in
  the workbench. `to_html` renders the prose between them (the blog passes
  its own, which knows the vault's embeds).
  """
  def render_with_beats(body, to_html \\ &Web.Markdown.to_html/1) when is_binary(body) do
    blocks = parse_blocks(body)
    beats_with_state = mark_beat_states(blocks)

    beats_with_state
    |> Enum.flat_map(fn
      {:research_heading, _, _} ->
        []

      {:research_line, _} ->
        []

      {:research_callout, _, _} ->
        []

      {:thought, %{lines: lines}} ->
        thought_html = lines |> Enum.join("\n") |> Web.Markdown.to_html()

        [
          """
          <aside class="adm-beat-card adm-beat-card--thought">
            <header class="adm-beat-head">
              <strong class="adm-beat-title">My phrasing / thought</strong>
              <span class="adm-pill adm-pill--quiet">voice</span>
            </header>
            <div class="adm-beat-body">#{thought_html}</div>
          </aside>
          """
        ]

      {:heading, level, raw_title, clean_title, target} ->
        hashes = String.duplicate("#", level)
        suffix = if target, do: " *(~#{target} words)*", else: ""
        ["#{hashes} #{clean_title || raw_title}#{suffix}"]

      {:beat,
       %{
         title: title,
         body_lines: lines,
         thoughts: thoughts,
         drafted?: drafted?,
         words: words
       }} ->
        prompt_html = lines |> Enum.join("\n") |> Web.Markdown.to_html()

        thoughts_html =
          if thoughts == [] do
            ""
          else
            joined = thoughts |> Enum.join("\n\n") |> Web.Markdown.to_html()

            """
            <div class="adm-beat-thoughts">
              <p class="adm-beat-thoughts-label">My thoughts &amp; phrasings</p>
              #{joined}
            </div>
            """
          end

        status =
          if drafted?,
            do: ~s(<span class="adm-pill adm-pill--live">drafted · #{words}w</span>),
            else: ~s(<span class="adm-pill adm-pill--draft">beat</span>)

        title_html = Phoenix.HTML.html_escape(title) |> Phoenix.HTML.safe_to_string()

        [
          """
          <aside class="adm-beat-card" data-drafted="#{drafted?}">
            <header class="adm-beat-head">
              <strong class="adm-beat-title">#{title_html}</strong>
              #{status}
            </header>
            <div class="adm-beat-body">#{prompt_html}</div>
            #{thoughts_html}
          </aside>
          """
        ]

      {:prose, line} ->
        [line]
    end)
    |> Enum.join("\n")
    |> to_html.()
  end

  @doc """
  Copies the `> [!thought]` phrasings attached to `beat_title` (or a reading
  note's thought) into a prose paragraph directly beneath that beat's callout
  block in `text`, so the author can shape their own phrasings into the draft.
  """
  def seed_beat_thoughts(text, beat_title) when is_binary(text) and is_binary(beat_title) do
    lines = String.split(text, ~r/\r?\n/)
    target_norm = normalize_title(beat_title)
    do_seed_beat(lines, target_norm, [])
  end

  @doc """
  Appends a `> [!thought]` phrasing block directly beneath `beat_title` in
  `text`.
  """
  def add_beat_thought(text, beat_title, thought)
      when is_binary(text) and is_binary(beat_title) and is_binary(thought) do
    trimmed = String.trim(thought)

    if trimmed == "" do
      text
    else
      lines = String.split(text, ~r/\r?\n/)
      target_norm = normalize_title(beat_title)
      do_add_beat_thought(lines, target_norm, format_thought_callout(trimmed), [])
    end
  end

  @doc """
  Appends a `> [!thought]` note beneath the `index`-th (0-based) reading-list
  checklist item in `text`.
  """
  def add_reading_thought(text, index, thought)
      when is_binary(text) and is_integer(index) and is_binary(thought) do
    trimmed = String.trim(thought)

    if trimmed == "" or index < 0 do
      text
    else
      lines = String.split(text, ~r/\r?\n/)
      do_add_reading_thought(lines, index, 0, format_thought_callout(trimmed), [])
    end
  end

  @doc """
  Toggles `- [ ]` ↔ `- [x]` on the `index`-th (0-based) reading-list checklist
  item in `text`.
  """
  def toggle_reading_item(text, index) when is_binary(text) and is_integer(index) do
    if index < 0 do
      text
    else
      lines = String.split(text, ~r/\r?\n/)
      do_toggle_reading_item(lines, index, 0, [])
    end
  end

  @doc """
  Inserts formatted reading-list entries (e.g. from `Web.Writing.Zotero.format_reading_item/1`),
  each given a citation key not already in the list (`Web.Writing.Citations.new_key/2`),
  into the top `## Reading List` / `## ... Research Checklist` section of `text`.

  If `text` has no reading list section yet, creates `## Reading List` right
  after the frontmatter block. Items whose titles are already present in the
  reading list are skipped.
  """
  def insert_reading_items(text, items) when is_binary(text) and is_list(items) do
    taken = reading_keys(text)

    {new_blocks, _taken} =
      items
      |> Enum.reject(fn item ->
        title = Map.get(item, :title, "")
        title != "" and String.contains?(String.downcase(text), String.downcase(title))
      end)
      |> Enum.map_reduce(taken, fn item, taken ->
        key = Citations.new_key(item, taken)
        {Web.Writing.Zotero.format_reading_item(Map.put(item, :cite_key, key)), [key | taken]}
      end)

    if new_blocks == [] do
      text
    else
      block_str = Enum.join(new_blocks, "\n")
      insert_into_reading_section(text, block_str)
    end
  end

  @doc """
  The citation key of the `index`-th (0-based) reading-list item, giving it one
  (` ^key` at the end of its line, from `Web.Writing.Citations.new_key/2`) if
  it has none. Returns `{text, key}`, or `{text, nil}` when there is no such item.
  """
  def ensure_reading_key(text, index) when is_binary(text) and is_integer(index) do
    case Enum.at(analyze(text).research.items, index) do
      nil ->
        {text, nil}

      %{key: key} when is_binary(key) ->
        {text, key}

      item ->
        key =
          Citations.new_key(
            Web.Writing.Zotero.parse_markdown_reading_item(item.text),
            reading_keys(text)
          )

        {append_task_key(text, index, key), key}
    end
  end

  @doc "Gives every reading-list item without a citation key one (see `ensure_reading_key/2`)."
  def key_reading_items(text) when is_binary(text) do
    analyze(text).research.items
    |> Enum.with_index()
    |> Enum.reduce(text, fn
      {%{key: nil}, index}, acc -> acc |> ensure_reading_key(index) |> elem(0)
      _, acc -> acc
    end)
  end

  @doc """
  The key of the reading-list item whose title is `title` (case-insensitive,
  matched within the item's text), giving it one if it has none; `nil` when no
  item names it. Returns `{text, key}`.
  """
  def reading_key_for_title(text, title) when is_binary(text) and is_binary(title) do
    wanted = String.downcase(String.trim(title))

    index =
      wanted != "" &&
        Enum.find_index(analyze(text).research.items, fn item ->
          String.contains?(String.downcase(item.text), wanted)
        end)

    if is_integer(index), do: ensure_reading_key(text, index), else: {text, nil}
  end

  defp reading_keys(text) do
    analyze(text).research.items |> Enum.map(& &1.key) |> Enum.reject(&is_nil/1)
  end

  # The task lines are counted as toggle_reading_item/2 counts them.
  defp append_task_key(text, index, key) do
    text
    |> String.split(~r/\r?\n/)
    |> Enum.map_reduce(0, fn line, n ->
      if Regex.match?(@task_item_re, line) do
        {if(n == index, do: String.trim_trailing(line) <> " ^" <> key, else: line), n + 1}
      else
        {line, n}
      end
    end)
    |> elem(0)
    |> Enum.join("\n")
  end

  @doc """
  Converts a raw markdown essay blueprint (working title, thesis/lede, section
  headers with `(~250 words)`, bulleted beats, and a research checklist) into a
  single-file draft with frontmatter, the **Reading List / Research Checklist at
  the top**, and `> [!beat]` blocks in each section.

  Returns `{:ok, %{title: title, slug: slug, content: markdown}}` or
  `{:error, :blank}` when no title or content is given.
  """
  def from_blueprint(raw, today \\ Web.Clock.local_today()) when is_binary(raw) do
    trimmed = String.trim(raw)

    if trimmed == "" do
      {:error, :blank}
    else
      lines = String.split(trimmed, ~r/\r?\n/)
      {meta_info, body_lines} = extract_blueprint_header(lines)
      {outline_body, research_body} = convert_blueprint_body(body_lines)

      title = meta_info.title || first_heading_title(lines) || "Untitled Essay"
      slug = Keywords.slugify(title)

      if slug == "" do
        {:error, :blank}
      else
        target = meta_info.target_words || sum_section_targets(outline_body)
        description = meta_info.description || ""

        frontmatter_lines =
          [
            "---",
            ~s(title: "#{escape_quotes(title)}"),
            ~s(description: "#{escape_quotes(description)}"),
            ~s(date: "#{Date.to_iso8601(today)}"),
            "keywords: essay",
            if(target && target > 0, do: "target_words: #{target}"),
            "draft: true",
            "---"
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join("\n")

        combined_body =
          [String.trim(research_body), String.trim(outline_body)]
          |> Enum.reject(&(&1 == ""))
          |> Enum.join("\n\n")

        content = frontmatter_lines <> "\n\n" <> combined_body <> "\n"
        {:ok, %{title: title, slug: slug, content: content}}
      end
    end
  end

  # ── Parsing blocks ────────────────────────────────────────────────────

  defp has_outline_marks?(body) do
    Regex.match?(~r/^>\s*\[!(?:beat|thought|voice|research)\]/im, body) or
      Regex.match?(
        ~r/^\#{1,6}\s+(?:master\s+.*?\s+)?(?:research\s+checklist|reading\s+list)\b/im,
        body
      ) or
      Regex.match?(~r/^\#{1,6}\s+.+\(~?[\d,]+\s+words?(?:\s*\/[^)]*)?\)\s*$/im, body)
  end

  defp parse_blocks(body) do
    lines = String.split(body, ~r/\r?\n/)
    do_parse_blocks(lines, false, nil, [])
  end

  defp do_parse_blocks([], _fenced?, _research_level, acc), do: Enum.reverse(acc)

  defp do_parse_blocks([line | rest], fenced?, research_level, acc) do
    toggles_fence? = Regex.match?(@fence_re, line)
    next_fenced? = if toggles_fence?, do: not fenced?, else: fenced?

    cond do
      fenced? or toggles_fence? ->
        tag = if research_level, do: {:research_line, line}, else: {:prose, line}
        do_parse_blocks(rest, next_fenced?, research_level, [tag | acc])

      match = Regex.run(@heading_parts_re, line) ->
        [_, hashes, raw_title] = match
        level = String.length(hashes)
        {clean_title, target} = extract_target_words(raw_title)

        cond do
          Regex.match?(@research_heading_re, clean_title) ->
            do_parse_blocks(rest, false, level, [{:research_heading, level, clean_title} | acc])

          not is_nil(research_level) and level > research_level ->
            do_parse_blocks(rest, false, research_level, [{:research_line, line} | acc])

          true ->
            block = {:heading, level, raw_title, clean_title, target}
            do_parse_blocks(rest, false, nil, [block | acc])
        end

      not is_nil(research_level) ->
        do_parse_blocks(rest, false, research_level, [{:research_line, line} | acc])

      match = Regex.run(@beat_start_re, line) ->
        [_, header_rest] = match
        {cont_lines, remaining} = collect_callout_lines(rest, [])
        {checked?, beat_title, first_body} = parse_beat_header(header_rest)
        body_lines = if first_body, do: [first_body | cont_lines], else: cont_lines

        beat = %{
          title: beat_title,
          checked?: checked?,
          body_lines: body_lines,
          thoughts: []
        }

        do_parse_blocks(remaining, false, nil, [{:beat, beat} | acc])

      match = Regex.run(@thought_start_re, line) ->
        [_, header_rest] = match
        {cont_lines, remaining} = collect_callout_lines(rest, [])
        trimmed_head = String.trim(header_rest)
        lines = if trimmed_head != "", do: [trimmed_head | cont_lines], else: cont_lines
        thought_text = lines |> Enum.join("\n") |> String.trim()

        next_acc =
          if thought_text != "",
            do: [{:thought, %{lines: lines, text: thought_text}} | acc],
            else: acc

        do_parse_blocks(remaining, false, nil, next_acc)

      match = Regex.run(@research_callout_re, line) ->
        [_, header_rest] = match
        {cont_lines, remaining} = collect_callout_lines(rest, [])

        do_parse_blocks(remaining, false, nil, [
          {:research_callout, String.trim(header_rest), cont_lines} | acc
        ])

      true ->
        do_parse_blocks(rest, false, nil, [{:prose, line} | acc])
    end
  end

  defp collect_callout_lines([line | rest] = all, acc) do
    case Regex.run(@blockquote_cont_re, line) do
      [_, inner] -> collect_callout_lines(rest, [inner | acc])
      [_] -> collect_callout_lines(rest, ["" | acc])
      nil -> {Enum.reverse(acc), all}
    end
  end

  defp collect_callout_lines([], acc), do: {Enum.reverse(acc), []}

  defp parse_beat_header(raw) do
    trimmed = String.trim(raw)

    {checked?, rest} =
      case Regex.run(~r/^\[([ xX])\]\s*(.*)$/, trimmed) do
        [_, mark, after_box] -> {String.downcase(mark) == "x", String.trim(after_box)}
        nil -> {false, trimmed}
      end

    case String.split(rest, ~r/:\s+/, parts: 2) do
      [title, inline_body] when title != "" and inline_body != "" ->
        {checked?, strip_md_formatting(title), inline_body}

      _ ->
        title = if rest == "", do: "Beat", else: strip_md_formatting(rest)
        {checked?, title, nil}
    end
  end

  defp strip_md_formatting(text) do
    text
    |> String.trim()
    # Only a wrapper around the whole title: `**Title**` or `*Title*`, never
    # the closing mark of an italic inside it (`Kukkonen’s *Designs*`).
    |> String.replace(~r/^\*\*(.+)\*\*$/, "\\1")
    |> String.replace(~r/^\*([^*].*)\*$/, "\\1")
    |> String.trim_trailing(":")
  end

  defp extract_target_words(raw_title) do
    case Regex.run(@target_suffix_re, raw_title) do
      [full_match, digits] ->
        clean =
          raw_title
          |> String.slice(0, String.length(raw_title) - String.length(full_match))
          |> String.trim()

        {clean, parse_int(digits)}

      nil ->
        {String.trim(raw_title), nil}
    end
  end

  # ── Stripping blocks for clean preview & public view ──────────────────

  defp strip_blocks(blocks) do
    blocks
    |> group_by_section()
    |> Enum.flat_map(fn section ->
      prose_lines =
        section.items
        |> Enum.flat_map(fn
          {:prose, line} -> [line]
          _ -> []
        end)

      prose_without_rules =
        prose_lines
        |> Enum.reject(&Regex.match?(@hr_re, &1))
        |> Enum.join("\n")

      has_words? = count_words(prose_without_rules) > 0

      case section.heading do
        nil ->
          if has_words?, do: trim_orphaned_rules(prose_lines), else: []

        {:heading, level, _raw, clean_title, _target} ->
          if has_words? do
            hashes = String.duplicate("#", level)
            ["#{hashes} #{clean_title}" | trim_orphaned_rules(prose_lines)]
          else
            []
          end
      end
    end)
    |> collapse_blank_runs()
    |> Enum.join("\n")
    |> String.trim()
  end

  defp trim_orphaned_rules(lines) do
    lines
    |> drop_leading_blank_and_rules()
    |> Enum.reverse()
    |> drop_leading_blank_and_rules()
    |> Enum.reverse()
  end

  defp drop_leading_blank_and_rules([line | rest] = all) do
    if String.trim(line) == "" or Regex.match?(@hr_re, line) do
      drop_leading_blank_and_rules(rest)
    else
      all
    end
  end

  defp drop_leading_blank_and_rules([]), do: []

  defp collapse_blank_runs(lines) do
    lines
    |> Enum.reduce({[], 0}, fn line, {acc, blanks} ->
      if String.trim(line) == "" do
        if blanks < 1, do: {["" | acc], blanks + 1}, else: {acc, blanks + 1}
      else
        {[line | acc], 0}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp group_by_section(blocks) do
    blocks
    |> Enum.reject(fn
      {:research_heading, _, _} -> true
      {:research_line, _} -> true
      {:research_callout, _, _} -> true
      _ -> false
    end)
    |> Enum.reduce([%{heading: nil, items: []}], fn
      {:heading, _, _, _, _} = h, acc ->
        [%{heading: h, items: []} | acc]

      item, [current | rest] ->
        [%{current | items: [item | current.items]} | rest]
    end)
    |> Enum.reverse()
    |> Enum.map(fn section -> %{section | items: Enum.reverse(section.items)} end)
  end

  # ── Analyzing sections, beats & research ──────────────────────────────

  defp build_sections(blocks) do
    blocks
    |> group_by_section()
    |> Enum.map(fn %{heading: heading, items: items} ->
      {title, level, target, implicit?} =
        case heading do
          {:heading, lvl, _raw, clean, tgt} -> {clean, lvl, tgt, false}
          nil -> {"Opening", 2, nil, true}
        end

      {beats, total_prose_words, prose} = analyze_section_items(items)
      beats_total = length(beats)
      beats_done = Enum.count(beats, & &1.drafted?)

      %{
        title: title,
        level: level,
        target_words: target,
        drafted_words: total_prose_words,
        beats_total: beats_total,
        beats_done: beats_done,
        beats: beats,
        first_sentence: first_sentence(prose),
        cites: beats |> Enum.flat_map(& &1.cites) |> Kernel.++(cite_keys(prose)) |> Enum.uniq(),
        implicit?: implicit? and beats_total == 0 and is_nil(target)
      }
    end)
  end

  defp analyze_section_items(items) do
    {beats_rev, current_beat, orphan_words, orphan_prose} =
      Enum.reduce(items, {[], nil, 0, []}, fn
        {:beat, beat}, {acc, prev_beat, orphans, oprose} ->
          next_acc = if prev_beat, do: [finalize_beat(prev_beat) | acc], else: acc
          {next_acc, beat |> Map.put(:words, 0) |> Map.put(:prose_lines, []), orphans, oprose}

        {:thought, %{text: text}}, {acc, prev_beat, orphans, oprose} ->
          if prev_beat do
            {acc, Map.update!(prev_beat, :thoughts, &(&1 ++ [text])), orphans, oprose}
          else
            {acc, nil, orphans, oprose}
          end

        {:prose, line}, {acc, prev_beat, orphans, oprose} ->
          words =
            if Regex.match?(@hr_re, line) do
              0
            else
              count_words(line)
            end

          if prev_beat do
            beat =
              prev_beat
              |> Map.update!(:words, &(&1 + words))
              |> Map.update!(:prose_lines, &[line | &1])

            {acc, beat, orphans, oprose}
          else
            {acc, nil, orphans + words, [line | oprose]}
          end

        _, state ->
          state
      end)

    beats =
      if current_beat do
        Enum.reverse([finalize_beat(current_beat) | beats_rev])
      else
        Enum.reverse(beats_rev)
      end

    total_words = orphan_words + Enum.sum(Enum.map(beats, & &1.words))

    prose =
      Enum.join(
        [Enum.reverse(orphan_prose) |> Enum.join("\n") | Enum.map(beats, & &1.prose)],
        "\n"
      )

    {beats, total_words, prose}
  end

  # The section's first drafted sentence, for the reverse outline: what the
  # prose says it is doing, beside what the beat asked of it.
  defp first_sentence(prose) do
    paragraph =
      prose
      |> String.split(~r/\n\s*\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.find(fn p -> p != "" and not String.starts_with?(p, ["#", ">", "|", "!["]) end)

    case paragraph && Web.Markdown.to_text(paragraph) do
      nil ->
        nil

      "" ->
        nil

      text ->
        case Regex.run(~r/^.+?[.!?](?=\s|$)/u, text) do
          [sentence] -> sentence
          nil -> String.slice(text, 0, 200)
        end
    end
  end

  defp cite_keys(text), do: text |> Citations.citations() |> Enum.map(& &1.key) |> Enum.uniq()

  defp finalize_beat(beat) do
    drafted? = beat.checked? or beat.words > 0
    prompt = Enum.join(beat.body_lines, "\n")
    thoughts = Map.get(beat, :thoughts, [])
    prose = beat |> Map.get(:prose_lines, []) |> Enum.reverse() |> Enum.join("\n")

    %{
      title: beat.title,
      prompt: prompt,
      thoughts: thoughts,
      checked?: beat.checked?,
      drafted?: drafted?,
      words: beat.words,
      body_lines: beat.body_lines,
      prose: prose,
      # The sources the beat leans on: cited in its prompt, its phrasings or
      # the prose written under it.
      cites: cite_keys(Enum.join([prompt, prose | thoughts], "\n"))
    }
  end

  defp mark_beat_states(blocks) do
    {out_rev, current_beat} =
      Enum.reduce(blocks, {[], nil}, fn
        {:beat, beat}, {acc, prev} ->
          acc = if prev, do: [{:beat, finalize_beat(prev)} | acc], else: acc
          {acc, Map.put(beat, :words, 0)}

        {:heading, _, _, _, _} = h, {acc, prev} ->
          acc = if prev, do: [{:beat, finalize_beat(prev)} | acc], else: acc
          {[h | acc], nil}

        {:research_heading, _, _} = rh, {acc, prev} ->
          acc = if prev, do: [{:beat, finalize_beat(prev)} | acc], else: acc
          {[rh | acc], nil}

        {:thought, %{text: text}} = t, {acc, prev} ->
          if prev do
            {acc, Map.update!(prev, :thoughts, &(&1 ++ [text]))}
          else
            {[t | acc], nil}
          end

        {:prose, line} = p, {acc, prev} ->
          words = if Regex.match?(@hr_re, line), do: 0, else: count_words(line)
          prev = if prev, do: Map.update!(prev, :words, &(&1 + words)), else: nil
          {[p | acc], prev}

        other, {acc, prev} ->
          {[other | acc], prev}
      end)

    final_acc =
      if current_beat, do: [{:beat, finalize_beat(current_beat)} | out_rev], else: out_rev

    Enum.reverse(final_acc)
  end

  # Each source learns which beats lean on it (`used_in`, beat titles in
  # order), so the reading list shows what each reading is for.
  defp link_research(research, sections) do
    beats = Enum.flat_map(sections, & &1.beats)

    items =
      Enum.map(research.items, fn item ->
        used_in =
          if item.key,
            do: beats |> Enum.filter(&(item.key in &1.cites)) |> Enum.map(& &1.title),
            else: []

        Map.put(item, :used_in, used_in)
      end)

    %{research | items: items}
  end

  defp build_research(blocks) do
    lines =
      Enum.flat_map(blocks, fn
        {:research_line, line} -> [line]
        {:research_callout, _title, callout_lines} -> callout_lines
        _ -> []
      end)

    items = parse_research_items(lines, nil, [])

    %{
      total: length(items),
      checked: Enum.count(items, & &1.done?),
      with_thoughts: Enum.count(items, &(&1.thoughts != [])),
      items: items
    }
  end

  defp parse_research_items([], current, acc) do
    final = if current, do: [finalize_research_item(current) | acc], else: acc
    Enum.reverse(final)
  end

  defp parse_research_items([line | rest], current, acc) do
    cond do
      match = Regex.run(@task_item_re, line) ->
        [_, mark, text] = match
        acc = if current, do: [finalize_research_item(current) | acc], else: acc

        {text, key} = text |> String.trim() |> Citations.split_key()

        item = %{
          done?: String.downcase(mark) == "x",
          text: text,
          key: key,
          thoughts: []
        }

        parse_research_items(rest, item, acc)

      match = Regex.run(@thought_start_re, String.trim(line)) ->
        [_, header_rest] = match
        {cont_lines, remaining} = collect_research_callout(rest, [])
        trimmed_head = String.trim(header_rest)
        thought_lines = if trimmed_head != "", do: [trimmed_head | cont_lines], else: cont_lines
        thought_text = thought_lines |> Enum.join("\n") |> String.trim()

        current =
          if current && thought_text != "" do
            %{current | thoughts: current.thoughts ++ [thought_text]}
          else
            current
          end

        parse_research_items(remaining, current, acc)

      match = Regex.run(~r/^\s*>\s?(.*)$/, line) ->
        [_, note_line] = match
        trimmed = String.trim(note_line)

        current =
          if current && trimmed != "" do
            %{current | thoughts: current.thoughts ++ [trimmed]}
          else
            current
          end

        parse_research_items(rest, current, acc)

      true ->
        parse_research_items(rest, current, acc)
    end
  end

  defp collect_research_callout([line | rest] = all, acc) do
    case Regex.run(~r/^\s*>(?:\s?(.*))?$/, line) do
      [_, inner] -> collect_research_callout(rest, [inner | acc])
      [_] -> collect_research_callout(rest, ["" | acc])
      nil -> {Enum.reverse(acc), all}
    end
  end

  defp collect_research_callout([], acc), do: {Enum.reverse(acc), []}

  defp finalize_research_item(item) do
    %{
      done?: item.done?,
      text: item.text,
      key: item.key,
      thoughts: item.thoughts
    }
  end

  # ── Seeding a beat's thoughts into the draft ──────────────────────────

  defp do_seed_beat([], _target_norm, acc), do: acc |> Enum.reverse() |> Enum.join("\n")

  defp do_seed_beat([line | rest], target_norm, acc) do
    case Regex.run(@beat_start_re, line) do
      [_, header_rest] ->
        {_checked?, title, _inline} = parse_beat_header(header_rest)

        if normalize_title(title) == target_norm do
          {beat_block, after_beat} = collect_beat_and_thoughts([line | rest], [], [])
          {block_lines, thought_texts} = beat_block
          seeded_paragraph = Enum.join(thought_texts, "\n\n")

          new_lines =
            if seeded_paragraph == "" do
              block_lines
            else
              block_lines ++ ["", seeded_paragraph]
            end

          (Enum.reverse(acc) ++ new_lines ++ after_beat)
          |> Enum.join("\n")
        else
          do_seed_beat(rest, target_norm, [line | acc])
        end

      nil ->
        do_seed_beat(rest, target_norm, [line | acc])
    end
  end

  defp do_add_beat_thought([], _target_norm, _callout, acc),
    do: acc |> Enum.reverse() |> Enum.join("\n")

  defp do_add_beat_thought([line | rest], target_norm, callout_lines, acc) do
    case Regex.run(@beat_start_re, line) do
      [_, header_rest] ->
        {_checked?, title, _inline} = parse_beat_header(header_rest)

        if normalize_title(title) == target_norm do
          {{block_lines, _thought_texts}, after_beat} =
            collect_beat_and_thoughts([line | rest], [], [])

          # A blank line first, so Obsidian draws the thought as its own
          # callout rather than as more lines of the beat's.
          (Enum.reverse(acc) ++ block_lines ++ ["" | callout_lines] ++ after_beat)
          |> Enum.join("\n")
        else
          do_add_beat_thought(rest, target_norm, callout_lines, [line | acc])
        end

      nil ->
        do_add_beat_thought(rest, target_norm, callout_lines, [line | acc])
    end
  end

  defp do_add_reading_thought([], _target_idx, _curr_idx, _callout, acc),
    do: acc |> Enum.reverse() |> Enum.join("\n")

  defp do_add_reading_thought([line | rest], target_idx, curr_idx, callout_lines, acc) do
    if Regex.match?(@task_item_re, line) do
      if curr_idx == target_idx do
        {existing_quotes, after_quotes} = collect_raw_quote_lines(rest, [line])

        (Enum.reverse(acc) ++ existing_quotes ++ callout_lines ++ after_quotes)
        |> Enum.join("\n")
      else
        do_add_reading_thought(rest, target_idx, curr_idx + 1, callout_lines, [line | acc])
      end
    else
      do_add_reading_thought(rest, target_idx, curr_idx, callout_lines, [line | acc])
    end
  end

  defp do_toggle_reading_item([], _target_idx, _curr_idx, acc),
    do: acc |> Enum.reverse() |> Enum.join("\n")

  defp do_toggle_reading_item([line | rest], target_idx, curr_idx, acc) do
    case Regex.run(@task_item_re, line) do
      [_, mark, text] ->
        if curr_idx == target_idx do
          new_mark = if String.downcase(mark) == "x", do: " ", else: "x"
          toggled = "- [#{new_mark}] #{text}"
          (Enum.reverse([toggled | acc]) ++ rest) |> Enum.join("\n")
        else
          do_toggle_reading_item(rest, target_idx, curr_idx + 1, [line | acc])
        end

      nil ->
        do_toggle_reading_item(rest, target_idx, curr_idx, [line | acc])
    end
  end

  defp format_thought_callout(text) do
    quoted =
      text
      |> String.split(~r/\r?\n/)
      |> Enum.map(&"> #{&1}")

    ["> [!thought]" | quoted]
  end

  defp collect_beat_and_thoughts([line | rest] = all, lines_acc, thoughts_acc) do
    cond do
      lines_acc == [] ->
        {cont_raw, after_cont} = collect_raw_quote_lines(rest, [line])
        collect_following_thoughts(after_cont, cont_raw, thoughts_acc)

      true ->
        {{Enum.reverse(lines_acc), Enum.reverse(thoughts_acc)}, all}
    end
  end

  defp collect_raw_quote_lines([line | rest] = all, acc) do
    if String.starts_with?(line, ">") do
      collect_raw_quote_lines(rest, [line | acc])
    else
      {Enum.reverse(acc), all}
    end
  end

  defp collect_raw_quote_lines([], acc), do: {Enum.reverse(acc), []}

  defp collect_following_thoughts([line | rest] = all, lines_acc, thoughts_acc) do
    cond do
      String.trim(line) == "" ->
        case rest do
          [next | _] ->
            if Regex.match?(@thought_start_re, next) do
              collect_following_thoughts(rest, lines_acc ++ [line], thoughts_acc)
            else
              {{lines_acc, Enum.reverse(thoughts_acc)}, all}
            end

          [] ->
            {{lines_acc, Enum.reverse(thoughts_acc)}, all}
        end

      match = Regex.run(@thought_start_re, line) ->
        [_, head_rest] = match
        {cont_clean, after_cont} = collect_callout_lines(rest, [])
        {cont_raw, _} = collect_raw_quote_lines(rest, [line])
        trimmed_head = String.trim(head_rest)
        t_lines = if trimmed_head != "", do: [trimmed_head | cont_clean], else: cont_clean
        t_text = t_lines |> Enum.join("\n") |> String.trim()

        collect_following_thoughts(
          after_cont,
          lines_acc ++ cont_raw,
          if(t_text != "", do: [t_text | thoughts_acc], else: thoughts_acc)
        )

      true ->
        {{lines_acc, Enum.reverse(thoughts_acc)}, all}
    end
  end

  defp collect_following_thoughts([], lines_acc, thoughts_acc) do
    {{lines_acc, Enum.reverse(thoughts_acc)}, []}
  end

  defp normalize_title(title) do
    title
    |> strip_md_formatting()
    |> String.downcase()
    |> String.trim()
  end

  defp insert_into_reading_section(text, block_str) do
    {yaml, body} = Web.Frontmatter.split(text)
    lines = String.split(body, ~r/\r?\n/)

    new_body =
      case find_reading_section_bounds(lines) do
        {:ok, insert_idx} ->
          {before_lines, after_lines} = Enum.split(lines, insert_idx)

          trimmed_before =
            before_lines
            |> Enum.reverse()
            |> Enum.drop_while(&(String.trim(&1) == ""))
            |> Enum.reverse()

          (trimmed_before ++ [block_str, ""] ++ after_lines)
          |> Enum.join("\n")

        :none ->
          trimmed = String.trim_leading(body)

          if trimmed == "" do
            "## Reading List\n\n" <> block_str <> "\n"
          else
            "## Reading List\n\n" <> block_str <> "\n\n" <> trimmed
          end
      end

    if String.trim(yaml) == "" do
      new_body
    else
      "---\n" <> yaml <> "\n---\n\n" <> String.trim_leading(new_body)
    end
  end

  defp find_reading_section_bounds(lines) do
    lines
    |> Enum.with_index()
    |> Enum.reduce({nil, nil}, fn {line, idx}, {res_level, end_idx} ->
      case Regex.run(@heading_parts_re, line) do
        [_, hashes, raw_title] ->
          level = String.length(hashes)
          {clean_title, _} = extract_target_words(raw_title)

          cond do
            is_nil(res_level) and Regex.match?(@research_heading_re, clean_title) ->
              {level, nil}

            not is_nil(res_level) and is_nil(end_idx) and level <= res_level ->
              {res_level, idx}

            true ->
              {res_level, end_idx}
          end

        nil ->
          {res_level, end_idx}
      end
    end)
    |> case do
      {nil, _} -> :none
      {_level, nil} -> {:ok, length(lines)}
      {_level, idx} -> {:ok, idx}
    end
  end

  # ── Blueprint converter ───────────────────────────────────────────────

  defp extract_blueprint_header(lines) do
    {meta, kept_rev, _in_body?} =
      Enum.reduce(lines, {%{title: nil, description: nil, target_words: nil}, [], false}, fn line,
                                                                                             {meta,
                                                                                              kept,
                                                                                              started?} ->
        trimmed = String.trim(line)

        cond do
          started? ->
            {meta, [line | kept], true}

          trimmed == "" or Regex.match?(@hr_re, trimmed) ->
            {meta, kept, false}

          match = Regex.run(~r/^\*\*Working Title:\*\*\s*(.+)$/i, trimmed) ->
            [_, raw_title] = match
            {%{meta | title: clean_blueprint_title(raw_title)}, kept, false}

          Regex.match?(~r/^\#{1,6}\s+Master\s+Essay\s+Blueprint/i, trimmed) ->
            target =
              case Regex.run(@blueprint_words_re, trimmed) do
                [_, digits] -> parse_int(digits)
                nil -> nil
              end

            {%{meta | target_words: target || meta.target_words}, kept, false}

          Regex.match?(@heading_re, trimmed) ->
            {meta, [line | kept], true}

          is_nil(meta.description) and not String.starts_with?(trimmed, "*") and
              not String.starts_with?(trimmed, "-") ->
            {%{meta | description: trimmed}, kept, false}

          true ->
            {meta, [line | kept], true}
        end
      end)

    {meta, Enum.reverse(kept_rev)}
  end

  defp convert_blueprint_body(lines) do
    {outline_rev, research_rev, current_beat, _in_research?} =
      Enum.reduce(lines, {[], [], nil, false}, fn line, {out_acc, res_acc, beat, research?} ->
        trimmed = String.trim(line)

        cond do
          match = Regex.run(@heading_parts_re, trimmed) ->
            out_acc = flush_beat(out_acc, beat)
            [_, _hashes, raw_title] = match
            {clean_title, _target} = extract_target_words(raw_title)

            if Regex.match?(@research_heading_re, clean_title) do
              {out_acc, ["", "## #{raw_title}", "" | res_acc], nil, true}
            else
              {["", "## #{raw_title}", "" | out_acc], res_acc, nil, false}
            end

          research? ->
            converted = convert_research_line(trimmed)
            {out_acc, if(converted, do: [converted | res_acc], else: res_acc), nil, true}

          Regex.match?(@hr_re, trimmed) ->
            out_acc = flush_beat(out_acc, beat)
            {out_acc, res_acc, nil, false}

          trimmed == "" ->
            {out_acc, res_acc, beat, false}

          match = Regex.run(~r/^\*\s+\*\*([^*]+?)\*\*\s*(.*)$/, line) ->
            out_acc = flush_beat(out_acc, beat)
            [_, raw_label, rest] = match
            label = String.trim_trailing(String.trim(raw_label), ":")
            first_line = String.trim_leading(String.trim(rest), ":") |> String.trim()
            new_beat = %{title: label, lines: if(first_line != "", do: [first_line], else: [])}
            {out_acc, res_acc, new_beat, false}

          not is_nil(beat) ->
            {out_acc, res_acc, %{beat | lines: beat.lines ++ [String.trim(line)]}, false}

          true ->
            {[line | out_acc], res_acc, nil, false}
        end
      end)

    outline_str =
      outline_rev
      |> flush_beat(current_beat)
      |> Enum.reverse()
      |> collapse_blank_runs()
      |> Enum.join("\n")

    research_str =
      research_rev
      |> Enum.reverse()
      |> collapse_blank_runs()
      |> Enum.join("\n")

    {outline_str, research_str}
  end

  defp flush_beat(acc, nil), do: acc

  defp flush_beat(acc, %{title: title, lines: body_lines}) do
    header = "> [!beat] #{title}"
    quoted = Enum.map(body_lines, &"> #{&1}")
    block = Enum.join([header | quoted], "\n")
    ["", block | acc]
  end

  defp convert_research_line(""), do: ""

  defp convert_research_line(line) do
    cond do
      match = Regex.run(~r/^[-*]\s+\*\*([^*]+?:\*\*)\s*$/, line) ->
        [_, category] = match
        cleaned = category |> String.replace("**", "") |> String.trim_trailing(":")
        "\n### #{cleaned}"

      match = Regex.run(~r/^[-*]\s+\[([ xX])\]\s+(.+)$/, line) ->
        [_, mark, rest] = match
        "- [#{mark}] #{rest}"

      match = Regex.run(~r/^[-*]\s+(.+)$/, line) ->
        [_, rest] = match
        "- [ ] #{rest}"

      true ->
        line
    end
  end

  defp first_heading_title(lines) do
    Enum.find_value(lines, fn line ->
      case Regex.run(@heading_re, String.trim(line)) do
        [_, title] ->
          {clean, _} = extract_target_words(title)
          if Regex.match?(~r/Master\s+Essay\s+Blueprint/i, clean), do: nil, else: clean

        nil ->
          nil
      end
    end)
  end

  defp sum_section_targets(body) do
    Regex.scan(@heading_re, body)
    |> Enum.map(fn [_, raw_title] ->
      {_clean, target} = extract_target_words(raw_title)
      target || 0
    end)
    |> Enum.sum()
    |> then(fn sum -> if sum > 0, do: sum, else: nil end)
  end

  defp clean_blueprint_title(raw) do
    raw
    |> String.trim()
    |> String.trim("*")
    |> String.trim("\"")
    |> String.trim("“")
    |> String.trim("”")
    |> String.trim()
  end

  defp escape_quotes(str), do: String.replace(str, "\"", "'")

  defp parse_int(nil), do: nil

  defp parse_int(val) when is_integer(val), do: val

  defp parse_int(val) when is_binary(val) do
    cleaned = val |> String.replace(",", "") |> String.trim()

    case Integer.parse(cleaned) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp count_words(text) when is_binary(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end
end
