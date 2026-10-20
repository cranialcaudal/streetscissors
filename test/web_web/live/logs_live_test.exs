defmodule WebWeb.LogsLiveTest do
  use WebWeb.ConnCase

  @this_browser "3f2a9c1e-7b4d-4e8a-9c21-5d6e7f809a1b"
  @someone_else "8c7d6e5f-4a3b-4c2d-9e1f-0a9b8c7d6e5f"

  import Phoenix.LiveViewTest
  import Web.AudioFixtures

  alias Web.Logs
  alias Web.Logs.Log

  defp count(haystack, needle), do: length(String.split(haystack, needle)) - 1

  # A visitor from outside, as Caddy reports one: the machine's own address is
  # excluded from every count (WebWeb.Visitor), plays included.
  setup %{conn: conn} do
    {:ok, conn: Plug.Conn.put_req_header(conn, "x-forwarded-for", "203.0.113.9")}
  end

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
      # The count is of the cards listed under it: the featured entry is in
      # the theater, not among them. (It counted all three until 2026-10-12.)
      assert has_element?(view, ".log-feed-count", "2")
    end

    test "an entry leads to the one before it and the one after, and says which of a day's it is",
         %{conn: conn} do
      older = log_fixture(recorded_on: ~D[2026-09-16])
      middle = log_fixture(recorded_on: ~D[2026-09-17])
      newer = log_fixture(recorded_on: ~D[2026-09-18])

      {:ok, view, _html} = live(conn, "/logs/#{middle.slug}")
      assert has_element?(view, ~s(.log-back a[rel="prev"][href="/logs/#{older.slug}"]))
      assert has_element?(view, ~s(.log-back a[rel="next"][href="/logs/#{newer.slug}"]))

      {:ok, view, _html} = live(conn, "/logs/#{newer.slug}")
      refute has_element?(view, ~s(.log-back a[rel="next"]))
    end

    test "the video's address in the page's structured data is the file's real one", %{conn: conn} do
      log = log_fixture(recorded_on: ~D[2026-09-18])
      html = conn |> get("/logs/#{log.slug}") |> html_response(200)
      assert html =~ "/uploads/logs/#{log.media_dir}/"
      refute html =~ ~s(/uploads/#{log.media_dir}/)
    end

    test "no card mounts a player — the index costs posters and nothing else", %{conn: conn} do
      log_fixture(recorded_on: ~D[2026-09-16])
      log_fixture(recorded_on: ~D[2026-09-17])
      log_fixture(recorded_on: ~D[2026-09-18])

      {:ok, _view, html} = live(conn, "/logs")

      # Three entries, one plate, one media element — the feature's. If a card
      # ever grows a player, opening this page starts fetching video for every
      # entry on it, which is the thing this page exists to avoid.
      assert count(html, ~s(phx-hook="WebWeb.LogEntry.LogPlayer")) == 1
      assert count(html, "<video") == 1
      assert count(html, "<audio") == 0
      # And even that one is told to fetch nothing until it is asked to.
      assert count(html, ~s(preload="none")) == 1
    end

    test "counting a play updates the readout without reordering the page",
         %{conn: conn} do
      quiet = log_fixture(recorded_on: ~D[2026-09-18], caption: "Quiet")
      loud = log_fixture(recorded_on: ~D[2026-09-17], caption: "Loud")
      # Someone other than this browser, so its play is a second view.
      Logs.record_play(loud.id, @someone_else)

      {:ok, view, html} = live(conn, "/logs?sort=viewed")
      assert html =~ ~s(id="log-plate-#{loud.id}")

      # Playing the featured entry must not pull it out of the theater
      # mid-play, which is exactly what re-sorting on every play did.
      render_hook(view, "track_play", %{"id" => to_string(loud.id), "witness" => @this_browser})
      after_play = render(view)

      assert after_play =~ ~s(id="log-plate-#{loud.id}")
      assert Logs.get_play_count(loud.id) == 2
      # The readout still moves, it is only the running order that holds.
      assert after_play =~ ~s(<dd>2</dd>)
      refute after_play =~ ~s(id="log-plate-#{quiet.id}")
    end

    # Watching again straight away is not a second view, and the console adds
    # up the entries on the page.
    test "a replay straight away moves nothing", %{conn: conn} do
      first = log_fixture(recorded_on: ~D[2026-09-18])
      second = log_fixture(recorded_on: ~D[2026-09-17])
      Logs.record_play(second.id, @someone_else)

      {:ok, view, _html} = live(conn, "/logs")

      for _ <- 1..3,
          do:
            render_hook(view, "track_play", %{
              "id" => to_string(first.id),
              "witness" => @this_browser
            })

      render_hook(view, "track_play", %{"id" => to_string(second.id), "witness" => @this_browser})

      assert Logs.get_play_count(first.id) == 1
      assert Logs.get_play_count(second.id) == 2
      # One view of the first and two of the second.
      html = render(view)
      assert html =~ ~r{<dt>Views</dt>\s*<dd>3</dd>}
      # The first leads the page, so only the second is a card.
      assert html =~ "· 2 views<"
    end

    test "the sort lives in the URL so a view can be linked to", %{conn: conn} do
      log_fixture()

      {:ok, view, _html} = live(conn, "/logs")

      view |> element("a", "Most viewed") |> render_click()
      assert_patched(view, "/logs?sort=viewed")
    end

    test "the index offers the feed once, and the running time sits on the featured plate",
         %{conn: conn} do
      log_fixture(recorded_on: ~D[2026-09-17], duration: 61)
      log_fixture(recorded_on: ~D[2026-09-18], duration: 252)

      {:ok, view, html} = live(conn, "/logs")

      # (the layout's own <link rel="alternate"> is a second href, so count
      # the visible links in the page body)
      assert count(html, ~s(href="/feed" class)) == 1
      assert has_element?(view, ~s(.console-bank a[href="/feed"]), "Follow by RSS")
      assert has_element?(view, ".log-plate .log-plate-length", "4:12")
      assert count(html, "log-plate-length") == 1
    end

    test "sorting by most viewed orders on view count", %{conn: conn} do
      quiet = log_fixture(recorded_on: ~D[2026-09-18], caption: "Quiet")
      loud = log_fixture(recorded_on: ~D[2026-09-17], caption: "Loud")

      Logs.record_play(loud.id, @this_browser)
      Logs.record_play(loud.id, @someone_else)
      Logs.record_play(quiet.id, @this_browser)

      # The sort's old name still answers, for links made before the rename.
      {:ok, _view, old} = live(conn, "/logs?sort=witnessed")
      {:ok, _view, html} = live(conn, "/logs?sort=viewed")
      assert old =~ ~s(id="log-plate-#{loud.id}")

      # The most-viewed entry leads, so it is the one in the theater.
      assert html =~ ~s(id="log-plate-#{loud.id}")
    end

    test "filters by keyword, keeping the sort", %{conn: conn} do
      log_fixture(recorded_on: ~D[2026-09-18], keywords: "ferry")
      log_fixture(recorded_on: ~D[2026-09-17], keywords: "bowling-green")

      {:ok, _view, html} = live(conn, "/logs?sort=viewed&keyword=ferry")

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
      # The rail carries a real designation rather than invented numerology.
      assert html =~ "Log 2026-09-18"
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

    test "the plate shows the running time before it plays", %{conn: conn} do
      log = log_fixture(duration: 252)

      {:ok, view, _html} = live(conn, "/logs/#{log.slug}")

      assert has_element?(view, "#log-plate-#{log.id} .log-plate-length", "4:12")
    end

    test "an entry with no known length shows no running time on the plate", %{conn: conn} do
      log = log_fixture(duration: nil)

      {:ok, view, _html} = live(conn, "/logs/#{log.slug}")

      refute has_element?(view, ".log-plate-length")
    end

    test "the page offers the file to keep and the feed to follow", %{conn: conn} do
      log = log_fixture(kind: "video", media_dir: "2026-09-18-abc12345")

      {:ok, view, _html} = live(conn, "/logs/#{log.slug}")

      assert has_element?(
               view,
               ~s(.log-keep a[download][href="/uploads/logs/2026-09-18-abc12345/video.mp4"]),
               "Download"
             )

      assert has_element?(view, ~s(.log-keep a[href="/feed"]), "Follow by RSS")
    end

    test "the player is handed one MP4 but told to preload nothing", %{conn: conn} do
      log = log_fixture(kind: "video", media_dir: "2026-09-18-abc12345")

      {:ok, _view, html} = live(conn, "/logs/#{log.slug}")

      assert html =~ ~s(data-src="/uploads/logs/2026-09-18-abc12345/video.mp4")
      assert html =~ ~s(preload="none")
      refute html =~ "m3u8"
    end

    # The hook owns the plate once it mounts. Without `ignore`, the patch that
    # counts a witness would put the plate's class back and reset the player.
    test "LiveView leaves the plate to the player", %{conn: conn} do
      log = log_fixture(kind: "video", media_dir: "2026-09-18-abc12345")

      {:ok, view, _html} = live(conn, "/logs/#{log.slug}")

      assert has_element?(view, ~s(#log-plate-#{log.id}[phx-update="ignore"][phx-hook]))
    end

    # A failure says so, with a way to try again and a way round the player.
    test "the plate carries a hidden failure panel with a retry and the file", %{conn: conn} do
      log = log_fixture(kind: "video", media_dir: "2026-09-18-abc12345")

      {:ok, view, _html} = live(conn, "/logs/#{log.slug}")

      assert has_element?(view, ".log-plate-error[hidden][role=alert]")
      assert has_element?(view, ".log-plate-error button.log-retry", "Try again")

      assert has_element?(
               view,
               ~s(.log-plate-error a.log-file[href="/uploads/logs/2026-09-18-abc12345/video.mp4"]),
               "Open the file"
             )
    end

    test "the media element carries no hidden attribute", %{conn: conn} do
      log = log_fixture(kind: "video", media_dir: "2026-09-18-abc12345")

      {:ok, _view, html} = live(conn, "/logs/#{log.slug}")

      # This is the whole bug, and it is worth pinning. LiveView patches back
      # every attribute it rendered, and counting a play *is* a render — so a
      # `hidden` here was restored the instant playback began, dropping the
      # poster and the play key back over a video that was already running.
      # An audio entry's poster is its waveform, so that looked like pressing
      # play and getting a flat orange screen. Visibility is CSS now.
      refute html =~ ~r/<video[^>]*\shidden/
      refute html =~ ~r/<audio[^>]*\shidden/
    end

    test "keywords link back to the filtered index", %{conn: conn} do
      log = log_fixture(keywords: "ferry")

      {:ok, view, _html} = live(conn, "/logs/#{log.slug}")

      assert has_element?(view, ~s(a[href="/logs?keyword=ferry"]), "ferry")
    end

    test "emits AudioObject and BreadcrumbList structured data", %{conn: conn} do
      log = log_fixture(kind: "audio", caption: "Test log entry")

      {:ok, _view, html} = live(conn, "/logs/#{log.slug}")

      assert html =~ ~s("@type":"AudioObject")
      assert html =~ ~s("@type":"BreadcrumbList")
      assert html =~ ~s("name":"Captain's Log")
    end

    test "a play is counted against the mounted log whatever the client claims", %{conn: conn} do
      log = log_fixture()
      other = log_fixture(recorded_on: ~D[2026-01-01])

      {:ok, view, _html} = live(conn, "/logs/#{log.slug}")
      render_hook(view, "track_play", %{"id" => to_string(other.id), "witness" => @this_browser})

      assert Logs.get_play_count(log.id) == 1
      assert Logs.get_play_count(other.id) == 0
    end

    test "the admin watching an entry back is not a view", %{conn: conn} do
      log = log_fixture()
      conn = Plug.Test.init_test_session(conn, admin_user: true)

      {:ok, view, _html} = live(conn, "/logs/#{log.slug}")
      render_hook(view, "track_play", %{"id" => to_string(log.id), "witness" => @this_browser})

      {:ok, index, _html} = live(conn, "/logs")
      render_hook(index, "track_play", %{"id" => to_string(log.id), "witness" => @this_browser})

      assert Logs.get_play_count(log.id) == 0
    end

    test "a play with no witness token is not counted", %{conn: conn} do
      log = log_fixture()

      {:ok, view, _html} = live(conn, "/logs/#{log.slug}")
      render_hook(view, "track_play", %{"id" => to_string(log.id)})

      assert Logs.get_play_count(log.id) == 0
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
