defmodule WebWeb.BlogHTML do
  @moduledoc """
  The blog's templates (the files in `blog_html/`) and the small pieces they
  share: a post's date and reading time, its keyword links, the line that says
  how many posts a filter found, and the figure beside each title in the
  contents list.
  """

  use WebWeb, :html

  embed_templates "blog_html/*"

  @doc """
  Builds a `/blog` URL that preserves the other control's state, so changing
  the sort does not silently drop an active keyword filter and vice versa.
  Defaults (newest first, no filter) are left out of the query string.
  """
  def blog_query(sort, keyword) do
    params =
      [{"sort", if(sort == "witnessed", do: "viewed")}, {"keyword", keyword}]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    if params == [], do: "/blog", else: "/blog?" <> URI.encode_query(params)
  end

  attr :post, :map, required: true

  @doc "`THU 3 SEP 2026 · 6 MIN READ · 17 VIEWS` — the line set above a title."
  def post_meta(assigns) do
    ~H"""
    <p class="writing-meta">
      <.link href={~p"/day/#{Date.to_iso8601(@post.date)}"} class="day-link">
        <time class="dt-published" datetime={Date.to_iso8601(@post.date)}>
          {Calendar.strftime(@post.date, "%a %-d %b %Y")}
        </time>
      </.link>
      <span class="writing-meta-dot" aria-hidden="true">·</span>
      <span>{@post.read_min} min read</span>
      <span class="writing-meta-dot" aria-hidden="true">·</span>
      <span title="How many different people have read it">{witnessed(@post.hit_count)}</span>
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
          class={[if(@variant == :chips, do: "writing-chip", else: "writing-keyword"), "p-category"]}
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
      <%!-- Follow a thread, not an account: this keyword across the blog and
            the logs, as a feed. --%>
      <a :if={@keyword} href={~p"/feed?keyword=#{@keyword}"} class="writing-clear writing-follow">
        Follow “{@keyword}” by RSS
      </a>
    </p>
    """
  end

  # Built as one string so template formatting can never wedge a space
  # before the comma.
  defp result_text(count, keyword, sort) do
    noun = if count == 1, do: "1 post", else: "#{count} posts"
    filter = if keyword, do: " filed under #{keyword}", else: ""
    order = if sort == "witnessed", do: "most viewed first", else: "newest first"

    "Showing #{noun}#{filter}, #{order}"
  end

  @doc "The figure a contents row shows: read time, or witnesses when sorted by them."
  def contents_figure(post, "witnessed"), do: witnessed(post.hit_count)
  def contents_figure(post, _sort), do: "#{post.read_min} min"

  # Witnesses, not page loads — the same word, and the same count, as the logs.
  # A reader sees "views", as on the logs; what is counted is still people.
  defp witnessed(1), do: "1 view"
  defp witnessed(count), do: "#{count} views"
end
