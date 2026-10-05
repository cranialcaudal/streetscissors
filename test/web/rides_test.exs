defmodule Web.RidesTest do
  use Web.DataCase

  import Web.RidesFixtures

  alias Web.Rides
  alias Web.Rides.{Thumbs, Units}

  setup do
    File.rm_rf!(Thumbs.dir())
    :ok
  end

  test "list_rides is newest first and includes private tours" do
    older = ride_fixture(%{started_at: ~U[2026-06-01 08:00:00Z]})
    newer = ride_fixture(%{started_at: ~U[2026-07-01 08:00:00Z], visibility: "private"})

    assert Enum.map(Rides.list_rides(), & &1.id) == [newer.id, older.id]
  end

  test "activities under 0.2 mi, or with no distance, never reach the site" do
    kept = ride_fixture(%{distance_m: 322.0})
    short = ride_fixture(%{distance_m: 321.0})
    unmeasured = ride_fixture(%{distance_m: nil})

    assert Enum.map(Rides.list_rides(), & &1.id) == [kept.id]
    assert Rides.get_ride(short.id) == nil
    assert Rides.get_ride(to_string(unmeasured.id)) == nil

    # The sync still sees the whole archive, or it would re-import them forever.
    assert map_size(Rides.komoot_index()) == 3
  end

  test "get_ride takes ids straight from a URL" do
    ride = ride_fixture()

    assert Rides.get_ride(ride.id).id == ride.id
    assert Rides.get_ride(to_string(ride.id)).id == ride.id
    assert Rides.get_ride("999999") == nil
    assert Rides.get_ride("live") == nil
    assert Rides.get_ride(nil) == nil
  end

  test "a ride needs a start time and a Komoot tour id no other ride has" do
    ride_fixture(%{komoot_id: "42"})

    assert {:error, changeset} =
             Rides.create_ride(%{komoot_id: "42", started_at: ~U[2026-07-01 08:00:00Z]})

    assert %{komoot_id: ["has already been taken"]} = errors_on(changeset)

    assert {:error, changeset} = Rides.create_ride(%{})
    assert %{komoot_id: ["can't be blank"], started_at: ["can't be blank"]} = errors_on(changeset)
  end

  test "delete_ride removes the cached thumbnail" do
    ride = ride_fixture(%{map_image_url: "https://cdn.example/maps/1.jpg"})
    :ok = Thumbs.store(ride, "fake-jpeg")
    assert Thumbs.exists?(ride)

    {:ok, _ride} = Rides.delete_ride(ride)
    refute Thumbs.exists?(ride)
    assert File.ls!(Thumbs.dir()) == []
  end

  describe "Thumbs" do
    test "a picture is named for the map it came from, so no other map's can be served" do
      ride = ride_fixture(%{map_image_url: "https://cdn.example/maps/cut-by-the-zone.jpg"})
      :ok = Thumbs.store(ride, "the stranger's map")

      assert Path.basename(Thumbs.path(ride)) =~ ~r/^#{ride.id}-[0-9a-f]{12}\.jpg$/
      assert Rides.thumb?(ride)

      # The route is cut differently now: a different map, a different name.
      recut = %{ride | map_image_url: "https://cdn.example/maps/cut-again.jpg"}
      refute Thumbs.exists?(recut)
      refute Thumbs.path(recut) == Thumbs.path(ride)
    end

    # What an earlier version of the site kept: the owner's map, whole route
    # and all, as `<id>.jpg`.
    test "a picture cached under the bare ride id is never the ride's picture" do
      ride = ride_fixture(%{map_image_url: "https://cdn.example/maps/1.jpg"})
      File.mkdir_p!(Thumbs.dir())
      File.write!(Path.join(Thumbs.dir(), "#{ride.id}.jpg"), "the whole route")

      refute Thumbs.exists?(ride)
      refute Rides.thumb?(ride)

      :ok = Thumbs.store(ride, "the stranger's map")
      assert File.ls!(Thumbs.dir()) == [Path.basename(Thumbs.path(ride))]
    end

    test "a ride with no map has no picture, and storing one is refused" do
      ride = ride_fixture()

      assert Thumbs.path(ride) == nil
      refute Thumbs.exists?(ride)
      assert Thumbs.store(ride, "bytes") == :error
    end

    test "sweep_all/1 removes what no listed ride answers for, and only that" do
      kept = ride_fixture(%{map_image_url: "https://cdn.example/maps/kept.jpg"})
      :ok = Thumbs.store(kept, "kept")
      File.write!(Path.join(Thumbs.dir(), "99999.jpg"), "legacy")
      File.write!(Path.join(Thumbs.dir(), "88888-0123456789ab.jpg"), "a deleted ride's")

      assert Thumbs.sweep_all([kept]) == 2
      assert File.ls!(Thumbs.dir()) == [Path.basename(Thumbs.path(kept))]
    end
  end

  describe "Komoot links" do
    test "a public tour embeds as itself" do
      ride = ride_fixture(%{komoot_id: "123", visibility: "public"})

      # Everything the embed can show is asked for: the profile, the photographs.
      assert Rides.embed_url(ride) == "https://www.komoot.com/tour/123/embed?profile=1&gallery=1"
      assert Rides.tour_url(ride) == "https://www.komoot.com/tour/123"
    end

    test "a private tour embeds through its share token" do
      ride = ride_fixture(%{komoot_id: "123", visibility: "private", share_token: "abc"})

      assert Rides.embed_url(ride) ==
               "https://www.komoot.com/tour/123/embed?share_token=abc&profile=1&gallery=1"

      assert Rides.tour_url(ride) == "https://www.komoot.com/tour/123?share_token=abc"
    end

    test "a private tour with no token yet has no link a visitor could open" do
      ride = ride_fixture(%{visibility: "private"})

      assert Rides.embed_url(ride) == nil
      assert Rides.tour_url(ride) == nil
    end

    # Only a tour the sync has read as a stranger and found clear is given
    # anything of Komoot's to show. Public or tokened, picture on disk or not.
    test "a tour that is not clear has no embed, no link and no picture, whatever else it has" do
      for view <- ["exposed", "passing", "hidden", nil],
          attrs <- [%{visibility: "public"}, %{visibility: "private", share_token: "abc"}] do
        ride =
          ride_fixture(
            Map.merge(attrs, %{stranger_view: view, map_image_url: "https://cdn/x.jpg"})
          )

        :ok = Thumbs.store(ride, "a picture that must not be shown")

        refute Rides.clear?(ride)
        assert Rides.embed_url(ride) == nil
        assert Rides.tour_url(ride) == nil
        refute Rides.thumb?(ride)
        assert Rides.thumb_src(ride) == nil
      end

      assert length(Rides.exposed()) == 2
    end

    test "a ride's view is one of the three, or not yet asked" do
      assert {:error, changeset} =
               Rides.create_ride(%{
                 komoot_id: "1",
                 started_at: ~U[2026-07-08 18:00:00Z],
                 stranger_view: "probably fine"
               })

      assert %{stranger_view: ["is invalid"]} = errors_on(changeset)

      assert {:ok, %{stranger_view: nil} = ride} =
               Rides.create_ride(%{komoot_id: "2", started_at: ~U[2026-07-08 18:00:00Z]})

      refute Rides.clear?(ride)
    end

    test "exposed/0 leaves false starts out, as every listing does" do
      ride_fixture(%{stranger_view: "exposed", distance_m: 100.0})
      assert Rides.exposed() == []
    end

    test "stranger_views/0 counts the listed rides in each state" do
      ride_fixture()
      ride_fixture()
      ride_fixture(%{stranger_view: "passing"})
      ride_fixture(%{stranger_view: nil})
      ride_fixture(%{stranger_view: "exposed", distance_m: 100.0})

      assert Rides.stranger_views() == %{"clear" => 2, "passing" => 1, nil => 1}
    end

    test "a picture's address names the map it was drawn from" do
      ride = ride_fixture(%{map_image_url: "https://cdn.example/maps/1.jpg"})
      assert Rides.thumb_src(ride) == nil

      :ok = Thumbs.store(ride, "the stranger's map")

      assert Rides.thumb_src(ride) ==
               "/fitness/rides/#{ride.id}/thumb?v=" <>
                 Thumbs.fingerprint("https://cdn.example/maps/1.jpg")
    end
  end

  describe "health" do
    test "a ride carries the workout that started nearest to it" do
      ride = ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})
      workout_fixture(%{started_at: ~U[2026-07-08 18:04:00Z], avg_hr: 120})
      nearest = workout_fixture(%{started_at: ~U[2026-07-08 17:59:30Z], avg_hr: 142})

      assert [%{health: %{id: id}}] = Rides.list_rides()
      assert id == nearest.id
      assert Rides.get_ride(ride.id).health.avg_hr == 142
    end

    test "a workout more than ten minutes off is another outing" do
      ride = ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})
      workout_fixture(%{started_at: ~U[2026-07-08 18:11:00Z]})

      assert Rides.get_ride(ride.id).health == nil
    end

    test "each ride in a list is matched on its own" do
      ride_fixture(%{started_at: ~U[2026-07-01 16:00:00Z]})
      ride_fixture(%{started_at: ~U[2026-07-08 16:00:00Z]})
      workout_fixture(%{started_at: ~U[2026-07-08 16:00:05Z], avg_hr: 150})

      assert [%{health: %{avg_hr: 150}}, %{health: nil}] = Rides.list_rides()
    end

    test "a workout is stored once, however often it is sent" do
      workout = %{
        hk_id: "HK-1",
        activity: "Outdoor Cycling",
        started_at: ~U[2026-07-08 18:00:10Z],
        ended_at: ~U[2026-07-08 20:00:00Z],
        avg_hr: 142,
        max_hr: 170,
        active_kcal: 600
      }

      assert Rides.store_workouts([workout]) == 1
      assert Rides.store_workouts([%{workout | active_kcal: 610}]) == 1
      assert Rides.count_workouts() == 1

      ride = ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})
      assert %{avg_hr: 142, max_hr: 170, active_kcal: 610} = Rides.get_ride(ride.id).health
    end

    test "a workout that cannot be stored is skipped, not fatal" do
      good = %{hk_id: "HK-2", started_at: ~U[2026-07-08 18:00:10Z]}

      assert Rides.store_workouts([%{hk_id: "no start"}, good, %{}]) == 1
      assert Rides.store_workouts([]) == 0
    end

    test "the ceiling is the highest heart rate any workout reached" do
      assert Rides.heart_rate_ceiling() == nil

      workout_fixture(%{max_hr: 171})
      workout_fixture(%{max_hr: 188})
      workout_fixture(%{max_hr: nil})

      assert Rides.heart_rate_ceiling() == 188
    end
  end

  describe "totals/1" do
    test "Komoot's figures are summed over every ride" do
      rides = [
        ride_fixture(%{distance_m: 10_000.0, time_in_motion_s: 1800, ascent_m: 100.0}),
        ride_fixture(%{
          distance_m: 20_000.0,
          time_in_motion_s: nil,
          duration_s: 3000,
          ascent_m: nil
        })
      ]

      assert %{rides: 2, distance_m: 30_000.0, moving_s: 4800, ascent_m: 100.0} =
               Rides.totals(rides)
    end

    test "the watch's figures come from the rides it measured, and say how many that was" do
      ride_fixture(%{started_at: ~U[2026-07-01 16:00:00Z]})
      ride_fixture(%{started_at: ~U[2026-07-08 16:00:00Z]})
      ride_fixture(%{started_at: ~U[2026-07-15 16:00:00Z]})

      # An hour at 150, and ten minutes at 100.
      workout_fixture(%{
        started_at: ~U[2026-07-08 16:00:05Z],
        ended_at: ~U[2026-07-08 17:00:05Z],
        avg_hr: 150,
        max_hr: 181,
        active_kcal: 700
      })

      workout_fixture(%{
        started_at: ~U[2026-07-15 16:00:05Z],
        ended_at: ~U[2026-07-15 16:10:05Z],
        avg_hr: 100,
        max_hr: 120,
        active_kcal: 80
      })

      totals = Rides.totals(Rides.list_rides())

      assert totals.rides == 3
      assert totals.measured == 2
      assert totals.active_kcal == 780
      assert totals.max_hr == 181
      # Weighted by how long each lasted: far nearer 150 than the 125 between.
      assert totals.avg_hr == 143
    end

    test "with nothing measured the watch's figures are absent, not zero" do
      assert %{measured: 0, active_kcal: nil, avg_hr: nil, max_hr: nil} =
               Rides.totals([ride_fixture()])

      assert %{rides: 0, distance_m: 0, moving_s: 0, measured: 0, avg_hr: nil} = Rides.totals([])
    end
  end

  describe "recent/3" do
    test "is the activities of the last N Pacific days, today included" do
      today = ~D[2026-07-10]

      # 06:30 UTC on the 4th is 11:30pm on the 3rd in California: outside.
      ride_fixture(%{started_at: ~U[2026-07-04 06:30:00Z], distance_m: 1_000.0})
      # 07:30 UTC on the 4th is half past midnight on the 4th: inside.
      ride_fixture(%{started_at: ~U[2026-07-04 07:30:00Z], distance_m: 2_000.0})
      ride_fixture(%{started_at: ~U[2026-07-10 20:00:00Z], distance_m: 4_000.0})
      ride_fixture(%{started_at: ~U[2026-06-20 20:00:00Z], distance_m: 8_000.0})

      rides = Rides.list_rides()

      assert %{rides: 2, distance_m: 6_000.0} = Rides.recent(rides, 7, today)
      assert %{rides: 4, distance_m: 15_000.0} = Rides.recent(rides, 28, today)
      assert %{rides: 0} = Rides.recent(rides, 7, ~D[2026-08-30])
    end
  end

  test "shelves put the biggest sport first, ties to the most recent, each newest first" do
    hike = ride_fixture(%{sport: "hike", started_at: ~U[2026-09-10 16:00:00Z]})
    road_new = ride_fixture(%{sport: "racebike", started_at: ~U[2026-09-08 16:00:00Z]})
    run_new = ride_fixture(%{sport: "jogging", started_at: ~U[2026-09-06 16:00:00Z]})
    road_old = ride_fixture(%{sport: "racebike", started_at: ~U[2026-09-04 16:00:00Z]})
    run_old = ride_fixture(%{sport: "jogging", started_at: ~U[2026-09-02 16:00:00Z]})

    shelves =
      Rides.list_rides()
      |> Rides.shelves()
      |> Enum.map(fn {sport, rides} -> {sport, Enum.map(rides, & &1.id)} end)

    # Road cycling and running tie at two; road cycling was done more recently.
    assert shelves == [
             {"racebike", [road_new.id, road_old.id]},
             {"jogging", [run_new.id, run_old.id]},
             {"hike", [hike.id]}
           ]

    assert Rides.shelves([]) == []
  end

  describe "yearly_totals/1" do
    test "sums every ride, private ones included, per Pacific-local year" do
      rides = [
        ride_fixture(%{
          started_at: ~U[2026-03-01 16:00:00Z],
          distance_m: 10_000.0,
          time_in_motion_s: 1800,
          ascent_m: 100.0
        }),
        ride_fixture(%{
          started_at: ~U[2026-06-01 16:00:00Z],
          distance_m: 40_000.0,
          time_in_motion_s: 6000,
          ascent_m: 800.0,
          visibility: "private"
        }),
        # 05:00 UTC on New Year's Day is still 9pm on the 31st in California.
        ride_fixture(%{
          started_at: ~U[2027-01-01 05:00:00Z],
          distance_m: 20_000.0,
          time_in_motion_s: nil,
          duration_s: 3000,
          ascent_m: 200.0
        }),
        ride_fixture(%{started_at: ~U[2025-05-01 16:00:00Z], distance_m: 5_000.0})
      ]

      assert [y2026, y2025] = Rides.yearly_totals(rides)

      assert y2026.year == 2026
      assert y2026.rides == 3
      assert y2026.distance_m == 70_000.0
      # Moving time, falling back to elapsed time where Komoot sent none.
      assert y2026.moving_s == 1800 + 6000 + 3000
      assert y2026.ascent_m == 1100.0
      # Nothing was measured that year, and the totals do not pretend otherwise.
      assert %{measured: 0, active_kcal: nil, avg_hr: nil} = y2026

      assert %{year: 2025, rides: 1, distance_m: 5_000.0} = y2025
    end

    test "no rides, no years" do
      assert Rides.yearly_totals([]) == []
    end
  end

  describe "Units" do
    test "sport reads Komoot's keys the way Komoot names them" do
      assert Units.sport("racebike") == "Road cycling"
      assert Units.sport("touringbicycle") == "Bike touring"
      assert Units.sport("jogging") == "Running"
      assert Units.sport("hike") == "Hiking"
      assert Units.sport("e_touringbicycle") == "E-bike touring"
      assert Units.sport("nordic_walking") == "Nordic walking"
      assert Units.sport(nil) == "Activity"
    end

    test "sport_kind groups sports the way The Week colors them" do
      assert Units.sport_kind("racebike") == "bike"
      assert Units.sport_kind("e_mtb") == "bike"
      assert Units.sport_kind("jogging") == "run"
      assert Units.sport_kind("hike") == "hike"
      assert Units.sport_kind("climbing") == "other"
      assert Units.sport_kind(nil) == "other"
    end

    test "heart rate and energy read the way the watch says them" do
      assert Units.bpm(141.6) == "142 bpm"
      assert Units.kcal(1204.4) == "1,204 kcal"
      assert Units.kcal(87) == "87 kcal"
      assert Units.bpm(nil) == "—"
      assert Units.kcal(nil) == "—"
    end

    test "dates are the Pacific day an activity happened on" do
      # 00:05 UTC on the 12th is still the evening of the 11th in California.
      assert Units.date(~U[2026-09-12 00:05:26Z]) == "11 Sep 2026"
      assert Units.day(~U[2026-09-12 00:05:26Z]) == "Fri 11 Sep 2026"
    end
  end
end
