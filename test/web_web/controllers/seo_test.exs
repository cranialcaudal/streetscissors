defmodule WebWeb.SEOTest do
  use WebWeb.ConnCase

  describe "page metadata" do
    test "every page carries a description, canonical and absolute og:image", %{conn: conn} do
      html = conn |> get(~p"/blog") |> html_response(200)

      assert html =~ ~s(<meta name="description")
      assert html =~ ~s(rel="canonical")
      # A relative og:image is silently ignored by every unfurler.
      assert html =~ ~r|<meta property="og:image" content="https?://[^"]+/images/|
      assert html =~ ~s(<meta property="og:type")
      assert html =~ ~s(<meta property="og:site_name")
    end

    test "a post gets its own card rather than the site-wide default", %{conn: conn} do
      html = conn |> get(~p"/blog/frontmatter-and-embeds") |> html_response(200)

      assert html =~ ~s(<meta property="og:title" content="Fixture Post With Frontmatter")
      assert html =~ "A fixture description used as the excerpt."
      assert html =~ ~s(<meta property="og:type" content="article")

      canonical = WebWeb.SEO.absolute("/blog/frontmatter-and-embeds")
      assert html =~ ~s(rel="canonical" href="#{canonical}")
      assert html =~ ~s(<meta property="og:url" content="#{canonical}")
    end

    test "the blog index no longer shares the homepage's title", %{conn: conn} do
      blog = conn |> get(~p"/blog") |> html_response(200)
      home = build_conn() |> get(~p"/") |> html_response(200)

      assert blog =~ "<title"
      refute title_of(blog) == title_of(home)
    end

    test "the feed is discoverable from the page", %{conn: conn} do
      html = conn |> get(~p"/blog") |> html_response(200)
      assert html =~ ~s(rel="alternate")
      assert html =~ ~s(type="application/rss+xml")
    end

    defp title_of(html) do
      case Regex.run(~r|<title[^>]*>(.*?)</title>|s, html) do
        [_, title] -> String.trim(title)
        _ -> nil
      end
    end
  end

  describe "sitemap" do
    test "uses the configured https host, never a hardcoded http one", %{conn: conn} do
      xml = conn |> get(~p"/sitemap.xml") |> response(200)

      # Search engines treat http:// and https:// as different sites.
      refute xml =~ "http://streetscissors.com"
      assert xml =~ "<loc>"
    end

    test "includes posts and the sections that were previously omitted", %{conn: conn} do
      xml = conn |> get(~p"/sitemap.xml") |> response(200)

      assert xml =~ "/blog/frontmatter-and-embeds"
      assert xml =~ "/fitness/wiki"
      assert xml =~ "/logs"
      assert xml =~ "/guestbook"
    end

    test "lastmod reflects the post's real date, not today", %{conn: conn} do
      xml = conn |> get(~p"/sitemap.xml") |> response(200)

      assert xml =~ "<lastmod>2026-07-01</lastmod>"
      refute xml =~ "<lastmod>#{Date.utc_today()}</lastmod>"
    end
  end

  describe "feed" do
    test "is served as RSS and is self-describing", %{conn: conn} do
      conn = get(conn, ~p"/feed")

      assert get_resp_header(conn, "content-type") |> hd() =~ "application/rss+xml"
      body = response(conn, 200)

      assert body =~ ~s(rel="self")
      assert body =~ "<language>en</language>"
    end

    test "pubDate is RFC 822 with a numeric offset, not a mislabelled local time", %{conn: conn} do
      body = conn |> get(~p"/feed") |> response(200)

      assert body =~ ~r|<pubDate>\w{3}, \d{2} \w{3} \d{4} \d{2}:\d{2}:\d{2} \+0000</pubDate>|
      refute body =~ "GMT"
    end

    test "the channel link agrees with the item links about the scheme", %{conn: conn} do
      body = conn |> get(~p"/feed") |> response(200)
      refute body =~ "http://streetscissors.com"
    end
  end

  describe "robots.txt" do
    test "points crawlers at the sitemap and keeps them out of admin" do
      robots = File.read!("priv/static/robots.txt")

      assert robots =~ "Sitemap: https://streetscissors.com/sitemap.xml"
      assert robots =~ "Disallow: /admin/"
      assert robots =~ "Disallow: /dev/"
      # The site should still be indexable overall.
      assert robots =~ "User-agent: *\nAllow: /"
    end
  end
end
