defmodule WebWeb.LogsLiveTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest
  import Web.AudioFixtures

  describe "GET /logs" do
    test "lists published logs and hides drafts", %{conn: conn} do
      log_fixture(title: "Ferry To Bowling Green", published: true)
      log_fixture(title: "Unfinished Thought", published: false)

      {:ok, _view, html} = live(conn, ~p"/logs")

      assert html =~ "Captain&#39;s Logs" or html =~ "Captain's Logs"
      assert html =~ "Ferry To Bowling Green"
      refute html =~ "Unfinished Thought"
    end

    test "the sort lives in the URL so a view can be linked to", %{conn: conn} do
      log_fixture(title: "Older Louder", recorded_on: ~D[2026-01-01], keywords: "ferry")
      log_fixture(title: "Newer Quieter", recorded_on: ~D[2026-06-01], keywords: "ferry")

      {:ok, view, html} = live(conn, ~p"/logs")

      # Default is most recent
      assert html =~ "Newer Quieter"

      view |> element("a", "Most Witnessed") |> render_click()
      assert_patched(view, "/logs?sort=witnessed")
    end

    test "sorting by most witnessed orders on play count", %{conn: conn} do
      quiet = log_fixture(title: "Quiet One", recorded_on: ~D[2026-06-01])
      loud = log_fixture(title: "Loud One", recorded_on: ~D[2026-01-01])

      Web.Audio.record_play(loud.id, "127.0.0.1")
      Web.Audio.record_play(loud.id, "127.0.0.2")
      Web.Audio.record_play(quiet.id, "127.0.0.3")

      {:ok, _view, html} = live(conn, ~p"/logs?sort=witnessed")

      loud_at = :binary.match(html, "Loud One") |> elem(0)
      quiet_at = :binary.match(html, "Quiet One") |> elem(0)
      assert loud_at < quiet_at
    end

    test "filters by keyword, keeping the sort", %{conn: conn} do
      log_fixture(title: "Ferry Log", keywords: "ferry, nyc")
      log_fixture(title: "Desert Log", keywords: "desert")

      {:ok, _view, html} = live(conn, ~p"/logs?keyword=ferry")

      assert html =~ "Ferry Log"
      refute html =~ "Desert Log"

      {:ok, view, _html} = live(conn, ~p"/logs?sort=witnessed&keyword=ferry")
      view |> element("a", "Most Recent") |> render_click()
      assert_patched(view, "/logs?keyword=ferry")
    end

    test "a keyword nothing is filed under renders an empty state", %{conn: conn} do
      log_fixture(title: "Ferry Log", keywords: "ferry")

      {:ok, _view, html} = live(conn, ~p"/logs?keyword=nothing-here")

      refute html =~ "Ferry Log"
      assert html =~ "nothing-here"
    end

    test "a hand-mangled sort falls back rather than crashing", %{conn: conn} do
      log_fixture(title: "Still Renders")
      {:ok, _view, html} = live(conn, ~p"/logs?sort=nonsense&keyword=%21%21%21")
      assert html =~ "Still Renders"
    end
  end

  describe "GET /logs/:slug" do
    test "gives a log its own address", %{conn: conn} do
      log_fixture(title: "Ferry To Bowling Green", description: "Notes from the water.")

      {:ok, _view, html} = live(conn, ~p"/logs/ferry-to-bowling-green")

      assert html =~ "Ferry To Bowling Green"
      assert html =~ "Notes from the water."
      assert html =~ "ferry"
    end

    test "an unpublished log 404s instead of leaking", %{conn: conn} do
      log_fixture(title: "Secret Draft", published: false)

      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/logs/secret-draft")
      end
    end

    test "an unknown slug 404s", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn ->
        live(conn, ~p"/logs/there-is-no-such-log")
      end
    end
  end

  describe "legacy paths" do
    test "/audio permanently redirects to /logs" do
      conn = get(build_conn(), "/audio")
      assert redirected_to(conn, 301) == "/logs"
    end

    test "the retired manuscripts audio path redirects to /logs" do
      conn = get(build_conn(), "/manuscripts/latent-sensus/audio/whatever.mp3")
      assert redirected_to(conn, 301) == "/logs"
    end
  end
end
