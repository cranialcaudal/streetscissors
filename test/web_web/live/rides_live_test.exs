defmodule WebWeb.RidesLiveTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest
  import Web.RidesFixtures

  alias Web.Rides.Thumbs

  @map "https://cdn.example/maps/route.jpg"

  setup do
    File.rm_rf!(Thumbs.dir())
    :ok
  end

  # The figures in one panel, as `%{"Avg heart rate" => "142 bpm", …}`.
  defp figures(view, selector) do
    panel = view |> element(selector) |> render() |> LazyHTML.from_fragment()

    read = fn class ->
      panel |> LazyHTML.query(class) |> Enum.map(&String.trim(LazyHTML.text(&1)))
    end

    Map.new(Enum.zip(read.(".activity-figure-label"), read.(".activity-figure-value")))
  end

  test "old ride paths redirect to /fitness/rides", %{conn: conn} do
    assert redirected_to(get(conn, "/rides"), 301) == "/fitness/rides"
    assert redirected_to(get(conn, "/rides/123"), 301) == "/fitness/rides/123"

    # The live page is gone; links to it land on the archive.
    assert redirected_to(get(conn, "/fitness/rides/live"), 301) == "/fitness/rides"
    assert redirected_to(get(conn, "/live"), 302) == "/fitness/rides"
  end

  test "index shows the empty state when nothing is synced", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/fitness/rides")
    assert html =~ "Nothing synced yet"
    refute has_element?(view, ".activity-recent")
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

    assert has_element?(
             view,
             ".activity-totals p",
             "2026 · 2 activities · 3h 20m moving · 6.2 mi"
           )
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

  describe "what Komoot draws" do
    test "the featured activity is Komoot's embed, with its profile and photographs", %{
      conn: conn
    } do
      ride = ride_fixture(%{komoot_id: "987654321", map_image_url: @map})
      :ok = Thumbs.store(ride, "fake-jpeg")

      {:ok, view, _html} = live(conn, ~p"/fitness/rides")

      assert has_element?(
               view,
               ".activity-feature iframe#komoot-embed-#{ride.id}.activity-embed" <>
                 "[src='https://www.komoot.com/tour/987654321/embed?profile=1&gallery=1']"
             )

      # Komoot's embed carries its own stats, so the page doesn't repeat them…
      refute has_element?(view, ".activity-feature .activity-figures")
      refute has_element?(view, ".activity-feature img.activity-map")

      # …and the shelf shows Komoot's picture of the route, at the address
      # that names the map it was drawn from.
      assert has_element?(
               view,
               ".activity-card img[src='/fitness/rides/#{ride.id}/thumb?v=#{Thumbs.fingerprint(@map)}']"
             )
    end

    test "a private tour is embedded through its share token", %{conn: conn} do
      ride = ride_fixture(%{komoot_id: "555", visibility: "private", share_token: "tok"})

      {:ok, index, _html} = live(conn, ~p"/fitness/rides")

      assert has_element?(
               index,
               ".activity-feature iframe" <>
                 "[src='https://www.komoot.com/tour/555/embed?share_token=tok&profile=1&gallery=1']"
             )

      {:ok, show, _html} = live(conn, ~p"/fitness/rides/#{ride.id}")
      assert has_element?(show, "iframe.activity-embed[src*='share_token=tok']")

      assert has_element?(
               show,
               "a.activity-komoot[href='https://www.komoot.com/tour/555?share_token=tok']"
             )
    end

    test "show embeds Komoot's own map for a public tour, and links to it", %{conn: conn} do
      ride = ride_fixture(%{name: "Lakes loop", komoot_id: "987654321"})

      {:ok, view, html} = live(conn, ~p"/fitness/rides/#{ride.id}")
      assert html =~ "Lakes loop"

      assert has_element?(
               view,
               "iframe.activity-embed[src='https://www.komoot.com/tour/987654321/embed?profile=1&gallery=1']"
             )

      refute has_element?(view, ".activity-figures")
      assert has_element?(view, "a.activity-komoot[href='https://www.komoot.com/tour/987654321']")
    end

    test "a private tour with no share link yet falls back to the cached picture and our figures",
         %{conn: conn} do
      ride = ride_fixture(%{visibility: "private", map_image_url: @map})
      :ok = Thumbs.store(ride, "fake-jpeg")

      {:ok, view, html} = live(conn, ~p"/fitness/rides/#{ride.id}")
      assert has_element?(view, "img.activity-map[src^='/fitness/rides/#{ride.id}/thumb?v=']")
      assert has_element?(view, ".activity-figure-label", "Downhill")
      refute html =~ "komoot.com"
      refute has_element?(view, "a.activity-komoot")
    end

    # Only a tour the sync has read as a stranger and found clear is shown
    # through Komoot. One the tripwire found exposed (`Web.Rides.Privacy`),
    # one that passes home mid-tour, one Komoot hides from strangers
    # altogether, and one not looked at yet keep their figures and lose
    # everything Komoot would draw, whatever is on disk and whatever token
    # they hold.
    for {view, label} <- [
          {"exposed", "exposed"},
          {"passing", "passing home"},
          {"hidden", "hidden"},
          {nil, "unchecked"}
        ] do
      test "a tour that is #{label} shows its figures and nothing of Komoot's", %{conn: conn} do
        ride =
          ride_fixture(%{
            komoot_id: "777",
            visibility: "private",
            share_token: "sharetoken9f3",
            map_image_url: @map,
            stranger_view: unquote(view)
          })

        :ok = Thumbs.store(ride, "fake-jpeg")

        for path <- [~p"/fitness/rides", ~p"/fitness/rides/#{ride.id}"] do
          {:ok, view, html} = live(conn, path)

          refute html =~ "komoot.com"
          refute html =~ "<iframe"
          refute html =~ "/thumb"
          refute html =~ "sharetoken9f3"
          assert has_element?(view, ".activity-feature .activity-map--blank")
          assert has_element?(view, ".activity-feature .activity-figures")
        end

        assert response(get(conn, ~p"/fitness/rides/#{ride.id}/thumb"), 404)
      end
    end

    test "a public tour is held back the same way until it has been looked at", %{conn: conn} do
      ride = ride_fixture(%{komoot_id: "888", visibility: "public", stranger_view: nil})

      {:ok, view, html} = live(conn, ~p"/fitness/rides/#{ride.id}")
      refute html =~ "komoot.com"
      refute has_element?(view, "iframe")
      refute has_element?(view, "a.activity-komoot")
      assert has_element?(view, ".activity-figures")
    end
  end

  describe "the cached picture" do
    test "is served for a ride that has one, public or private", %{conn: conn} do
      ride = ride_fixture(%{visibility: "private", map_image_url: @map})
      :ok = Thumbs.store(ride, "fake-jpeg")

      conn = get(conn, ~p"/fitness/rides/#{ride.id}/thumb")
      assert response(conn, 200) == "fake-jpeg"
      assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    end

    test "is a 404 for a ride with none, and for no ride at all", %{conn: conn} do
      ride = ride_fixture(%{map_image_url: @map})

      assert response(get(conn, ~p"/fitness/rides/#{ride.id}/thumb"), 404)
      assert response(get(conn, "/fitness/rides/abc/thumb"), 404)
      assert response(get(conn, "/fitness/rides/999999/thumb"), 404)
    end

    # An earlier version of the site kept the owner's view of each route —
    # the whole of it, front door included — under the bare ride id. A file
    # by that name, or one drawn from any map but the current one, is not
    # this ride's picture.
    test "is never a file kept under another name", %{conn: conn} do
      ride = ride_fixture(%{map_image_url: @map})
      File.mkdir_p!(Thumbs.dir())
      File.write!(Path.join(Thumbs.dir(), "#{ride.id}.jpg"), "the whole route")

      File.write!(
        Path.join(
          Thumbs.dir(),
          "#{ride.id}-#{Thumbs.fingerprint("https://cdn.example/old.jpg")}.jpg"
        ),
        "an earlier cut"
      )

      assert response(get(conn, ~p"/fitness/rides/#{ride.id}/thumb"), 404)

      {:ok, view, _html} = live(conn, ~p"/fitness/rides")
      refute has_element?(view, ".activity-card img")

      # And a ride Komoot gave no map for has no picture whatever is on disk.
      mapless = ride_fixture()
      File.write!(Path.join(Thumbs.dir(), "#{mapless.id}.jpg"), "the whole route")
      assert response(get(conn, ~p"/fitness/rides/#{mapless.id}/thumb"), 404)
    end
  end

  describe "what the watch measured" do
    test "heart rate and energy lead the featured activity and mark its card", %{conn: conn} do
      ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})
      workout_fixture(%{started_at: ~U[2026-07-08 18:00:20Z], avg_hr: 142, max_hr: 171})

      {:ok, view, html} = live(conn, ~p"/fitness/rides")

      assert has_element?(view, ".activity-feature .activity-health-title", "Heart & energy")
      assert has_element?(view, ".activity-feature .activity-health-source", "Apple Health")

      assert figures(view, ".activity-feature .activity-health") == %{
               "Avg heart rate" => "142 bpm",
               "Max heart rate" => "171 bpm",
               "Active energy" => "612 kcal"
             }

      # What the body did comes before the map.
      assert :binary.match(html, "activity-health") < :binary.match(html, "activity-embed")

      assert has_element?(view, ".activity-card-health", "142 bpm · 612 kcal")
      # The zones and the trace belong to the ride's own page.
      refute has_element?(view, ".heart-trace")
      refute has_element?(view, ".heart-zones")
    end

    test "a ride's own page adds the lowest, the time in each zone and the trace", %{conn: conn} do
      ride = ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})

      # 0:00 at 96, 10:00 at 128, 20:00 at 150, 30:00 at 171, 40:00 at 140.
      workout_fixture(%{
        started_at: ~U[2026-07-08 18:00:20Z],
        avg_hr: 142,
        max_hr: 171,
        min_hr: 88
      })

      {:ok, view, _html} = live(conn, ~p"/fitness/rides/#{ride.id}")

      assert figures(view, ".activity-health") == %{
               "Avg heart rate" => "142 bpm",
               "Max heart rate" => "171 bpm",
               "Lowest" => "88 bpm",
               "Active energy" => "612 kcal"
             }

      # Zones are shares of the highest heart rate on file, 171 here: they
      # start at 86, 103, 120, 137 and 154. Ten minutes went to each of four.
      assert has_element?(view, ".heart-zones .heart-trace-caption", "shares of 171 bpm")

      zones =
        view
        |> element(".heart-zones-list")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("li")
        |> Enum.map(fn zone ->
          zone |> LazyHTML.query("span") |> Enum.map_join(" ", &LazyHTML.text/1) |> String.trim()
        end)

      assert zones == [
               "Easy 86+ bpm 10:00",
               "Steady 103+ bpm 0:00",
               "Tempo 120+ bpm 10:00",
               "Hard 137+ bpm 10:00",
               "All out 154+ bpm 10:00"
             ]

      # A zone no time was spent in takes no room on the bar.
      assert view |> element(".heart-zones-bar") |> render() |> String.split("<span") |> length() ==
               5

      assert has_element?(view, "#heart-trace-#{ride.id}[phx-hook] svg path.heart-trace-line")
      assert has_element?(view, "#heart-trace-#{ride.id} .heart-trace-caption", "96–171 bpm")
    end

    test "a workout with figures and no trace shows the figures alone", %{conn: conn} do
      ride = ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})
      workout_fixture(%{started_at: ~U[2026-07-08 18:00:20Z], hr_trace: []})

      {:ok, view, _html} = live(conn, ~p"/fitness/rides/#{ride.id}")
      assert has_element?(view, ".activity-health .activity-figure-value", "142 bpm")
      refute has_element?(view, ".heart-zones")
      refute has_element?(view, ".heart-trace")
    end

    test "a ride with no paired workout shows no health panel", %{conn: conn} do
      ride = ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})
      # Half an hour later is another outing, not this one.
      workout_fixture(%{started_at: ~U[2026-07-08 18:30:00Z]})

      {:ok, index, _html} = live(conn, ~p"/fitness/rides")
      refute has_element?(index, ".activity-health")
      refute has_element?(index, ".activity-card-health")

      {:ok, show, _html} = live(conn, ~p"/fitness/rides/#{ride.id}")
      refute has_element?(show, ".activity-health")
    end
  end

  describe "recent training" do
    defp ago(days),
      do: DateTime.utc_now() |> DateTime.add(-days, :day) |> DateTime.truncate(:second)

    test "the last 7 and the last 28 days, with the watch's share of them said", %{conn: conn} do
      this_week = ago(1)
      ride_fixture(%{started_at: this_week})

      workout_fixture(%{
        started_at: DateTime.add(this_week, 20),
        ended_at: DateTime.add(this_week, 7200)
      })

      ride_fixture(%{started_at: ago(12)})
      ride_fixture(%{started_at: ~U[2025-06-01 16:00:00Z]})

      {:ok, view, html} = live(conn, ~p"/fitness/rides")

      assert has_element?(view, "#recent-7 .activity-recent-title", "Last 7 days")

      assert figures(view, "#recent-7") == %{
               "Activities" => "1",
               "Time moving" => "1h 40m",
               "Distance" => "24.9 mi",
               "Active energy" => "612 kcal",
               "Avg heart rate" => "142 bpm"
             }

      # Every activity in the week was measured, so there is nothing to qualify.
      refute has_element?(view, "#recent-7 .activity-recent-note")

      assert figures(view, "#recent-28") == %{
               "Activities" => "2",
               "Time moving" => "3h 20m",
               "Distance" => "49.7 mi",
               "Active energy" => "612 kcal",
               "Avg heart rate" => "142 bpm"
             }

      assert has_element?(
               view,
               "#recent-28 .activity-recent-note",
               "Heart rate and energy from 1 of 2 activities."
             )

      # How training has gone comes before any one outing.
      assert :binary.match(html, "activity-recent") < :binary.match(html, "activity-feature")
    end

    test "with nothing from the watch it is Komoot's figures alone", %{conn: conn} do
      ride_fixture(%{started_at: ago(2)})

      {:ok, view, _html} = live(conn, ~p"/fitness/rides")

      assert figures(view, "#recent-7") == %{
               "Activities" => "1",
               "Time moving" => "1h 40m",
               "Distance" => "24.9 mi"
             }

      refute has_element?(view, ".activity-recent-note")
    end

    test "is left out after four weeks with nothing in them", %{conn: conn} do
      ride_fixture(%{started_at: ~U[2025-06-01 16:00:00Z]})

      {:ok, view, _html} = live(conn, ~p"/fitness/rides")
      refute has_element?(view, ".activity-recent")
      assert has_element?(view, ".activity-feature")
    end

    test "follows the sport filter", %{conn: conn} do
      ride_fixture(%{sport: "racebike", started_at: ago(1)})

      ride_fixture(%{
        sport: "jogging",
        distance_m: 5_000.0,
        time_in_motion_s: 1800,
        started_at: ago(2)
      })

      {:ok, view, _html} = live(conn, ~p"/fitness/rides?sport=jogging")

      assert figures(view, "#recent-7") == %{
               "Activities" => "1",
               "Time moving" => "30m",
               "Distance" => "3.1 mi"
             }
    end
  end

  test "the year's totals are one quiet line per year, below everything", %{conn: conn} do
    ride_fixture(%{started_at: ~U[2026-06-01 16:00:00Z], distance_m: 16_093.44, ascent_m: 100.0})
    ride_fixture(%{started_at: ~U[2025-06-01 16:00:00Z], distance_m: 8046.72, ascent_m: 100.0})
    workout_fixture(%{started_at: ~U[2026-06-01 16:00:10Z], ended_at: ~U[2026-06-01 17:40:00Z]})

    {:ok, view, html} = live(conn, ~p"/fitness/rides")

    # The year the watch measured says so; the year it did not says nothing.
    assert has_element?(
             view,
             ".activity-totals p",
             "2026 · 1 activity · 1h 40m moving · 10.0 mi · 328 ft up · 612 kcal · avg 142 bpm"
           )

    assert has_element?(
             view,
             ".activity-totals p",
             "2025 · 1 activity · 1h 40m moving · 5.0 mi · 328 ft up"
           )

    refute has_element?(
             view,
             ".activity-totals p",
             "2025 · 1 activity · 1h 40m moving · 5.0 mi · 328 ft up ·"
           )

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

  test "an unknown ride 404s", %{conn: conn} do
    assert_raise Ecto.NoResultsError, fn -> live(conn, ~p"/fitness/rides/999999") end
  end
end
