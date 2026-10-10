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

  describe "author structured data" do
    # The author's name is configuration (AUTHOR_NAME), not code.
    test "names the configured author", %{conn: conn} do
      with_author("Ada Example", fn ->
        html = conn |> get(~p"/") |> html_response(200)

        assert html =~ ~s("@type":"Person")
        assert html =~ ~s("name":"Ada Example")
        assert html =~ "streetscissors · Ada Example"
      end)
    end

    test "about page contains ProfilePage structured data and author name", %{conn: conn} do
      with_author("Ada Example", fn ->
        html = conn |> get(~p"/about") |> html_response(200)

        assert html =~ "About · Ada Example"
        assert html =~ ~s("@type":"ProfilePage")
        assert html =~ ~s("name":"Ada Example")
        # What she does and where is the vault's to say (content/about.json).
        assert html =~ ~s("jobTitle":"Archivist")
        assert html =~ ~s("name":"Example University")
        assert html =~ "About Ada Example — an invented person for the tests."
      end)
    end

    test "with nothing said of the author, the pages say less and still render", %{conn: conn} do
      was = Application.get_env(:web, :about_json_path)
      Application.put_env(:web, :about_json_path, "/nonexistent/about.json")
      on_exit(fn -> Application.put_env(:web, :about_json_path, was) end)

      with_author(nil, fn ->
        about = conn |> get(~p"/about") |> html_response(200)
        assert about =~ "About · the author"
        refute about =~ "jobTitle"
        refute about =~ "worksFor"

        home = conn |> get(~p"/") |> html_response(200)
        refute home =~ "open.spotify.com/user"
        assert home =~ "streetscissors."
      end)
    end

    test "the homepage names its author and links a profile only as the host says", %{conn: conn} do
      with_author("Ada Example", fn ->
        home = conn |> get(~p"/") |> html_response(200)
        assert home =~ ~s(href="https://open.spotify.com/user/example")
        assert home =~ "Ada Example"
        assert home =~ "#{Web.Clock.local_today().year}"
      end)
    end

    test "emits no Person at all when no author is configured", %{conn: conn} do
      with_author(nil, fn ->
        html = conn |> get(~p"/") |> html_response(200)

        refute html =~ ~s("@type":"Person")
        # The site's own structured data is unaffected.
        assert html =~ ~s("@type":"WebSite")
      end)
    end

    defp with_author(name, fun) do
      prev = Application.get_env(:web, :author_name)

      if name,
        do: Application.put_env(:web, :author_name, name),
        else: Application.delete_env(:web, :author_name)

      try do
        fun.()
      after
        if prev,
          do: Application.put_env(:web, :author_name, prev),
          else: Application.delete_env(:web, :author_name)
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

    # A roll only became addressable when /negatives/roll/:roll was added, and
    # these URLs are built as plain strings rather than ~p sigils — so the
    # compiler will not notice if the route moves. This is what does.
    test "lists each roll, and the printed frames under it", %{conn: conn} do
      xml = conn |> get(~p"/sitemap.xml") |> response(200)

      assert xml =~ "/negatives/roll/001"
      # The committed fixture archive has one print on roll 1.
      assert xml =~ "/negatives/roll/001/frame/1"
      # Padded, so one roll is one URL rather than three.
      refute xml =~ "/negatives/roll/1<"
      refute xml =~ "?slug="
    end

    # Scoped to a dated post: undated fixtures fall back to the file's mtime,
    # which is today on any fresh checkout, so a sitemap-wide refute only ever
    # passed on a machine whose fixture files happened to be old.
    test "lastmod reflects the post's real date, not today", %{conn: conn} do
      xml = conn |> get(~p"/sitemap.xml") |> response(200)

      [entry] =
        Regex.run(~r{<url>\s*<loc>[^<]*/blog/frontmatter-and-embeds</loc>.*?</url>}s, xml)

      assert entry =~ "<lastmod>2026-07-01</lastmod>"
      refute entry =~ "<lastmod>#{Date.utc_today()}</lastmod>"
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

  describe "structured data (JSON-LD)" do
    test "blog post includes BlogPosting and BreadcrumbList", %{conn: conn} do
      html = conn |> get(~p"/blog/frontmatter-and-embeds") |> html_response(200)

      assert html =~ ~s("@type":"BlogPosting")
      assert html =~ ~s("headline":"Fixture Post With Frontmatter")
      assert html =~ ~s("@type":"BreadcrumbList")
      assert html =~ ~s("name":"Writing")
    end

    test "blog index includes BreadcrumbList", %{conn: conn} do
      html = conn |> get(~p"/blog") |> html_response(200)

      assert html =~ ~s("@type":"BreadcrumbList")
      assert html =~ ~s("name":"Writing")
    end
  end

  describe "PWA support" do
    test "serves manifest.json with standalone display and theme colors", %{conn: conn} do
      conn = get(conn, "/manifest.json")
      assert response(conn, 200)
      body = json_response(conn, 200)

      assert body["name"] == "streetscissors"
      assert body["display"] == "standalone"
      assert body["theme_color"] == "#17140f"
      assert body["background_color"] == "#f3eee4"
      assert is_list(body["icons"])
      assert length(body["icons"]) >= 3
    end

    # A deploy fingerprints static files, and `~p` hands out the fingerprinted
    # name. Root-level files are served by exact name only, so the manifest
    # linked through `~p` was /manifest-<hash>.json: a 404 on every page, and
    # only on the live site, where there are fingerprints.
    test "every page links the manifest at the address it is served from", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)
      assert html =~ ~s(<link rel="manifest" href="/manifest.json">)

      layout = File.read!("lib/web_web/components/layouts/root.html.heex")
      assert layout =~ ~s(<link rel="manifest" href="/manifest.json" />)
      refute layout =~ ~s(~p"/manifest.json")
    end

    test "serves service worker sw.js", %{conn: conn} do
      conn = get(conn, "/sw.js")
      assert response(conn, 200)
      assert get_resp_header(conn, "content-type") |> hd() =~ "javascript"
    end

    test "serves google site verification HTML file", %{conn: conn} do
      conn = get(conn, "/google0a37fc5aaf651faf.html")
      assert response(conn, 200) =~ "google-site-verification: google0a37fc5aaf651faf.html"
    end
  end
end
