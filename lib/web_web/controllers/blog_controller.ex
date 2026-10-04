defmodule WebWeb.BlogController do
  use WebWeb, :controller

  alias Web.Blog
  alias Web.Keywords
  alias WebWeb.SEO
  import WebWeb.Navigation, only: [return_context: 1]

  def index(conn, params) do
    hit_counts = hit_counts()

    posts =
      Blog.list_posts()
      |> Enum.map(&Map.put(&1, :hit_count, Map.get(hit_counts, Keywords.slugify(&1.slug), 0)))

    keyword = filter_keyword(params["keyword"])
    sort = parse_sort(params["sort"])

    visible =
      posts
      |> Enum.filter(&Keywords.match?(&1.keywords, keyword))
      |> sort_posts(sort)

    {return_to, return_label} = return_context(params["from"])
    crumbs = [{"Home", ~p"/"}, {"Writing", ~p"/blog"}]

    conn
    |> assign(:page_title, "Writing")
    |> assign(:og_description, "Notes, essays and photographs from the streetscissors darkroom.")
    |> assign(:canonical_path, ~p"/blog")
    |> assign(:keyword_feed, keyword && ~p"/feed?keyword=#{keyword}")
    |> assign(:json_ld, SEO.breadcrumb_json_ld(crumbs))
    |> render(:index,
      posts: visible,
      # Tallied across every post, not the filtered set, so the bar does not
      # collapse to a single chip once a filter is on.
      keywords: Keywords.tally(Enum.map(posts, & &1.keywords)),
      keyword: keyword,
      return_to: return_to,
      return_label: return_label,
      sort: sort
    )
  end

  # Legacy category URLs from before the blog merge; keep old links working.
  def show(conn, %{"slug" => slug})
      when slug in ["latent-sensus", "another-blog", "sensus"] do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/blog")
  end

  def show(conn, %{"slug" => "fitness-blog"}) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/fitness")
  end

  def show(conn, %{"slug" => "sports-blog"}) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/blog")
  end

  # A post filed under a title ("Tide's Out.md") used to be served at that
  # title, spaces and all. Its clean address is the slug the admin uploader
  # names files with, so once a file by that name exists the old URL moves
  # there for good. Only then: until the vault file is renamed, the old URL is
  # still the one that works.
  def show(conn, %{"slug" => slug} = params) do
    clean = Keywords.slugify(slug)

    if clean != slug and match?({:ok, _}, Blog.get_post(clean)) do
      conn
      |> put_status(:moved_permanently)
      |> redirect(to: ~p"/blog/#{clean}")
    else
      render_post(conn, slug, params)
    end
  end

  defp render_post(conn, slug, params) do
    case Blog.get_post(slug) do
      {:ok, post} ->
        html =
          case Earmark.as_html(post.body, gfm: true) do
            {:ok, html, _} -> html
            {:error, html, _} -> html
          end

        post =
          post
          |> Map.put(:html, Web.Blog.Embeds.transform(html))
          |> Map.put(:hit_count, Map.get(hit_counts(), Keywords.slugify(slug), 0))

        {return_to, return_label} = return_context(params["from"] || "blog")
        crumbs = [{"Home", ~p"/"}, {"Writing", ~p"/blog"}, {post.title, ~p"/blog/#{post.slug}"}]

        json_ld = [
          SEO.article_json_ld(post),
          SEO.breadcrumb_json_ld(crumbs)
        ]

        conn
        |> assign(:page_title, post.title)
        # Its own social card and canonical URL, rather than the site-wide
        # default every page used to share.
        |> assign(:og_title, post.title)
        |> assign(:og_description, post.excerpt)
        |> assign(:og_type, "article")
        |> assign(:canonical_path, ~p"/blog/#{post.slug}")
        |> assign(:json_ld, json_ld)
        |> render(:show, post: post, return_to: return_to, return_label: return_label)

      {:error, _} ->
        conn
        |> put_status(:not_found)
        |> put_view(WebWeb.ErrorHTML)
        |> render("404.html")
    end
  end

  defp parse_sort("witnessed"), do: "witnessed"
  defp parse_sort(_), do: "recent"

  # list_posts/0 already returns newest first, so "recent" is the identity.
  defp sort_posts(posts, "witnessed"), do: Enum.sort_by(posts, & &1.hit_count, :desc)
  defp sort_posts(posts, _), do: posts

  # A filter that normalizes to nothing (punctuation, blanks) is no filter.
  defp filter_keyword(nil), do: nil

  defp filter_keyword(raw) do
    case Keywords.normalize(raw) do
      "" -> nil
      keyword -> keyword
    end
  end

  # View counts keyed by clean slug. Merges the pre-rename /manuscripts prefix,
  # and folds a post's old title-shaped address ("/blog/Tide's%20Out")
  # into its clean one, so historical hits survive both moves. A count is
  # witnesses, not page loads: the visitor sets are unioned across every
  # address a post has lived at, so someone who read it at two of them — or
  # ten times at one — witnessed it once.
  defp hit_counts do
    Map.merge(
      Web.Analytics.visitors_by_prefix("/manuscripts/latent-sensus/%"),
      Web.Analytics.visitors_by_prefix("/blog/%"),
      fn _slug, old, new -> MapSet.union(old, new) end
    )
    |> Enum.reduce(%{}, fn {slug, visitors}, acc ->
      Map.update(acc, Keywords.slugify(slug), visitors, &MapSet.union(&1, visitors))
    end)
    |> Map.new(fn {slug, visitors} -> {slug, MapSet.size(visitors)} end)
  end
end
