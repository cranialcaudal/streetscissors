defmodule WebWeb.BlogHTML do
  use WebWeb, :html

  embed_templates "blog_html/*"

  @doc """
  Builds a `/blog` URL that preserves the other control's state, so changing
  the sort does not silently drop an active keyword filter and vice versa.
  Defaults (newest first, no filter) are left out of the query string.
  """
  def blog_query(sort, keyword) do
    params =
      [{"sort", if(sort == "witnessed", do: "witnessed")}, {"keyword", keyword}]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    if params == [], do: "/blog", else: "/blog?" <> URI.encode_query(params)
  end
end
