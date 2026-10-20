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
end
