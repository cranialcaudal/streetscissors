defmodule WebWeb.RidesLiveTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest
  import Web.RidesFixtures

  alias Web.Rides.Thumbs

  setup do
    File.rm_rf!(Thumbs.dir())
    :ok
  end

  test "old ride paths redirect to /fitness/rides", %{conn: conn} do
    assert redirected_to(get(conn, "/rides"), 301) == "/fitness/rides"
    assert redirected_to(get(conn, "/rides/123"), 301) == "/fitness/rides/123"

    # The live page is gone; links to it land on the archive.
    assert redirected_to(get(conn, "/fitness/rides/live"), 301) == "/fitness/rides"
    assert redirected_to(get(conn, "/live"), 302) == "/fitness/rides"
  end

  test "index shows the empty state when nothing is synced", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/fitness/rides")
    assert html =~ "Nothing synced yet"
  end

  test "the newest activity is featured above one shelf per sport, biggest first", %{conn: conn} do
    ride_fixture(%{name: "Lakes loop", sport: "racebike", started_at: ~U[2026-07-01 16:00:00Z]})
    ride_fixture(%{name: "Long road", sport: "racebike", started_at: ~U[2026-07-03 16:00:00Z]})

    ride_fixture(%{
      name: "Home loop",
      sport: "jogging",
      visibility: "private",
      started_at: ~U[2026-07-08 16:00:00Z]
    })

    {:ok, view, html} = live(conn, ~p"/fitness/rides")
    assert has_element?(view, "h1.blog-header-title", "Activities")
    assert has_element?(view, ".activity-feature", "Home loop")

    # Road cycling has two, so its shelf leads even though the run is newer.
    assert :binary.match(html, ~s(id="shelf-racebike")) <
             :binary.match(html, ~s(id="shelf-jogging"))

    assert has_element?(view, "#shelf-racebike .activity-shelf-count", "2")
    assert has_element?(view, "#shelf-racebike.activity-shelf--strip[phx-hook]")

    # The featured run is on its own shelf too, so every count matches its cards.
    assert has_element?(view, "#shelf-jogging .activity-card", "Home loop")
  end

  test "pills count each sport and filter the page, totals included", %{conn: conn} do
    ride_fixture(%{name: "Road day", sport: "racebike", started_at: ~U[2026-07-09 16:00:00Z]})

    ride_fixture(%{
      name: "Old run",
      sport: "jogging",
      distance_m: 5_000.0,
      started_at: ~U[2026-07-01 16:00:00Z]
    })

    ride_fixture(%{
      name: "New run",
      sport: "jogging",
      distance_m: 5_000.0,
      started_at: ~U[2026-07-05 16:00:00Z]
    })

    {:ok, view, _html} = live(conn, ~p"/fitness/rides")
    assert has_element?(view, "a.activity-pill.is-active", "All")
    assert has_element?(view, "a.activity-pill.is-active .activity-pill-count", "3")
    assert has_element?(view, "a.activity-pill[href='/fitness/rides?sport=jogging']", "Running")

    view |> element("a.activity-pill[href='/fitness/rides?sport=jogging']") |> render_click()
    assert_patch(view, ~p"/fitness/rides?sport=jogging")

    assert has_element?(view, "a.activity-pill.is-active", "Running")
    assert has_element?(view, ".activity-feature", "New run")
    assert has_element?(view, "#shelf-jogging.activity-shelf--grid")
    refute has_element?(view, "#shelf-racebike")
    refute has_element?(view, ".activity-card", "Road day")
    assert has_element?(view, ".activity-totals p", "2026 · 2 activities · 6.2 mi")
  end

  test "an unknown sport in the URL falls back to All", %{conn: conn} do
    ride_fixture(%{sport: "racebike"})

    {:ok, view, _html} = live(conn, ~p"/fitness/rides?sport=curling")
    assert has_element?(view, "a.activity-pill.is-active", "All")
    assert has_element?(view, "#shelf-racebike.activity-shelf--strip")
  end

  test "activities under 0.2 mi appear nowhere and have no page", %{conn: conn} do
    ride_fixture(%{name: "Real ride"})
    short = ride_fixture(%{name: "Pocket ride", distance_m: 160.0})

    {:ok, view, html} = live(conn, ~p"/fitness/rides")
    refute html =~ "Pocket ride"
    assert has_element?(view, "a.activity-pill.is-active .activity-pill-count", "1")
    assert has_element?(view, ".activity-totals p", "1 activity")

    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/fitness/rides/#{short.id}") end
  end

  test "sports and days read the way Komoot records them", %{conn: conn} do
    # 00:05 UTC on the 12th was the evening of Friday the 11th in California.
    ride_fixture(%{sport: "touringbicycle", started_at: ~U[2026-09-12 00:05:26Z]})

    {:ok, view, _html} = live(conn, ~p"/fitness/rides")
    assert has_element?(view, ".activity-feature .activity-meta", "Bike touring")
    assert has_element?(view, ".activity-feature .activity-meta", "Fri 11 Sep 2026")
    assert has_element?(view, ".activity-card-stats", "2,625 ft up")
  end

  test "the featured activity is Komoot's embed; the cards keep Komoot's map", %{conn: conn} do
    ride = ride_fixture(%{komoot_id: "987654321"})
    :ok = Thumbs.store(ride, "fake-jpeg")

    {:ok, view, _html} = live(conn, ~p"/fitness/rides")

    assert has_element?(
             view,
             ".activity-feature iframe.activity-embed[src='https://www.komoot.com/tour/987654321/embed?profile=1']"
           )

    # Komoot's embed carries its own stats, so the page doesn't repeat them…
    refute has_element?(view, ".activity-feature .activity-figures")
    refute has_element?(view, ".activity-feature img.activity-map")
    # …and the shelf still shows the route, at full colour.
    assert has_element?(view, ".activity-card img[src='/fitness/rides/#{ride.id}/thumb']")
  end

  test "a private tour is embedded through its share token", %{conn: conn} do
    ride = ride_fixture(%{komoot_id: "555", visibility: "private", share_token: "tok"})

    {:ok, index, _html} = live(conn, ~p"/fitness/rides")

    assert has_element?(
             index,
             ".activity-feature iframe[src='https://www.komoot.com/tour/555/embed?share_token=tok&profile=1']"
           )

    {:ok, show, _html} = live(conn, ~p"/fitness/rides/#{ride.id}")
    assert has_element?(show, "iframe.activity-embed[src*='share_token=tok']")

    assert has_element?(
             show,
             "a.activity-komoot[href='https://www.komoot.com/tour/555?share_token=tok']"
           )
  end

  test "heart and energy come from the Apple Health workout paired with a ride", %{conn: conn} do
    ride = ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})
    workout_fixture(%{started_at: ~U[2026-07-08 18:00:20Z], avg_hr: 142, max_hr: 171})

    {:ok, index, _html} = live(conn, ~p"/fitness/rides")
    assert has_element?(index, ".activity-feature .activity-health", "Apple Health")
    assert has_element?(index, ".activity-feature .activity-figure-value", "142 bpm")
    assert has_element?(index, ".activity-card-health", "142 bpm · 612 kcal")
    # The trace belongs to the ride's own page.
    refute has_element?(index, ".heart-trace")

    {:ok, show, _html} = live(conn, ~p"/fitness/rides/#{ride.id}")
    assert has_element?(show, ".activity-figure-label", "Max heart rate")
    assert has_element?(show, ".activity-figure-value", "171 bpm")
    assert has_element?(show, "#heart-trace-#{ride.id}[phx-hook] svg path.heart-trace-line")
    assert has_element?(show, ".heart-trace-caption", "96–171 bpm")
  end

  test "a ride with no paired workout shows no health panel", %{conn: conn} do
    ride = ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})
    workout_fixture(%{started_at: ~U[2026-07-08 18:30:00Z]})

    {:ok, index, _html} = live(conn, ~p"/fitness/rides")
    refute has_element?(index, ".activity-health")
    refute has_element?(index, ".activity-card-health")

    {:ok, show, _html} = live(conn, ~p"/fitness/rides/#{ride.id}")
    refute has_element?(show, ".activity-health")
  end

  test "the year's mileage is one quiet line per year, below everything", %{conn: conn} do
    ride_fixture(%{started_at: ~U[2026-06-01 16:00:00Z], distance_m: 16_093.44, ascent_m: 100.0})
    ride_fixture(%{started_at: ~U[2025-06-01 16:00:00Z], distance_m: 8046.72, ascent_m: 100.0})

    {:ok, view, html} = live(conn, ~p"/fitness/rides")
    assert has_element?(view, ".activity-totals p", "2026 · 1 activity · 10.0 mi · 328 ft up")
    assert has_element?(view, ".activity-totals p", "2025 · 1 activity · 5.0 mi")
    assert :binary.match(html, "activity-feature") < :binary.match(html, "activity-totals")
  end

  test "index includes the fitness sub-nav", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/fitness/rides")
    assert html =~ "bento-fitness-sub-row"
    assert html =~ "/fitness/wiki"
  end

  test "fitness pages link to rides in the sub-nav", %{conn: conn} do
    for path <- ["/fitness", "/fitness/wiki"] do
      {:ok, _view, html} = live(conn, path)
      assert html =~ "/fitness/rides", "expected #{path} to link to /fitness/rides"
    end
  end

  test "show embeds Komoot's own map for a public tour", %{conn: conn} do
    ride = ride_fixture(%{name: "Lakes loop", komoot_id: "987654321"})

    {:ok, view, html} = live(conn, ~p"/fitness/rides/#{ride.id}")
    assert html =~ "Lakes loop"
    assert html =~ "https://www.komoot.com/tour/987654321/embed?profile=1"
    refute has_element?(view, ".activity-figures")
    assert has_element?(view, "a.activity-komoot[href='https://www.komoot.com/tour/987654321']")
  end

  test "show falls back to the cached route image for a private tour with no share token yet",
       %{conn: conn} do
    ride = ride_fixture(%{visibility: "private"})
    :ok = Thumbs.store(ride, "fake-jpeg")

    {:ok, view, html} = live(conn, ~p"/fitness/rides/#{ride.id}")
    assert html =~ ~s(src="/fitness/rides/#{ride.id}/thumb")
    assert has_element?(view, ".activity-figure-label", "Downhill")
    refute html =~ "komoot.com/tour/"
    refute has_element?(view, "a.activity-komoot")
  end

  test "thumbnails are served for every ride", %{conn: conn} do
    ride = ride_fixture(%{visibility: "private"})
    :ok = Thumbs.store(ride, "fake-jpeg")

    assert response(get(conn, ~p"/fitness/rides/#{ride.id}/thumb"), 200) == "fake-jpeg"
    assert response(get(conn, "/fitness/rides/abc/thumb"), 404)
  end

  test "an unknown ride 404s", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/fitness/rides/999999") end
  end
end
