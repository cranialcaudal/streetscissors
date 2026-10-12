defmodule WebWeb.BlogNeighboursTest do
  use WebWeb.ConnCase, async: true

  # Fixture posts (test/support/fixtures/blog), non-draft, newest first:
  #   bare-post            (no frontmatter; date falls back to file mtime, 2026-08-03)
  #   keyworded-post       2026-07-15
  #   block-list-post      2026-07-10
  #   frontmatter-and-embeds 2026-07-01
  # draft-post (2026-07-20, draft: true) is never linked.

  defp neighbours_nav(html) do
    [nav] = Regex.run(~r|<nav[^>]*class="blog-post-neighbours".*?</nav>|s, html)
    nav
  end

  test "a post between two others links to both an older and a newer neighbour", %{conn: conn} do
    html = conn |> get("/blog/keyworded-post") |> html_response(200)
    nav = neighbours_nav(html)

    assert html =~ ~s(class="blog-post-neighbours")
    assert nav =~ ~s(rel="prev")
    assert nav =~ ~s(rel="next")
  end

  test "the newest post has no next neighbour in its nav", %{conn: conn} do
    html = conn |> get("/blog/bare-post") |> html_response(200)
    nav = neighbours_nav(html)

    assert nav =~ ~s(rel="prev")
    refute nav =~ ~s(rel="next")
    refute nav =~ ~s(href="/blog/bare-post")
  end

  test "a draft is never linked from the neighbours nav", %{conn: conn} do
    for slug <- ["keyworded-post", "bare-post"] do
      html = conn |> get("/blog/#{slug}") |> html_response(200)
      refute neighbours_nav(html) =~ "draft-post"
    end
  end
end
