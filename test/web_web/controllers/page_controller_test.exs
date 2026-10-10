defmodule WebWeb.PageControllerTest do
  use WebWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "streetscissors"
    assert html =~ "Contact Sheets/Photos"
    assert html =~ ~s(href="/blog")
    # The manual is only reachable from here and /about — if this link goes, it
    # becomes a page nobody can find.
    assert html =~ ~s(href="/how-to?from=home")
    # The prayer pages took the manual's card; the manual dropped to the foot.
    [cards] = Regex.run(~r{<div class="bento-fitness-sub-row.*?</div>}s, html)
    assert cards =~ ~s(href="/Christ")
    refute cards =~ "/how-to"
    [footer] = Regex.run(~r{<footer class="home-footer">.*?</footer>}s, html)
    assert footer =~ ~s(href="/how-to?from=home")
    # The hero is the first screen's largest picture: sized, and never lazy.
    if html =~ "bento-hero-image" do
      [hero] = Regex.run(~r{<img[^>]*class="bento-hero-image"[^>]*>}s, html)
      assert hero =~ "w=960"
      assert hero =~ ~s(fetchpriority="high")
      refute hero =~ "lazy"
    end

    refute html =~ "Another Blog"
    refute html =~ "&#39;s Machine"
    refute html =~ "All Manuscripts"
  end

  # Both controls used to carry an inline `border: none`, which outranks every
  # stylesheet rule, so they rendered as loose words beside a framed playlist.
  test "GET / frames both top-bar controls and lets the keyboard open the playlist",
       %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    [bar] = Regex.run(~r{<nav class="home-top-bar">.*?</nav>}s, html)

    assert bar =~ ~s(href="/guestbook")
    assert bar =~ ~s(aria-label="Guestbook")
    assert bar =~ ~s(aria-label="Newsletter and Contact")
    assert Regex.scan(~r/class="top-bar-link"/, bar) |> length() == 2
    refute bar =~ "border: none"

    assert bar =~ ~s(class="spotify-pill-main" tabindex="0")
    refute bar =~ "#1DB954"
  end

  describe "GET /search" do
    test "the page is a form, reachable from the homepage and every header", %{conn: conn} do
      html = conn |> get(~p"/search") |> html_response(200)

      assert html =~ ~s(<form action="/search" method="get" role="search")
      assert html =~ ~s(name="robots" content="noindex, follow")
      refute html =~ "site-search-group"

      # The homepage has its own bar, and search is a mark in it.
      home = conn |> get(~p"/") |> html_response(200)
      [bar] = Regex.run(~r{<nav class="home-top-bar">.*?</nav>}s, home)

      assert bar =~
               ~s(<a href="/search" class="top-bar-link top-bar-link--search" aria-label="Search">)

      assert bar =~ "hero-magnifying-glass "
      # On a phone it is drawn as a field with its word in it (home.css).
      assert bar =~ ~s(<span class="top-bar-search-word" aria-hidden="true">Search</span>)

      # The shared header carries it on every inner page.
      assert conn |> get(~p"/about") |> html_response(200) =~
               ~s(<a href="/search" class="header-action header-action--search" aria-label="Search">)

      # Icons are an allowlist in app.css: one that is not on it renders as
      # an empty square, which is how this control first shipped.
      assert File.read!("assets/css/app.css") =~ ~r/@source inline\("[^"]*hero-magnifying-glass /
    end

    test "results come grouped by section, with the query kept in the field", %{conn: conn} do
      html = conn |> get(~p"/search?q=push-ups") |> html_response(200)

      assert html =~ ~s(value="push-ups")
      assert html =~ "Exercise wiki"
      assert html =~ ~s(href="/fitness/wiki/push-ups")
    end

    test "nothing found and too short both say so", %{conn: conn} do
      assert conn |> get(~p"/search?q=zzzzqqqq") |> html_response(200) =~
               "Nothing here matches “zzzzqqqq”"

      assert conn |> get(~p"/search?q=z") |> html_response(200) =~
               "Type at least two characters."
    end

    test "a query is escaped, not rendered", %{conn: conn} do
      html = conn |> get("/search?q=%3Cscript%3Ealert(1)%3C/script%3E") |> html_response(200)
      refute html =~ "<script>alert(1)</script>"
    end

    test "the field says where to ask for suggestions, and they come back as JSON",
         %{conn: conn} do
      assert conn |> get(~p"/search") |> html_response(200) =~ ~s(data-suggest="/search/suggest")

      conn = get(conn, ~p"/search/suggest?q=push")

      assert [%{"title" => "Push-ups", "path" => "/fitness/wiki/push-ups", "section" => section}] =
               json_response(conn, 200)

      assert section == "Exercise wiki"
      assert get_resp_header(conn, "x-robots-tag") == ["noindex"]

      # As a browser's fetch sends it.
      assert build_conn()
             |> put_req_header("accept", "*/*")
             |> get(~p"/search/suggest?q=push")
             |> json_response(200) != []

      assert build_conn() |> get(~p"/search/suggest") |> json_response(200) == []
      assert build_conn() |> get("/search/suggest?q[]=x") |> json_response(200) == []
    end

    test "one address may not search without limit", %{conn: conn} do
      Web.RateLimit.reset_all()
      for _ <- 1..30, do: conn |> get(~p"/search?q=push") |> html_response(200)

      assert conn |> get(~p"/search?q=push") |> html_response(429) =~ "a lot of searching"
      Web.RateLimit.reset_all()
    end
  end

  describe "GET /how-to" do
    test "renders the manual from docs/how-to.md", %{conn: conn} do
      conn = get(conn, ~p"/how-to")
      html = html_response(conn, 200)

      assert html =~ "How this is made"
      # Markdown actually went through Earmark rather than reaching the page raw.
      refute html =~ "## Part 1"
      assert html =~ "<table>"
      assert html =~ "<h2 id="
    end

    test "every link in the contents rail points at a heading that exists", %{conn: conn} do
      html = conn |> get(~p"/how-to") |> html_response(200)

      [_, rail] = Regex.run(~r{<ol class="howto-contents-list">(.*?)</ol>}s, html)

      anchors = capture_all(~r/href="#([^"]+)"/, rail)
      headings = capture_all(~r/<h[23] id="([^"]+)"/, html)

      assert length(anchors) >= 8, "the rail should list every part of the manual"
      assert anchors -- headings == [], "a contents link points nowhere"
    end
  end

  # The calendar reference names venues and times, so it is the author's alone.
  describe "GET /admin/fitness/calendar" do
    test "404s without the admin session, and the old public path is gone", %{conn: conn} do
      assert conn |> get(~p"/admin/fitness/calendar") |> html_response(404)
      assert conn |> get("/calendar-markdown") |> html_response(404)
    end

    test "renders for the admin", %{conn: conn} do
      conn =
        conn |> init_test_session(%{"admin_user" => true}) |> get(~p"/admin/fitness/calendar")

      assert html_response(conn, 200) =~ ~s(content="noindex, nofollow")
    end
  end

  # Against the fixture vault (config/test.exs); the real meals.md is checked
  # in the gitignored test/private/.
  describe "GET /food" do
    test "renders the kitchen from the fitness vault's meals.md", %{conn: conn} do
      html = conn |> get(~p"/food") |> html_response(200)

      assert html =~ "The Kitchen"
      # Markdown actually went through Earmark rather than reaching the page raw.
      refute html =~ "## Staples"
      assert html =~ "<h2 id="
    end

    # The strip and its description come from meals-week.json, and every day
    # has to land on a heading meals.md actually has.
    test "the week strip comes from meals-week.json and jumps to real headings", %{conn: conn} do
      html = conn |> get(~p"/food") |> html_response(200)

      assert html =~ "A fixture kitchen for the test suite."
      assert html =~ "Batch Cook"
      assert html =~ "2100 kcal"

      [_, strip] = Regex.run(~r{<nav class="week-strip"[^>]*>(.*?)</nav>}s, html)
      anchors = capture_all(~r/href="#([^"]+)"/, strip)
      headings = capture_all(~r/<h[23] id="([^"]+)"/, html)

      assert anchors == ["sunday", "monday"]
      assert anchors -- headings == []
    end

    # The macro tables are the point of the page; if they arrive as raw pipes
    # the plan is unreadable.
    test "renders the macro tables as real tables", %{conn: conn} do
      html = conn |> get(~p"/food") |> html_response(200)

      assert html =~ "<table>"
      refute html =~ "|---|"
      assert html =~ "Lentils"
    end

    # Earmark has no GFM task lists, so without Web.Docs' substitution the
    # shopping list renders as prose beginning with a literal "[ ]".
    test "renders the shopping list as real checkboxes", %{conn: conn} do
      html = conn |> get(~p"/food") |> html_response(200)

      assert html =~ ~s(<li class="task"><input type="checkbox" />)
      refute html =~ "[ ]"
    end

    test "every link in the contents rail points at a heading that exists", %{conn: conn} do
      html = conn |> get(~p"/food") |> html_response(200)

      [_, rail] = Regex.run(~r{<ol class="meals-contents-list">(.*?)</ol>}s, html)

      anchors = capture_all(~r/href="#([^"]+)"/, rail)
      headings = capture_all(~r/<h[23] id="([^"]+)"/, html)

      assert length(anchors) >= 6, "the rail should list every part of the plan"
      assert anchors -- headings == [], "a contents link points nowhere"
    end

    # The page is unlisted, which is a property of the whole site rather than of
    # this template: the tab row must lead out without any route leading back,
    # and a crawler that guesses the path must be told not to index it.
    test "is unlisted — noindex, and nothing links back to it", %{conn: conn} do
      html = conn |> get(~p"/food") |> html_response(200)

      assert html =~ ~s(<meta name="robots" content="noindex, nofollow")

      assert html =~ ~s(href="/fitness/wiki")
      assert html =~ ~s(href="/fitness/rides")
      refute html =~ ~s(href="/food")

      sitemap = conn |> get(~p"/sitemap.xml") |> response(200)
      refute sitemap =~ "/food"
    end

    # It used to live here, and the /fitness/:slug catch-all now takes the path.
    test "the old /fitness/meals path no longer serves the page", %{conn: conn} do
      conn = get(conn, "/fitness/meals")

      assert conn.status in [301, 302]
    end
  end

  defp capture_all(regex, html) do
    regex |> Regex.scan(html) |> Enum.map(fn [_full, capture] -> capture end)
  end

  test "GET / degrades gracefully when the negatives directory is missing", %{conn: conn} do
    original = Application.get_env(:web, :negatives_path)
    Application.put_env(:web, :negatives_path, "/nonexistent-negatives-path")

    try do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ "Contact Sheets/Photos"
      refute html =~ "bento-hero-image"
    after
      if original,
        do: Application.put_env(:web, :negatives_path, original),
        else: Application.delete_env(:web, :negatives_path)
    end
  end
end
