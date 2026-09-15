defmodule WebWeb.BlogControllerTest do
  use WebWeb.ConnCase

  test "GET /blog lists fixture posts with frontmatter metadata", %{conn: conn} do
    conn = get(conn, ~p"/blog")
    html = html_response(conn, 200)
    assert html =~ "streetscissors"
    assert html =~ "Fixture Post With Frontmatter"
    assert html =~ "A fixture description used as the excerpt."
    assert html =~ "Bare Post"
    refute html =~ "description:"
  end

  test "legacy category slugs permanently redirect" do
    for slug <- ["latent-sensus", "another-blog", "sensus"] do
      conn = get(build_conn(), "/blog/#{slug}")
      assert redirected_to(conn, 301) == "/blog"
    end

    conn = get(build_conn(), "/blog/fitness-blog")
    assert redirected_to(conn, 301) == "/fitness"

    conn = get(build_conn(), "/blog/sports-blog")
    assert redirected_to(conn, 301) == "/blog"
  end

  test "GET /blog/:slug renders a post without visible frontmatter", %{conn: conn} do
    conn = get(conn, ~p"/blog/frontmatter-and-embeds")
    html = html_response(conn, 200)
    assert html =~ "Fixture Post With Frontmatter"
    # The meta line: the day, then read time and views — no icon row.
    assert html =~ "Wed 1 Jul 2026"
    assert html =~ "min read"
    refute html =~ "fa-paragraph"
    refute html =~ "description:"
    # Unresolvable embed stays literal text — never a broken image
    assert html =~ "![[roll999]]"
    # Standard markdown images pass through Earmark
    assert html =~ ~s(<img src="/uploads/example.png")
  end

  test "GET /blog/bare-post falls back to filename-derived title", %{conn: conn} do
    conn = get(conn, ~p"/blog/bare-post")
    assert html_response(conn, 200) =~ "Bare Post"
  end

  test "GET /blog/:slug returns 404 for unknown posts", %{conn: conn} do
    conn = get(conn, ~p"/blog/there-is-no-such-post")
    assert response(conn, 404)
  end

  describe "lead story and contents" do
    test "the first post leads and every other post is a contents row, in order", %{conn: conn} do
      [lead | rest] = Web.Blog.list_posts()
      html = conn |> get(~p"/blog") |> html_response(200)

      assert [lead_html] = Regex.run(~r{<article class="writing-lead">.*?</article>}s, html)
      assert lead_html =~ lead.title
      assert lead_html =~ "Read the post"

      assert length(Regex.scan(~r{<li class="writing-entry">}, html)) == length(rest)

      positions = Enum.map(rest, fn post -> html |> :binary.match(post.title) |> elem(0) end)
      assert positions == Enum.sort(positions)

      assert html =~ "Earlier"
      refute html =~ "NEW!"
      refute html =~ "fa-paragraph"
    end

    test "the lead's keywords are labelled links back into the filtered index", %{conn: conn} do
      html = conn |> get(~p"/blog?keyword=film") |> html_response(200)

      assert [lead_html] = Regex.run(~r{<article class="writing-lead">.*?</article>}s, html)
      assert lead_html =~ "Filed under:"
      assert lead_html =~ ~s(href="/blog?keyword=bowling-green")
    end

    test "sorting by most witnessed leads with the most-read post", %{conn: conn} do
      for visitor <- ~w(a b c) do
        Web.Analytics.record_hit("/blog/frontmatter-and-embeds", "Firefox", "visitor-#{visitor}")
      end

      html = conn |> get(~p"/blog?sort=witnessed") |> html_response(200)

      assert [lead_html] = Regex.run(~r{<article class="writing-lead">.*?</article>}s, html)
      assert lead_html =~ "Fixture Post With Frontmatter"
      assert lead_html =~ "3 views"

      # The contents column follows the sort: views, not read time.
      assert html =~ "More"
      assert html =~ "0 views"
    end
  end

  describe "result line" do
    test "says what the list is showing", %{conn: conn} do
      html = conn |> get(~p"/blog") |> html_response(200)

      assert html =~ "Showing #{length(Web.Blog.list_posts())} posts, newest first"
      refute html =~ "Clear filter"
    end

    test "names an active filter and offers the way back out", %{conn: conn} do
      html = conn |> get(~p"/blog?keyword=film") |> html_response(200)

      assert html =~ "Showing 1 post filed under film, newest first"
      assert html =~ ~s(<a href="/blog" class="writing-clear">)
    end

    test "clearing a filter keeps the sort", %{conn: conn} do
      html = conn |> get(~p"/blog?sort=witnessed&keyword=film") |> html_response(200)

      assert html =~ "most witnessed first"
      assert html =~ ~s(<a href="/blog?sort=witnessed" class="writing-clear">)
    end
  end

  describe "keywords" do
    test "the index renders a keyword filter bar from every post's frontmatter", %{conn: conn} do
      html = conn |> get(~p"/blog") |> html_response(200)

      assert html =~ "Filter by keyword"
      assert html =~ "bowling-green"
      # Obsidian's block-list `tags:` form feeds the same bar
      assert html =~ "night-walk"
    end

    test "?keyword= filters the feed", %{conn: conn} do
      html = conn |> get(~p"/blog?keyword=bowling-green") |> html_response(200)

      assert html =~ "Fixture Post With Keywords"
      refute html =~ "Fixture Post With A Block List"
    end

    test "a keyword filter normalizes, so a human-typed value still matches", %{conn: conn} do
      html = conn |> get(~p"/blog?keyword=Bowling%20Green") |> html_response(200)
      assert html =~ "Fixture Post With Keywords"
    end

    test "a keyword nothing is filed under renders an empty state", %{conn: conn} do
      html = conn |> get(~p"/blog?keyword=nothing-here") |> html_response(200)

      refute html =~ "Fixture Post With Keywords"
      assert html =~ "nothing-here"
      assert html =~ "See everything instead"
    end

    test "a junk keyword is treated as no filter rather than matching nothing", %{conn: conn} do
      html = conn |> get(~p"/blog?keyword=%21%21%21") |> html_response(200)
      assert html =~ "Fixture Post With Keywords"
      assert html =~ "Bare Post"
    end

    test "a post's keyword chips link back into the filtered index", %{conn: conn} do
      html = conn |> get(~p"/blog/keyworded-post") |> html_response(200)

      assert html =~ "Filed under:"
      assert html =~ "/blog?keyword=bowling-green"
    end
  end

  describe "sorting" do
    test "sort controls offer most recent and most witnessed", %{conn: conn} do
      html = conn |> get(~p"/blog") |> html_response(200)

      assert html =~ "Sort by"
      assert html =~ "Most Recent"
      assert html =~ "Most Witnessed"
      refute html =~ "Least Read"
    end

    test "the sort keeps an active keyword filter", %{conn: conn} do
      html = conn |> get(~p"/blog?keyword=film") |> html_response(200)
      assert html =~ "sort=witnessed&amp;keyword=film"
    end

    test "?sort=witnessed renders without error", %{conn: conn} do
      assert conn |> get(~p"/blog?sort=witnessed") |> html_response(200) =~ "Most Witnessed"
    end
  end

  test "the blog no longer serves audio — spoken work lives at /logs", %{conn: conn} do
    conn = get(conn, "/blog/audio/anything.mp3")
    assert response(conn, 404)
  end

  test "the blog index no longer carries a sticky audio player", %{conn: conn} do
    html = conn |> get(~p"/blog") |> html_response(200)

    refute html =~ "sensus-player-bar"
    refute html =~ "sensusPortalPlay"
    # ...and points at the section that does hold spoken work
    assert html =~ "/logs"
  end
end
