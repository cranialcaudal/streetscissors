defmodule WebWeb.RidesLiveTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest
  import Web.RidesFixtures

  alias Web.Rides
  alias Web.Rides.Privacy

  # An invented street: due north from the "house" at 45.0, 7.0, a point
  # every ~22 m for ~2.2 km, altitude climbing with it.
  @house {45.0, 7.0}
  @track for i <- 0..100, do: {45.0 + i * 0.0002, 7.0, 300.0 + i, i * 5_000}

  defp tracked_ride(attrs \\ %{}) do
    ride = ride_fixture(attrs)
    {:ok, ride} = Rides.store_track(ride, @track)
    ride
  end

  defp with_zone(_context) do
    Application.put_env(:web, :ride_privacy_zones, "45.0,7.0,400")
    on_exit(fn -> Application.delete_env(:web, :ride_privacy_zones) end)
  end

  # Every coordinate pair the plate hands to the browser.
  defp published_points(view, ride) do
    view
    |> element("#route-#{ride.id}")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.attribute("data-route")
    |> hd()
    |> Jason.decode!()
    |> Map.fetch!("segments")
    |> Enum.concat()
    |> Enum.map(fn [lng, lat | _] -> {lat, lng} end)
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

  test "the featured activity is drawn by the site: map, profile, figures and outline", %{
    conn: conn
  } do
    ride = tracked_ride()

    {:ok, view, html} = live(conn, ~p"/fitness/rides")

    assert has_element?(view, ".activity-feature #route-#{ride.id}[phx-hook='RouteMap']")
    assert has_element?(view, ".activity-feature .activity-profile path.activity-profile-line")
    assert has_element?(view, ".activity-feature .activity-figures")
    assert has_element?(view, ".activity-card svg.activity-card-route path")

    # With no zone set the whole track is published, both ends marked.
    points = published_points(view, ride)
    assert List.first(points) == @house
    assert length(points) == 101

    # Nothing of Komoot's is shown or linked: it would show the route whole.
    refute html =~ "komoot.com"
    refute html =~ "<iframe"
  end

  describe "with a privacy zone" do
    setup :with_zone

    test "no point within the zone's radius reaches either page", %{conn: conn} do
      ride = tracked_ride()

      for path <- [~p"/fitness/rides", ~p"/fitness/rides/#{ride.id}"] do
        {:ok, view, html} = live(conn, path)
        points = published_points(view, ride)

        assert points != []
        assert Enum.all?(points, &(Privacy.distance_m(&1, @house) > 400))

        # The route's far end is still its finish; its near end is a cut.
        assert List.last(points) == {45.02, 7.0}
        assert html =~ ~s(&quot;start&quot;:false)
        assert html =~ ~s(&quot;finish&quot;:true)
      end
    end

    test "a ride that never leaves the zone shows its figures and no route", %{conn: conn} do
      ride = ride_fixture()
      {:ok, ride} = Rides.store_track(ride, Enum.take(@track, 10))

      {:ok, view, _html} = live(conn, ~p"/fitness/rides/#{ride.id}")
      refute has_element?(view, "[phx-hook='RouteMap']")
      assert has_element?(view, ".activity-map--blank")
      assert has_element?(view, ".activity-figures")

      {:ok, index, _html} = live(conn, ~p"/fitness/rides")
      refute has_element?(index, ".activity-card svg")
    end

    test "an outline cut by other zones is not shown", %{conn: conn} do
      tracked_ride()
      Application.put_env(:web, :ride_privacy_zones, "45.0,7.0,900")

      {:ok, view, _html} = live(conn, ~p"/fitness/rides")
      refute has_element?(view, ".activity-card svg")
    end

    test "a zone setting that can't be read hides every route", %{conn: conn} do
      ride = tracked_ride()
      Application.put_env(:web, :ride_privacy_zones, "45.0;7.0,400")

      ExUnit.CaptureLog.capture_log(fn ->
        {:ok, view, _html} = live(conn, ~p"/fitness/rides/#{ride.id}")
        refute has_element?(view, "[phx-hook='RouteMap']")
      end)
    end
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

  test "show draws the route and links nowhere on Komoot, private tour or public", %{conn: conn} do
    for visibility <- ~w(public private) do
      ride = tracked_ride(%{name: "Lakes loop", visibility: visibility})

      {:ok, view, html} = live(conn, ~p"/fitness/rides/#{ride.id}")
      assert html =~ "Lakes loop"
      assert has_element?(view, "#route-#{ride.id} [data-role='map']")
      assert has_element?(view, ".activity-figure-label", "Downhill")
      refute html =~ "komoot.com"
    end
  end

  test "a ride whose track hasn't synced yet shows its figures over a blank plate", %{conn: conn} do
    ride = ride_fixture()

    {:ok, view, _html} = live(conn, ~p"/fitness/rides/#{ride.id}")
    assert has_element?(view, ".activity-map--blank")
    assert has_element?(view, ".activity-figures")
  end

  test "the old thumbnail address is gone", %{conn: conn} do
    ride = ride_fixture()
    assert response(get(conn, "/fitness/rides/#{ride.id}/thumb"), 404)
  end

  test "an unknown ride 404s", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/fitness/rides/999999") end
  end
end
