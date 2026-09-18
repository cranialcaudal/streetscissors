defmodule WebWeb.LogsLiveTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest
  import Web.AudioFixtures

  alias Web.Audio
  alias Web.Audio.Log

  defp count(haystack, needle), do: length(String.split(haystack, needle)) - 1

  describe "the index" do
    test "titles entries by their date and hides drafts", %{conn: conn} do
      log_fixture(recorded_on: ~D[2026-09-18], caption: "Under way")
      log_fixture(recorded_on: ~D[2026-09-17], published: false)

      {:ok, _view, html} = live(conn, "/logs")

      assert html =~ "Friday, 18 September 2026"
      assert html =~ "Under way"
      refute html =~ "Thursday, 17 September 2026"
    end

    test "an entry still transcoding stays off the page until it is playable", %{conn: conn} do
      log_fixture(recorded_on: ~D[2026-09-18], published: true, status: "ready")
      log_fixture(recorded_on: ~D[2026-09-19], published: true, status: "pending")

      {:ok, _view, html} = live(conn, "/logs")

      assert html =~ "Friday, 18 September 2026"
      refute html =~ "Saturday, 19 September 2026"
    end

    test "two entries the same day are told apart by their ordinal", %{conn: conn} do
      log_fixture(recorded_on: ~D[2026-09-18])
      log_fixture(recorded_on: ~D[2026-09-18])

      {:ok, _view, html} = live(conn, "/logs")

      assert html =~ "Entry 02"
    end

    test "the newest entry in view is featured, and keeps its place in the run below",
         %{conn: conn} do
      log_fixture(recorded_on: ~D[2026-09-16])
      log_fixture(recorded_on: ~D[2026-09-17])
      newest = log_fixture(recorded_on: ~D[2026-09-18])

      {:ok, view, html} = live(conn, "/logs")

      # Featured: the only plate on the page.
      assert html =~ ~s(id="log-plate-#{newest.id}")
      # The count in the readout accounts for every entry, featured included.
      assert has_element?(view, ".log-feed-count", "3")
    end

    test "no card mounts a player — the index costs posters and nothing else", %{conn: conn} do
      log_fixture(recorded_on: ~D[2026-09-16])
      log_fixture(recorded_on: ~D[2026-09-17])
      log_fixture(recorded_on: ~D[2026-09-18])

      {:ok, _view, html} = live(conn, "/logs")

      # Three entries, one plate, one media element — the feature's. If a card
      # ever grows a player, opening this page starts fetching video for every
      # entry on it, which is the thing this page exists to avoid.
      assert count(html, ~s(class="log-plate)) == 1
      assert count(html, "<video") == 1
      assert count(html, "<audio") == 0
      # And even that one is told to fetch nothing until it is asked to.
      assert count(html, ~s(preload="none")) == 1
    end

    test "the sort lives in the URL so a view can be linked to", %{conn: conn} do
      log_fixture()

      {:ok, view, _html} = live(conn, "/logs")

      view |> element("a", "Most witnessed") |> render_click()
      assert_patched(view, "/logs?sort=witnessed")
    end

    test "sorting by most witnessed orders on play count", %{conn: conn} do
      quiet = log_fixture(recorded_on: ~D[2026-09-18], caption: "Quiet")
      loud = log_fixture(recorded_on: ~D[2026-09-17], caption: "Loud")

      Audio.record_play(loud.id, "127.0.0.1")
      Audio.record_play(loud.id, "127.0.0.2")
      Audio.record_play(quiet.id, "127.0.0.3")

      {:ok, _view, html} = live(conn, "/logs?sort=witnessed")

      # The most-witnessed entry leads, so it is the one in the theater.
      assert html =~ ~s(id="log-plate-#{loud.id}")
    end

    test "filters by keyword, keeping the sort", %{conn: conn} do
      log_fixture(recorded_on: ~D[2026-09-18], keywords: "ferry")
      log_fixture(recorded_on: ~D[2026-09-17], keywords: "bowling-green")

      {:ok, _view, html} = live(conn, "/logs?sort=witnessed&keyword=ferry")

      assert html =~ "Friday, 18 September 2026"
      refute html =~ "Thursday, 17 September 2026"
    end

    test "a keyword nothing is filed under renders an empty state", %{conn: conn} do
      log_fixture(keywords: "ferry")

      {:ok, _view, html} = live(conn, "/logs?keyword=nothing-here")

      assert html =~ "Nothing filed under"
    end

    test "a hand-mangled sort falls back rather than crashing", %{conn: conn} do
      log_fixture()
      assert {:ok, _view, _html} = live(conn, "/logs?sort=sideways")
    end

    test "the years are a footnote", %{conn: conn} do
      log_fixture(
        recorded_on: ~D[2026-09-18],
        recorded_at: ~U[2026-09-18 20:00:00Z],
        duration: 3720
      )

      {:ok, _view, html} = live(conn, "/logs")

      assert html =~ "2026 · 1 entry · 1h 2m"
    end
  end

  describe "a log's own page" do
    test "gives an entry its own address, titled by its date", %{conn: conn} do
      log = log_fixture(recorded_on: ~D[2026-09-18], description: "What happened.")

      {:ok, _view, html} = live(conn, "/logs/#{log.slug}")

      assert html =~ "Friday, 18 September 2026"
      assert html =~ "What happened."
      assert html =~ log.stardate
    end

    test "the second entry of a day has an address of its own", %{conn: conn} do
      log_fixture(recorded_on: ~D[2026-09-18])
      second = log_fixture(recorded_on: ~D[2026-09-18])

      {:ok, _view, html} = live(conn, "/logs/2026-09-18-2")

      assert second.slug == "2026-09-18-2"
      assert html =~ "Entry 02"
    end

    test "an unpublished log 404s instead of leaking", %{conn: conn} do
      log = log_fixture(published: false)

      assert_raise Ecto.NoResultsError, fn -> live(conn, "/logs/#{log.slug}") end
    end

    test "an entry still transcoding 404s rather than showing a half-built page", %{conn: conn} do
      log = log_fixture(published: true, status: "processing")

      assert_raise Ecto.NoResultsError, fn -> live(conn, "/logs/#{log.slug}") end
    end

    test "an unknown slug 404s", %{conn: conn} do
      assert_raise Ecto.NoResultsError, fn -> live(conn, "/logs/2026-01-01") end
    end

    test "the player is handed the playlist but told to preload nothing", %{conn: conn} do
      log = log_fixture(kind: "video", media_dir: "2026-09-18-abc12345")

      {:ok, _view, html} = live(conn, "/logs/#{log.slug}")

      assert html =~ "/uploads/logs/2026-09-18-abc12345/master.m3u8"
      assert html =~ ~s(preload="none")
    end

    test "keywords link back to the filtered index", %{conn: conn} do
      log = log_fixture(keywords: "ferry")

      {:ok, view, _html} = live(conn, "/logs/#{log.slug}")

      assert has_element?(view, ~s(a[href="/logs?keyword=ferry"]), "ferry")
    end

    test "a play is counted against the mounted log whatever the client claims", %{conn: conn} do
      log = log_fixture()
      other = log_fixture(recorded_on: ~D[2026-01-01])

      {:ok, view, _html} = live(conn, "/logs/#{log.slug}")
      render_hook(view, "track_play", %{"id" => to_string(other.id)})

      assert Audio.get_play_count(log.id) == 1
      assert Audio.get_play_count(other.id) == 0
    end
  end

  describe "legacy addresses" do
    test "/audio permanently redirects to /logs" do
      conn = get(build_conn(), "/audio")
      assert redirected_to(conn, 301) == "/logs"
    end

    test "the retired manuscripts audio path redirects to /logs" do
      conn = get(build_conn(), "/manuscripts/essays/audio/whatever.mp3")
      assert redirected_to(conn, 301) == "/logs"
    end
  end

  describe "the shared display helpers" do
    test "a runtime reads as hours and minutes" do
      assert WebWeb.LogsLive.Format.format_runtime(22_320) == "6h 12m"
      assert WebWeb.LogsLive.Format.format_runtime(252) == "4m"
      assert WebWeb.LogsLive.Format.format_runtime(nil) == "—"
    end

    test "a title falls back rather than rendering blank" do
      assert Log.title(%Log{recorded_on: nil}) == "Undated log"
    end
  end
end
