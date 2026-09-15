defmodule Web.Docs do
  @moduledoc """
  Renders a long-form documentation page from markdown, with headings that can
  be linked to and a contents list that points at them.

  Earmark emits headings with no `id`, so on a page the length of a manual
  nothing can be linked to and no contents list can be built. This module runs
  *after* Earmark — the same shape as `Web.Blog.Embeds` — giving every `<h2>`
  and `<h3>` an id slugified from its own text and returning the matching
  contents entries alongside the HTML.

  Slugs come from `Web.Keywords.slugify/1`, the same normalizer that names blog
  posts and keyword filters, so an anchor here reads like every other token on
  the site. Colliding slugs are suffixed rather than dropped: two parts may
  legitimately share a heading and both still need their own address.

  The regex matches only attribute-less `<h2>`/`<h3>`, which is exactly what
  Earmark produces. Should that ever change, headings stop being anchored and
  the contents list comes back empty — the page still renders, which is the
  right way for a documentation page to fail.
  """

  alias Web.Keywords

  # `s` so `.` spans the newlines a wrapped heading can contain.
  @heading_re ~r{<h([23])>(.*?)</h\1>}s
  @tag_re ~r{<[^>]*>}

  @type entry :: %{level: 2 | 3, id: String.t(), text: String.t()}

  @doc """
  Renders markdown into `{html, contents}`.

  The HTML has ids on its headings; `contents` lists them in document order,
  each with the level it was written at so a caller can decide how deep a
  contents list to show.

      iex> {html, contents} = Web.Docs.render("## The Ferry at Bowling Green")
      iex> contents
      [%{level: 2, id: "the-ferry-at-bowling-green", text: "The Ferry at Bowling Green"}]
      iex> html =~ ~s(<h2 id="the-ferry-at-bowling-green">)
      true

  Repeated headings stay reachable rather than collapsing onto one id:

      iex> {_html, contents} = Web.Docs.render("## Film\\n\\n## Film")
      iex> Enum.map(contents, & &1.id)
      ["film", "film-2"]
  """
  @spec render(String.t()) :: {String.t(), [entry()]}
  def render(markdown) when is_binary(markdown) do
    markdown
    |> Earmark.as_html!(gfm: true)
    |> task_lists()
    |> anchor_headings()
  end

  # Earmark does not implement GFM task lists: `- [ ] Eggs` arrives as an
  # ordinary `<li>` whose text begins with a literal "[ ]", so a shopping list
  # written as a checklist renders as prose about brackets. These are the same
  # two substitutions `Web.Fitness.Vault` makes for the regimen checklists —
  # `\s*` because Earmark puts a newline between the `<li>` and the text.
  defp task_lists(html) do
    html
    |> then(
      &Regex.replace(~r{<li>\s*\[ \]\s*}, &1, ~s(<li class="task"><input type="checkbox" /> ))
    )
    |> then(
      &Regex.replace(
        ~r{<li>\s*\[[xX]\]\s*},
        &1,
        ~s(<li class="task"><input type="checkbox" checked /> )
      )
    )
  end

  defp anchor_headings(html) do
    {html, entries, _seen} =
      @heading_re
      |> Regex.scan(html)
      |> Enum.reduce({html, [], MapSet.new()}, &anchor_heading/2)

    {html, Enum.reverse(entries)}
  end

  defp anchor_heading([match, level, inner], {html, entries, seen}) do
    text = heading_text(inner)
    id = unique_slug(text, seen)
    anchored = ~s(<h#{level} id="#{id}">#{inner}</h#{level}>)

    # `global: false` rewrites the first remaining unanchored heading, which —
    # because the scan is in document order and each rewrite no longer matches
    # the bare-tag pattern — is always this one, even when two headings are
    # written identically.
    {String.replace(html, match, anchored, global: false),
     [%{level: String.to_integer(level), id: id, text: text} | entries], MapSet.put(seen, id)}
  end

  defp heading_text(inner) do
    inner
    |> String.replace(@tag_re, "")
    |> unescape()
    |> String.trim()
  end

  # Earmark escapes on the way in, and the contents list is rendered through
  # HEEx which escapes again — so entities have to come back out here or they
  # arrive on the page doubled.
  defp unescape(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    # Last, so an escaped entity in the source does not decode twice.
    |> String.replace("&amp;", "&")
  end

  defp unique_slug(text, seen) do
    case Keywords.slugify(text) do
      "" -> unique_slug("section", seen)
      slug -> free_slug(slug, slug, seen, 2)
    end
  end

  defp free_slug(candidate, base, seen, n) do
    if MapSet.member?(seen, candidate),
      do: free_slug("#{base}-#{n}", base, seen, n + 1),
      else: candidate
  end
end
