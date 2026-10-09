defmodule Web.Fitness.WikiCheck do
  @moduledoc """
  What in the exercise wiki has drifted from the shape its pages share.

  The wiki is a folder of markdown files written over months, and nothing
  holds one page to the conventions of the next. The 2026-10 cleanup found
  twenty-four categories where thirteen were meant, sixteen of them used by a
  single page; pages naming the weekday a lift fell on, which went stale the
  moment the week was rearranged; and headings that said "(theory)" on pages
  with citations and the reverse. `problems/0` finds those again as they
  appear, and `Web.ContentHealth` lists them on /admin/health:

    * a page missing one of the five frontmatter keys every page carries, or
      filed in a folder that is not its `muscle_group`;
    * a `functional_category` no other page uses, which is nearly always a
      new spelling of an existing one (a wiki whose pages all share one
      category has no vocabulary yet to drift from);
    * a page without its Goal line, or without one of its sections;
    * "Why it works" on a page that cites nothing, or "(theory)" on one that
      does: the heading is how a reader tells a measured claim from a
      coaching principle;
    * a day of the week in a page's body. A page names the session ("the
      lower day"), never the day;
    * a citation that is not in `references.md`;
    * a figure file (`Web.Fitness.Figure`) that does not hold together, or
      that belongs to no page.

  It does not judge the writing, and it knows no list of allowed categories:
  the vocabulary is whatever the pages themselves agree on.
  """

  alias Web.Fitness.{Figure, Vault}

  @keys ~w(title muscle_group anatomy functional_category short_description)
  @weekday ~r/\b(?:Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day\b/
  @sections ["### Execution", "### Programming notes"]

  @doc "Every problem found, as `%{where: path under the vault, problem: sentence}`."
  def problems do
    pages = Vault.exercise_sources()
    categories = Enum.frequencies_by(pages, & &1.meta["functional_category"])
    references = Vault.list_references()
    slugs = MapSet.new(pages, & &1.slug)

    Enum.flat_map(pages, &page(&1, categories, references)) ++ figures(slugs)
  end

  defp page(page, categories, references) do
    where = "exercise-wiki/#{page.group}/#{page.slug}.md"
    category = page.meta["functional_category"]
    cited = cited(page.meta)

    found =
      for(key <- @keys, blank?(page.meta[key]), do: "has no #{key}") ++
        if(page.meta["muscle_group"] not in [nil, page.group],
          do: [
            "says its muscle group is #{page.meta["muscle_group"]} but is filed under #{page.group}"
          ],
          else: []
        ) ++
        if(not blank?(category) and categories[category] == 1 and map_size(categories) > 1,
          do: ["is the only page in the category \"#{category}\"; use one the wiki already has"],
          else: []
        ) ++
        if(String.contains?(page.body, "**Goal:**"), do: [], else: ["has no Goal line"]) ++
        for(
          section <- @sections,
          not heading?(page.body, section),
          do: "has no #{section} section"
        ) ++
        why(page.body, cited) ++
        for(
          day <- @weekday |> Regex.scan(page.body) |> List.flatten() |> Enum.uniq(),
          do:
            "names a day of the week (#{day}); a page names the session, since the week gets rearranged"
        ) ++
        for(
          id <- cited,
          not Map.has_key?(references, id),
          do: "cites #{id}, which is not in references.md"
        )

    Enum.map(found, &%{where: where, problem: &1})
  end

  defp why(body, cited) do
    measured = heading?(body, "### Why it works")
    theory = heading?(body, "### Why it works (theory)")

    cond do
      not measured and not theory ->
        ["has no \"Why it works\" section"]

      theory and cited != [] ->
        ["cites sources, so its section is \"Why it works\", not \"(theory)\""]

      measured and cited == [] ->
        ["cites nothing, so its section is \"Why it works (theory)\""]

      true ->
        []
    end
  end

  defp heading?(body, heading), do: Regex.match?(~r/^#{Regex.escape(heading)}\s*$/m, body)

  defp cited(meta) do
    (meta["references"] || "")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp blank?(value), do: value in [nil, ""]

  defp figures(slugs) do
    Enum.flat_map(Figure.all(), fn {slug, result} ->
      where = "figures/#{slug}.json"

      orphan =
        if MapSet.member?(slugs, slug),
          do: [],
          else: [%{where: where, problem: "there is no exercise by that name in the wiki"}]

      broken =
        case result do
          {:error, [first | rest]} ->
            more = if rest == [], do: "", else: " (and #{length(rest)} more)"
            [%{where: where, problem: "the figure is not drawn: #{first}#{more}"}]

          _ ->
            []
        end

      orphan ++ broken
    end)
  end
end
