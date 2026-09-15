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
