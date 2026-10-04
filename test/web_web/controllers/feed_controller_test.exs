defmodule WebWeb.FeedControllerTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  import Web.AudioFixtures

  # Fixture posts carry the keywords film and bowling-green (keyworded-post);
  # roll 001 is the fixture archive's one roll.

  test "the feed carries every section: posts, logs and film", %{conn: conn} do
    log = log_fixture(%{recorded_on: ~D[2026-07-20], caption: "Under way", size_bytes: 1234})
    body = conn |> get("/feed") |> response(200)

    assert body =~ "/blog/keyworded-post"
    assert body =~ "/logs/#{log.slug}"
    assert body =~ "/negatives/roll/001"
    assert body =~ "<title>streetscissors</title>"
  end

  test "a log item carries its media as an enclosure, for podcast apps", %{conn: conn} do
    log = log_fixture(%{recorded_on: ~D[2026-07-20], size_bytes: 1234})
    body = conn |> get("/feed") |> response(200)

    assert body =~
             ~s(<enclosure url="http://localhost:4000#{Web.Audio.Log.media_url(log)}" length="1234" type="video/mp4" />)
  end

  test "a draft log is not in the feed", %{conn: conn} do
    draft = log_fixture(%{recorded_on: ~D[2026-07-21], published: false})
    refute conn |> get("/feed") |> response(200) =~ "/logs/#{draft.slug}"
  end

  test "?keyword= follows one thread across the blog and the logs", %{conn: conn} do
    log = log_fixture(%{recorded_on: ~D[2026-07-22], keywords: "film"})
    other = log_fixture(%{recorded_on: ~D[2026-07-23], keywords: "ferry"})

    body = conn |> get("/feed?keyword=Film") |> response(200)

    assert body =~ "streetscissors · film"
    assert body =~ "/blog/keyworded-post"
    assert body =~ "/logs/#{log.slug}"
    refute body =~ "/logs/#{other.slug}"
    refute body =~ "/negatives/roll/"
    assert body =~ ~s(href="http://localhost:4000/feed?keyword=film" rel="self")
  end

  test "an unknown keyword is a 404, not an empty feed", %{conn: conn} do
    assert conn |> get("/feed?keyword=no-such-thing") |> response(404)
  end

  test "a filtered index offers its keyword's feed", %{conn: conn} do
    html = conn |> get("/blog?keyword=film") |> html_response(200)

    assert html =~
             ~s(<link rel="alternate" type="application/rss+xml" title="streetscissors · film" href="/feed?keyword=film")

    assert html =~ "Follow “film” by RSS"

    log_fixture(%{recorded_on: ~D[2026-07-24], keywords: "ferry"})
    {:ok, view, _html} = live(conn, "/logs?keyword=ferry")
    assert has_element?(view, ~s(a.console-follow[href="/feed?keyword=ferry"]))
  end
end
