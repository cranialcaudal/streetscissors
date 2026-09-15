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

  attr :post, :map, required: true

  @doc "`THU 3 SEP 2026 · 6 MIN READ · 17 VIEWS` — the line set above a title."
  def post_meta(assigns) do
    ~H"""
    <p class="writing-meta">
      <time datetime={Date.to_iso8601(@post.date)}>
        {Calendar.strftime(@post.date, "%a %-d %b %Y")}
      </time>
      <span class="writing-meta-dot" aria-hidden="true">·</span>
      <span>{@post.read_min} min read</span>
      <span class="writing-meta-dot" aria-hidden="true">·</span>
      <span>{views(@post.hit_count)}</span>
    </p>
    """
  end

  attr :keywords, :list, required: true
  attr :sort, :string, default: "recent"
  attr :variant, :atom, default: :inline, values: [:inline, :chips]

  @doc """
  A post's keywords, each linking back into the index filtered on it. `:inline`
  is a line of underlined links (the lead story); `:chips` are the filter row's
  buttons (a post's "Filed under").
  """
  def keyword_links(assigns) do
    ~H"""
    <ul class={["writing-keywords", @variant == :chips && "writing-keywords--chips"]}>
      <li :for={keyword <- @keywords}>
        <a
          href={blog_query(@sort, keyword)}
          class={if @variant == :chips, do: "writing-chip", else: "writing-keyword"}
        >
          {keyword}
        </a>
      </li>
    </ul>
    """
  end

  attr :count, :integer, required: true
  attr :keyword, :string, default: nil
  attr :sort, :string, required: true

  @doc """
  What the list below is showing — so a filtered page never looks like the
  blog lost its posts — with a way back out of the filter.
  """
  def result_line(assigns) do
    ~H"""
    <p class="writing-result">
      <span>{result_text(@count, @keyword, @sort)}</span>
      <a :if={@keyword} href={blog_query(@sort, nil)} class="writing-clear">
        Clear filter <span aria-hidden="true">✕</span>
      </a>
    </p>
    """
  end

  # Built as one string so template formatting can never wedge a space
  # before the comma.
  defp result_text(count, keyword, sort) do
    noun = if count == 1, do: "1 post", else: "#{count} posts"
    filter = if keyword, do: " filed under #{keyword}", else: ""
    order = if sort == "witnessed", do: "most witnessed first", else: "newest first"

    "Showing #{noun}#{filter}, #{order}"
  end

  @doc "The figure a contents row shows: read time, or views when sorted by them."
  def contents_figure(post, "witnessed"), do: views(post.hit_count)
  def contents_figure(post, _sort), do: "#{post.read_min} min"

  defp views(1), do: "1 view"
  defp views(count), do: "#{count} views"
end
