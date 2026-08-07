defmodule WebWeb.FeedController do
  use WebWeb, :controller

  @moduledoc """
  RSS 2.0 feed for the blog.

  Several things here were quietly wrong and are fixed:

    * `pubDate` stamped a **local-time** filesystem mtime with the literal
      string `"GMT"`, so every item's date was off by the server's UTC offset.
      Dates are now converted to real UTC and carry a numeric offset, which is
      what RFC 822 actually asks for.
    * The channel `<link>` said `http://` while item links said `https://` —
      one document disagreeing with itself about the site's identity.
    * The content type was `application/xml` rather than `application/rss+xml`.
    * There was no `<atom:link rel="self">`, which every feed validator warns
      about, and no `<language>`.
  """

  def index(conn, _params) do
    posts = Web.Blog.list_posts() |> Enum.take(20)

    conn
    |> put_resp_content_type("application/rss+xml")
    |> send_resp(200, generate_feed(posts))
  end

  defp generate_feed(posts) do
    items = Enum.map_join(posts, "\n", &generate_item/1)
    self_url = WebWeb.SEO.absolute("/feed")

    # Newest post date, not "now" — a fetch should not restate the whole feed
    # as freshly built.
    last_build =
      posts
      |> Enum.map(& &1.mtime)
      |> Enum.max(NaiveDateTime, fn -> NaiveDateTime.utc_now() end)

    """
    <?xml version="1.0" encoding="UTF-8" ?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
    <channel>
      <title>streetscissors</title>
      <description>streetscissors — notes and photographs</description>
      <link>#{WebWeb.SEO.base_url()}</link>
      <atom:link href="#{self_url}" rel="self" type="application/rss+xml" />
      <language>en</language>
      <lastBuildDate>#{to_rfc822(last_build)}</lastBuildDate>
      <ttl>1800</ttl>

      #{items}
    </channel>
    </rss>
    """
  end

  defp generate_item(post) do
    url = WebWeb.SEO.absolute("/blog/#{post.slug}")

    """
    <item>
      <title>#{escape_xml(post.title)}</title>
      <description>#{escape_xml(post.excerpt)}</description>
      <link>#{url}</link>
      <guid isPermaLink="true">#{url}</guid>
      <pubDate>#{to_rfc822(post.mtime)}</pubDate>
    </item>
    """
  end

  defp escape_xml(nil), do: ""

  defp escape_xml(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  # File mtimes are naive local time. Interpret them in the system's zone and
  # convert to UTC, rather than relabelling them "GMT" and shifting every date.
  defp to_rfc822(%NaiveDateTime{} = naive) do
    naive
    |> DateTime.from_naive!("Etc/UTC")
    |> to_rfc822()
  end

  defp to_rfc822(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%a, %d %b %Y %H:%M:%S +0000")
  end
end
