defmodule Web.Fitness.Vault do
  @moduledoc """
  Reads fitness content from the in-repo content directory.
  Source of truth: content/fitness/ (override with the FITNESS_PATH env var).
  """

  @default_base "/home/cesar/streetscissors/content/fitness"

  defp base_path, do: Application.get_env(:web, :fitness_path, @default_base)

  @day_order ~w[monday tuesday wednesday thursday friday saturday sunday one-shot teleauto core-module bosu-amrap-module pickleball-module cooldown-module baseball-5k-module st-herberts-build]

  # ── Weekly Regimen ────────────────────────────────────────────────────

  @doc "Returns ordered list of day metadata from weekly/ or additional/ folders."
  def list_days do
    @day_order
    |> Enum.filter(fn slug ->
      File.exists?(find_day_path(slug))
    end)
    |> Enum.map(fn slug ->
      path = find_day_path(slug)
      meta = parse_frontmatter(path)

      %{
        slug: slug,
        title: meta["title"] || slug,
        description: meta["description"] || "",
        tab: meta["tab"] || String.capitalize(slug)
      }
    end)
  end

  @doc "Returns {:ok, html} for a given day slug, or :error."
  def get_day(slug) do
    path = find_day_path(slug)

    case File.read(path) do
      {:ok, content} ->
        meta = parse_frontmatter(path)
        body = strip_frontmatter(content)

        # Check for modules
        body =
          case Map.get(meta, "modules") do
            nil ->
              body

            "" ->
              body

            mods_str ->
              mods = String.split(mods_str, ",") |> Enum.map(&String.trim/1)

              modules_body =
                Enum.map(mods, fn m_slug ->
                  m_path = Path.join([base_path(), "modules", m_slug <> ".md"])

                  case File.read(m_path) do
                    {:ok, m_content} -> strip_frontmatter(m_content)
                    _ -> ""
                  end
                end)
                |> Enum.join("\n\n")

              body <> "\n\n" <> modules_body
          end

        html = body |> checklist_only() |> render_markdown()
        {:ok, html}

      {:error, _} ->
        :error
    end
  end

  @doc """
  A day plus its rotating options.

  Some days do two different things depending on the week — Friday is the
  office swim or a remote fartlek run, Saturday runs a four-week cycle. Those
  used to be described only in prose, which `checklist_only/1` strips, so the
  page showed one option and gave no sign the others existed.

  Options are declared as numbered frontmatter keys, because `parse_frontmatter/1`
  is a flat `": "` line split with no list support:

      option_1: friday-survival-swim|Office Swim — Rec Pool
      option_2: friday-fartlek-run|Remote Fartlek Run

  Returns `{:ok, %{html: shared_html, options: [%{key:, label:, html:, active?:}]}}`.
  `html` is the day body plus its always-on `modules:`; each option is rendered
  through the same filter independently. Exactly one option is `active?`, chosen
  by `Web.Fitness.Rotation`. A day with no `option_N` keys returns `options: []`,
  so callers can treat every day the same way.
  """
  def get_day_with_options(slug, date \\ Web.Clock.local_today()) do
    with {:ok, html} <- get_day(slug),
         {:ok, meta, _body} <- get_day_raw(slug) do
      options =
        meta
        |> parse_options()
        |> Web.Fitness.Rotation.mark(date)
        |> Enum.map(fn {option, active?} -> Map.put(option, :active?, active?) end)

      {:ok, %{html: html, options: options}}
    else
      _ -> :error
    end
  end

  # option_1, option_2, … in numeric order. Each value is `module-slug|Label`;
  # the label is optional and falls back to a title-cased slug.
  defp parse_options(meta) do
    meta
    |> Enum.filter(fn {key, _value} -> Regex.match?(~r/^option_\d+$/, key) end)
    |> Enum.sort_by(fn {key, _value} ->
      key |> String.replace_prefix("option_", "") |> String.to_integer()
    end)
    |> Enum.map(fn {key, value} -> build_option(key, value) end)
    |> Enum.reject(&is_nil/1)
  end

  # `modules|Label`, where modules is comma-separated like the `modules:` key.
  # Composing lets an option reuse a module rather than restate it — Saturday's
  # DOCO weeks are a hike plus the existing No Focus – Full Body session, and
  # copying that exercise list would guarantee the two drift apart.
  defp build_option(key, value) do
    {slugs_str, label} =
      case String.split(value, "|", parts: 2) do
        [slugs, label] -> {slugs, String.trim(label)}
        [slugs] -> {slugs, format_name(String.trim(slugs))}
      end

    module_slugs = slugs_str |> String.split(",") |> Enum.map(&String.trim/1)

    bodies =
      module_slugs
      |> Enum.map(fn slug ->
        case File.read(Path.join([base_path(), "modules", slug <> ".md"])) do
          {:ok, content} -> strip_frontmatter(content)
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # An option whose modules are all missing is skipped rather than rendered
    # blank — an empty dropdown reads as a bug to whoever opens it.
    if bodies == [] do
      nil
    else
      %{
        key: key,
        modules: module_slugs,
        label: label,
        html: bodies |> Enum.join("\n\n") |> checklist_only() |> render_markdown()
      }
    end
  end

  @doc "Returns {:ok, content} for a given day slug, or :error."
  def get_day_raw(slug) do
    path = find_day_path(slug)

    if File.exists?(path) do
      content = File.read!(path)
      {:ok, parse_frontmatter(path), strip_frontmatter(content)}
    else
      :error
    end
  end

  @doc "Returns a MapSet of all exercise slugs explicitly referenced in the weekly regimen."
  def active_slugs do
    @day_order
    |> Enum.map(fn day ->
      path = find_day_path(day)

      case File.read(path) do
        {:ok, content} ->
          Regex.scan(~r/\[\[(.*?)(?:\|.*?)?\]\]/, content)
          |> Enum.map(fn match -> Enum.at(match, 1) end)

        _ ->
          []
      end
    end)
    |> List.flatten()
    |> MapSet.new()
  end

  @doc """
  Updates a weekly regimen day.

  Keys the edit form does not know about are carried through from the file.
  This used to rebuild the frontmatter from `title`/`description`/`tab` alone,
  so saving any day from `/admin/fitness` silently deleted its `modules:` line —
  and would now delete `option_N:` with it, quietly emptying a rotating day.
  """
  def update_day(slug, params) do
    path = find_day_path(slug)
    dir = Path.dirname(path)
    File.mkdir_p!(dir)

    existing = if File.exists?(path), do: parse_frontmatter(path), else: %{}

    frontmatter =
      Map.merge(existing, %{
        "title" => params["title"],
        "description" => params["description"],
        "tab" => params["tab"]
      })

    path = Path.join(dir, slug <> ".md")
    write_markdown_with_frontmatter(path, frontmatter, params["content"])
  end

  # ── Exercise Wiki ─────────────────────────────────────────────────────

  @doc "Returns sorted list of muscle group folder names."
  def list_muscle_groups do
    dir = Path.join(base_path(), "exercise-wiki")

    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&File.dir?(Path.join(dir, &1)))
        |> Enum.sort()

      _ ->
        []
    end
  end

  @doc "Returns list of exercises in a muscle group folder."
  def list_exercises(group) do
    dir = Path.join([base_path(), "exercise-wiki", group])

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(fn filename ->
          slug = String.replace(filename, ".md", "")
          path = Path.join(dir, filename)
          meta = parse_frontmatter(path)

          %{
            slug: slug,
            name: meta["title"] || format_name(slug),
            muscle_group: meta["muscle_group"] || group,
            anatomy: meta["anatomy"],
            functional_category: meta["functional_category"],
            thumbnail_url: meta["thumbnail_url"],
            short_description: meta["short_description"]
          }
        end)
        |> Enum.sort_by(& &1.name)

      _ ->
        []
    end
  end

  @doc "Returns all exercises grouped by muscle group."
  def list_all_exercises do
    list_muscle_groups()
    |> Enum.map(fn group ->
      {group, list_exercises(group)}
    end)
  end

  @doc "Finds an exercise by slug across all muscle groups."
  def get_exercise_by_slug(slug) do
    list_muscle_groups()
    |> Enum.find_value(:error, fn group ->
      path = Path.join([base_path(), "exercise-wiki", group, slug <> ".md"])

      if File.exists?(path) do
        meta = parse_frontmatter(path)

        {:ok,
         %{
           slug: slug,
           name: meta["title"] || format_name(slug),
           muscle_group: meta["muscle_group"] || group,
           anatomy: meta["anatomy"],
           functional_category: meta["functional_category"],
           video_url: normalize_video_url(meta["video_url"]),
           thumbnail_url: meta["thumbnail_url"],
           short_description: meta["short_description"],
           references: resolve_references(meta["references"]),
           html: strip_frontmatter(File.read!(path)) |> render_markdown()
         }}
      end
    end)
  end

  @doc """
  Loads the shared citation bibliography (content/fitness/references.md) as a map
  of `id => %{"authors" => ..., "year" => ..., ...}`. Citations are verified against
  PubMed before being added to that file; see its header.
  """
  def list_references do
    path = Path.join(base_path(), "references.md")

    case File.read(path) do
      {:ok, content} -> parse_bibliography(content)
      _ -> %{}
    end
  end

  # Resolve an exercise's comma-separated `references:` ids into ordered citation
  # maps. Unknown ids are dropped silently so a typo can never crash the page.
  defp resolve_references(nil), do: []

  defp resolve_references(csv) do
    bib = list_references()

    csv
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn id -> bib[id] && Map.put(bib[id], "id", id) end)
    |> Enum.reject(&is_nil/1)
  end

  # Bibliography format: blocks introduced by a `### <id>` heading, each followed by
  # `- key: value` lines. Anything outside a block (intro prose) is ignored.
  defp parse_bibliography(content) do
    content
    |> String.split(~r/^###[ \t]+/m, trim: true)
    |> Enum.reduce(%{}, fn block, acc ->
      case String.split(block, "\n", trim: true) do
        [id_line | rest] ->
          id = String.trim(id_line)

          fields =
            Enum.reduce(rest, %{}, fn line, m ->
              case Regex.run(~r/^-\s*([a-zA-Z_]+):\s*(.*)$/, String.trim(line)) do
                [_, k, v] -> Map.put(m, k, String.trim(v))
                _ -> m
              end
            end)

          if id == "" or fields == %{}, do: acc, else: Map.put(acc, id, fields)

        _ ->
          acc
      end
    end)
  end

  @doc "Returns raw data for editing an exercise."
  def get_exercise_raw(slug) do
    list_muscle_groups()
    |> Enum.find_value(:error, fn group ->
      path = Path.join([base_path(), "exercise-wiki", group, slug <> ".md"])

      if File.exists?(path) do
        meta = parse_frontmatter(path)
        body = strip_frontmatter(File.read!(path))

        {:ok,
         %{
           slug: slug,
           name: meta["title"] || format_name(slug),
           muscle_group: meta["muscle_group"] || group,
           anatomy: meta["anatomy"],
           functional_category: meta["functional_category"],
           video_url: meta["video_url"],
           thumbnail_url: meta["thumbnail_url"],
           short_description: meta["short_description"]
         }, body}
      end
    end)
  end

  @doc "Creates or updates an exercise, moving it to a new muscle group folder if necessary."
  def update_exercise(slug, old_muscle_group, params) do
    # Ensure muscle group folder exists
    new_group = params["muscle_group"] || old_muscle_group || "uncategorized"
    dir = Path.join([base_path(), "exercise-wiki", new_group])
    File.mkdir_p!(dir)

    # If the muscle group changed and it's not a new exercise, remove the old file
    if old_muscle_group && old_muscle_group != new_group do
      old_path = Path.join([base_path(), "exercise-wiki", old_muscle_group, slug <> ".md"])
      if File.exists?(old_path), do: File.rm!(old_path)
    end

    # Build the YAML frontmatter
    frontmatter = %{
      "title" => params["title"],
      "muscle_group" => new_group,
      "anatomy" => params["anatomy"],
      "functional_category" => params["functional_category"],
      "thumbnail_url" => params["thumbnail_url"],
      "video_url" => params["video_url"],
      "short_description" => params["short_description"]
    }

    path = Path.join(dir, slug <> ".md")
    write_markdown_with_frontmatter(path, frontmatter, params["content"])
  end

  @doc "Deletes an exercise."
  def delete_exercise(slug, muscle_group) do
    path = Path.join([base_path(), "exercise-wiki", muscle_group, slug <> ".md"])
    if File.exists?(path), do: File.rm!(path)
  end

  # ── Private Helpers ───────────────────────────────────────────────────

  defp find_day_path(slug) do
    weekly_path = Path.join([base_path(), "weekly", slug <> ".md"])
    additional_path = Path.join([base_path(), "additional", slug <> ".md"])

    cond do
      File.exists?(additional_path) -> additional_path
      true -> weekly_path
    end
  end

  defp parse_frontmatter(path) do
    case File.read(path) do
      {:ok, content} ->
        case Regex.run(~r/\A---\n(.*?)\n---/ms, content, capture: :all_but_first) do
          [yaml] ->
            yaml
            |> String.split("\n")
            |> Enum.reduce(%{}, fn line, acc ->
              case String.split(line, ": ", parts: 2) do
                [k, v] -> Map.put(acc, String.trim(k), v |> String.trim() |> strip_quotes())
                _ -> acc
              end
            end)

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  # Frontmatter values are often written quoted (e.g. `title: "Farmer's Walk"`).
  # YAML quotes are delimiters, not part of the value — strip one matching
  # surrounding pair so they never leak into rendered titles, tags, or links.
  defp strip_quotes(v) do
    cond do
      String.length(v) >= 2 and String.starts_with?(v, "\"") and String.ends_with?(v, "\"") ->
        String.slice(v, 1..-2//1)

      String.length(v) >= 2 and String.starts_with?(v, "'") and String.ends_with?(v, "'") ->
        String.slice(v, 1..-2//1)

      true ->
        v
    end
  end

  defp strip_frontmatter(content) do
    case Regex.replace(~r/\A---\n.*?\n---\n?/ms, content, "") do
      stripped -> String.trim_leading(stripped)
    end
  end

  defp write_markdown_with_frontmatter(path, frontmatter, content) do
    # Filter out nil or empty string values from frontmatter
    clean_meta =
      frontmatter
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
      |> Enum.join("\n")

    yaml_block =
      if clean_meta != "" do
        "---\n#{clean_meta}\n---\n\n"
      else
        ""
      end

    full_content = yaml_block <> (content || "")
    File.write!(path, full_content)
  end

  # Lightweight per-slug metadata for [[wiki-link]] expansion: frontmatter only,
  # never renders the exercise body. render_markdown MUST use this instead of
  # get_exercise_by_slug/1 — that one renders the body, which expands its own
  # [[links]], which would recurse forever on a cycle (e.g. pull-ups <->
  # scapular-pull-ups). The hover card only needs these fields, never the HTML.
  defp exercise_meta(slug) do
    list_muscle_groups()
    |> Enum.find_value(:error, fn group ->
      path = Path.join([base_path(), "exercise-wiki", group, slug <> ".md"])

      if File.exists?(path) do
        meta = parse_frontmatter(path)

        {:ok,
         %{
           muscle_group: meta["muscle_group"] || group,
           anatomy: meta["anatomy"],
           functional_category: meta["functional_category"],
           thumbnail_url: meta["thumbnail_url"],
           short_description: meta["short_description"]
         }}
      end
    end)
  end

  # The regimen page is a checklist, not a training diary. Only block headings
  # and top-level exercise checkboxes survive; the where/when prose, the
  # coaching notes, and the indented how-to / why / video / rest lines stay in
  # the vault file for Obsidian. This is a filter on the *source*, not CSS —
  # the page is public, so the schedule and location detail should never reach
  # the HTML at all. `get_day_raw/1` is untouched, so admin editing still sees
  # the whole file.
  defp checklist_only(md) do
    md
    |> String.split("\n")
    |> Enum.filter(&checklist_line?/1)
    |> drop_empty_sections()
    # Earmark wants a blank line before a heading that follows a list.
    |> Enum.flat_map(fn line -> if heading?(line), do: ["", line], else: [line] end)
    |> Enum.join("\n")
  end

  defp checklist_line?(line), do: heading?(line) or exercise_checkbox?(line)

  defp heading?(line), do: Regex.match?(~r/^\#{1,6}\s+\S/, line)

  defp heading_level(line) do
    line |> String.graphemes() |> Enum.take_while(&(&1 == "#")) |> length()
  end

  # Top-level only: the nested "- How-to:" / "- Video:" lines are indented.
  defp exercise_checkbox?(line), do: Regex.match?(~r/^[-*]\s+\[[ xX]\]\s*\S/, line)

  # Once the prose is gone, a heading whose section held nothing but prose is
  # left labelling empty space. Keep a heading only when its subtree — up to
  # the next heading of the same or higher level — still contains an exercise,
  # so parent blocks survive on the strength of their sub-sections.
  defp drop_empty_sections(lines) do
    lines
    |> Enum.with_index()
    |> Enum.filter(fn {line, i} ->
      not heading?(line) or section_has_exercise?(lines, i, heading_level(line))
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp section_has_exercise?(lines, index, level) do
    lines
    |> Enum.drop(index + 1)
    |> Enum.take_while(&(not (heading?(&1) and heading_level(&1) <= level)))
    |> Enum.any?(&exercise_checkbox?/1)
  end

  defp render_markdown(md) do
    md = inject_log_markers(md)

    html =
      case Earmark.as_html(md, gfm: true) do
        {:ok, html, _} -> html
        {:error, html, _} -> html
      end

    # Pre-process Obsidian links [[slug|display text]] -> <a href="...">
    # Must run AFTER Earmark to prevent Earmark from escaping the raw HTML or auto-linking the thumb URL.
    html =
      Regex.replace(~r/\[\[(.*?)(?:\|(.*?))?\]\]/, html, fn _, slug, display ->
        disp = if display == "", do: format_name(slug), else: display

        case exercise_meta(slug) do
          {:ok, ex} ->
            thumb_attr = if ex.thumbnail_url, do: " data-thumb=\"#{ex.thumbnail_url}\"", else: ""

            muscle_cat =
              if ex.anatomy,
                do: "#{ex.anatomy} | #{ex.functional_category}",
                else: ex.muscle_group

            """
            <a href="/fitness/wiki/#{slug}" class="gym-link hover-exercise"#{thumb_attr} data-muscle="#{muscle_cat}" data-desc="#{String.replace(ex.short_description || "", "\"", "&quot;")}">#{disp}</a>
            """
            |> String.trim()

          _ ->
            "<a href=\"/fitness/wiki/#{slug}\" class=\"gym-link hover-exercise\">#{disp}</a>"
        end
      end)

    # Convert GitHub style task lists into checkboxes since Earmark leaves them as [ ] text with newlines
    html = Regex.replace(~r/<li>\s*\[ \]\s*/, html, "<li><input type=\"checkbox\"> ")
    html = Regex.replace(~r/<li>\s*\[[xX]\]\s*/, html, "<li><input type=\"checkbox\" checked> ")

    # Swap the ⟦LOG:slug⟧ markers left by inject_log_markers/1 for an inline
    # "Log" trigger. LiveView binds phx-* attributes anywhere in the DOM, so
    # this works even though the button lives inside raw/1-injected HTML.
    html =
      Regex.replace(~r/⟦LOG:([a-z0-9][a-z0-9-]*)⟧/, html, fn _, slug ->
        ~s(<button type="button" class="log-trigger" phx-click="open_log" phx-value-slug="#{slug}">Log</button>)
      end)

    # External links (http/https) open in new tab
    html =
      Regex.replace(
        ~r/<a href="(https?:\/\/[^"]+)">/,
        html,
        "<a href=\"\\1\" target=\"_blank\" rel=\"noopener noreferrer\">"
      )

    html
  end

  # YouTube `watch?v=` and `youtu.be/` links cannot be loaded inside an <iframe>;
  # only the `/embed/<id>` form can. Normalize known share URLs to the embed form
  # so stored links render regardless of which format was pasted.
  defp normalize_video_url(nil), do: nil

  defp normalize_video_url(url) do
    cond do
      String.contains?(url, "/embed/") ->
        url

      match = Regex.run(~r/(?:youtu\.be\/|[?&]v=)([\w-]{11})/, url) ->
        "https://www.youtube.com/embed/" <> Enum.at(match, 1)

      true ->
        url
    end
  end

  # Tags each checkbox line that references a `[[slug]]` exercise with a
  # trailing marker, later swapped for an inline "Log" button by
  # render_markdown/1. Runs on the raw markdown, before Earmark, so it only
  # ever has to reason about the single source line a checkbox and its first
  # wiki-link already share — never about matching `<li>...</li>` boundaries
  # in the rendered HTML, which would be unsafe once sub-bullets (nested
  # `<li>`s, e.g. the Shoulder Triage checklist) are involved.
  defp inject_log_markers(md) do
    md
    |> String.split("\n")
    |> Enum.map(fn line ->
      if Regex.match?(~r/^\s*-\s*\[[ xX]\]/, line) do
        case Regex.run(~r/\[\[([a-z0-9][a-z0-9-]*)/, line) do
          [_, slug] -> line <> " ⟦LOG:#{slug}⟧"
          _ -> line
        end
      else
        line
      end
    end)
    |> Enum.join("\n")
  end

  defp format_name(slug) do
    slug
    |> String.replace("-", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
