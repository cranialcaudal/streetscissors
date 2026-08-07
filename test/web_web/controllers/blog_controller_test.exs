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
    assert html =~ "July 01, 2026"
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

  describe "keywords" do
    test "the index renders a keyword filter bar from every post's frontmatter", %{conn: conn} do
      html = conn |> get(~p"/blog") |> html_response(200)

      assert html =~ "Keywords:"
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
    test "sort pills offer most recent and most witnessed", %{conn: conn} do
      html = conn |> get(~p"/blog") |> html_response(200)

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
