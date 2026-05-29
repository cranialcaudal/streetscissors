defmodule Web.Fitness.Vault do
  @moduledoc """
  Reads fitness content directly from the Obsidian Vault.
  Source of truth: /home/cesar/Documents/Obsidian Vault/fitness/
  """

  @base "/home/cesar/Documents/Obsidian Vault/fitness"

  @day_order ~w[monday tuesday wednesday thursday friday saturday sunday one-shot teleauto core-module bosu-amrap-module pickleball-module cooldown-module]

  # ── Weekly Regimen ────────────────────────────────────────────────────

  @doc "Returns ordered list of day metadata from weekly-regimen/ folder."
  def list_days do
    dir = Path.join(@base, "weekly-regimen")

    @day_order
    |> Enum.filter(fn slug ->
      File.exists?(Path.join(dir, slug <> ".md"))
    end)
    |> Enum.map(fn slug ->
      path = Path.join(dir, slug <> ".md")
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
    path = Path.join([@base, "weekly-regimen", slug <> ".md"])

    case File.read(path) do
      {:ok, content} ->
        body = strip_frontmatter(content)
        html = render_markdown(body)
        {:ok, html}

      {:error, _} ->
        :error
    end
  end

  @doc "Returns {:ok, content} for a given day slug, or :error."
  def get_day_raw(slug) do
    path = Path.join([@base, "weekly-regimen", slug <> ".md"])
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
      path = Path.join([@base, "weekly-regimen", day <> ".md"])

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

  @doc "Updates a weekly regimen day."
  def update_day(slug, params) do
    dir = Path.join(@base, "weekly-regimen")
    File.mkdir_p!(dir)

    frontmatter = %{
      "title" => params["title"],
      "description" => params["description"],
      "tab" => params["tab"]
    }

    path = Path.join(dir, slug <> ".md")
    write_markdown_with_frontmatter(path, frontmatter, params["content"])
  end

  # ── Exercise Wiki ─────────────────────────────────────────────────────

  @doc "Returns sorted list of muscle group folder names."
  def list_muscle_groups do
    dir = Path.join(@base, "exercise-wiki")

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
    dir = Path.join([@base, "exercise-wiki", group])

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
      path = Path.join([@base, "exercise-wiki", group, slug <> ".md"])

      if File.exists?(path) do
        meta = parse_frontmatter(path)

        {:ok,
         %{
           slug: slug,
           name: meta["title"] || format_name(slug),
           muscle_group: meta["muscle_group"] || group,
           anatomy: meta["anatomy"],
           functional_category: meta["functional_category"],
           video_url: meta["video_url"],
           thumbnail_url: meta["thumbnail_url"],
           short_description: meta["short_description"],
           html: strip_frontmatter(File.read!(path)) |> render_markdown()
         }}
      end
    end)
  end

  @doc "Returns raw data for editing an exercise."
  def get_exercise_raw(slug) do
    list_muscle_groups()
    |> Enum.find_value(:error, fn group ->
      path = Path.join([@base, "exercise-wiki", group, slug <> ".md"])

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
    dir = Path.join([@base, "exercise-wiki", new_group])
    File.mkdir_p!(dir)

    # If the muscle group changed and it's not a new exercise, remove the old file
    if old_muscle_group && old_muscle_group != new_group do
      old_path = Path.join([@base, "exercise-wiki", old_muscle_group, slug <> ".md"])
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
    path = Path.join([@base, "exercise-wiki", muscle_group, slug <> ".md"])
    if File.exists?(path), do: File.rm!(path)
  end

  # ── Fitness Blog ──────────────────────────────────────────────────────

  @doc "Returns list of fitness blog posts sorted by date descending."
  def list_blog_posts do
    dir = Path.join(@base, "fitness-blog")

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(fn filename ->
          slug = String.replace(filename, ".md", "")
          path = Path.join(dir, filename)
          meta = parse_frontmatter(path)
          body = strip_frontmatter(File.read!(path))

          excerpt =
            body
            |> String.split("\n")
            |> Enum.reject(&(&1 == ""))
            |> List.first("")
            |> String.slice(0, 250)

          %{
            slug: slug,
            title: meta["title"] || format_name(slug),
            date: meta["date"],
            excerpt: excerpt
          }
        end)
        |> Enum.sort_by(& &1.date, :desc)

      _ ->
        []
    end
  end

  @doc "Returns {:ok, html} for a fitness blog post slug."
  def get_blog_post(slug) do
    path = Path.join([@base, "fitness-blog", slug <> ".md"])

    case File.read(path) do
      {:ok, content} ->
        meta = parse_frontmatter(path)
        html = strip_frontmatter(content) |> render_markdown()
        {:ok, meta, html}

      {:error, _} ->
        :error
    end
  end

  @doc "Returns raw data for a blog post."
  def get_blog_post_raw(slug) do
    path = Path.join([@base, "fitness-blog", slug <> ".md"])
    if File.exists?(path) do
      content = File.read!(path)
      {:ok, parse_frontmatter(path), strip_frontmatter(content)}
    else
      :error
    end
  end

  @doc "Updates a fitness blog post."
  def update_blog_post(slug, params) do
    dir = Path.join(@base, "fitness-blog")
    File.mkdir_p!(dir)

    frontmatter = %{
      "title" => params["title"],
      "date" => params["date"]
    }

    path = Path.join(dir, slug <> ".md")
    write_markdown_with_frontmatter(path, frontmatter, params["content"])
  end

  @doc "Deletes a fitness blog post."
  def delete_blog_post(slug) do
    path = Path.join([@base, "fitness-blog", slug <> ".md"])
    if File.exists?(path), do: File.rm!(path)
  end

  # ── Private Helpers ───────────────────────────────────────────────────

  defp parse_frontmatter(path) do
    case File.read(path) do
      {:ok, content} ->
        case Regex.run(~r/\A---\n(.*?)\n---/ms, content, capture: :all_but_first) do
          [yaml] ->
            yaml
            |> String.split("\n")
            |> Enum.reduce(%{}, fn line, acc ->
              case String.split(line, ": ", parts: 2) do
                [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
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

  defp render_markdown(md) do
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

        case get_exercise_by_slug(slug) do
          {:ok, ex} ->
            thumb_attr = if ex.thumbnail_url, do: " data-thumb=\"#{ex.thumbnail_url}\"", else: ""

            muscle_cat =
              if ex.anatomy,
                do: "#{ex.anatomy} | #{ex.functional_category}",
                else: ex.muscle_group

            """
            <a href="/fitness/#{slug}" class="gym-link hover-exercise"#{thumb_attr} data-muscle="#{muscle_cat}" data-desc="#{String.replace(ex.short_description || "", "\"", "&quot;")}">#{disp}</a>
            """
            |> String.trim()

          _ ->
            "<a href=\"/fitness/#{slug}\" class=\"gym-link hover-exercise\">#{disp}</a>"
        end
      end)

    # Convert GitHub style task lists into checkboxes since Earmark leaves them as [ ] text with newlines
    html = Regex.replace(~r/<li>\s*\[ \]\s*/, html, "<li><input type=\"checkbox\"> ")
    html = Regex.replace(~r/<li>\s*\[[xX]\]\s*/, html, "<li><input type=\"checkbox\" checked> ")

    # External links (http/https) open in new tab
    html =
      Regex.replace(
        ~r/<a href="(https?:\/\/[^"]+)">/,
        html,
        "<a href=\"\\1\" target=\"_blank\" rel=\"noopener noreferrer\">"
      )

    html
  end

  defp format_name(slug) do
    slug
    |> String.replace("-", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
