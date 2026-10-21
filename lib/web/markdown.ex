defmodule Web.Markdown do
  @moduledoc """
  Markdown to HTML, with one set of options for every page that renders it
  (the blog, the vault, the manual, mail, the about page, the calendar).

  Earmark's warnings about a malformed line are not failures: the HTML it
  made anyway is what the page shows, as it always did.
  """

  @options [gfm: true]

  @doc "The HTML for `markdown`."
  def to_html(markdown, opts \\ []) when is_binary(markdown) do
    case Earmark.as_html(markdown, Keyword.merge(@options, opts)) do
      {:ok, html, _} -> html
      {:error, html, _} -> html
    end
  end

  @doc """
  Markdown as plain words, for the places that want a line rather than a
  page: a feed's description, a meta description. Embeds (`![[roll012/3]]`)
  are left out, a wiki link (`[[slug|Name]]`) keeps its name, and the
  rest is rendered and its tags dropped, so `**ferry**` reads as `ferry`.
  """
  def to_text(nil), do: ""

  def to_text(markdown) when is_binary(markdown) do
    markdown
    |> String.replace(~r/!\[\[[^\]\n]*\]\]/, "")
    |> String.replace(~r/\[\[(?:[^\]|\n]*\|)?([^\]\n]*)\]\]/, "\\1")
    |> to_html()
    # A block ends a run of words; an inline tag (emphasis, a link) sits
    # inside one, so it goes without leaving a space before the punctuation.
    |> String.replace(
      ~r{<br\s*/?>|</?(?:p|h[1-6]|li|ul|ol|div|blockquote|pre|table|tr|td|th)\b[^>]*>}i,
      " "
    )
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace(~w(&amp; &lt; &gt; &quot; &#39; &nbsp;), fn
      "&amp;" -> "&"
      "&lt;" -> "<"
      "&gt;" -> ">"
      "&quot;" -> "\""
      "&#39;" -> "'"
      "&nbsp;" -> " "
    end)
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end
end
