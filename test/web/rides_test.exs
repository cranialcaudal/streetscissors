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
    ride = ride_fixture()
    :ok = Thumbs.store(ride, "fake-jpeg")

    {:ok, _ride} = Rides.delete_ride(ride)
    refute Thumbs.exists?(ride)
  end

  describe "Komoot links" do
    test "a public tour embeds as itself" do
      ride = ride_fixture(%{komoot_id: "123", visibility: "public"})

      assert Rides.embed_url(ride) == "https://www.komoot.com/tour/123/embed?profile=1"
      assert Rides.tour_url(ride) == "https://www.komoot.com/tour/123"
    end

    test "a private tour embeds through its share token" do
      ride = ride_fixture(%{komoot_id: "123", visibility: "private", share_token: "abc"})

      assert Rides.embed_url(ride) ==
               "https://www.komoot.com/tour/123/embed?share_token=abc&profile=1"

      assert Rides.tour_url(ride) == "https://www.komoot.com/tour/123?share_token=abc"
    end

    test "a private tour with no token yet has no link a visitor could open" do
      ride = ride_fixture(%{visibility: "private"})

      assert Rides.embed_url(ride) == nil
      assert Rides.tour_url(ride) == nil
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

    test "ingest stores a workout once, however often the export repeats it" do
      raw = %{
        "id" => "HK-1",
        "name" => "Outdoor Cycling",
        "start" => "2026-07-08 11:00:10 -0700",
        "end" => "2026-07-08 13:00:00 -0700",
        "heartRate" => %{"avg" => %{"qty" => 141.6}, "max" => %{"qty" => 170}},
        "activeEnergyBurned" => %{"qty" => 600, "units" => "kcal"}
      }

      assert Rides.ingest_workouts([raw]) == 1
      assert Rides.ingest_workouts([%{raw | "activeEnergyBurned" => %{"qty" => 610}}]) == 1
      assert Rides.count_workouts() == 1

      ride = ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})
      assert %{avg_hr: 142, max_hr: 170, active_kcal: 610} = Rides.get_ride(ride.id).health
    end

    test "a workout without a readable start is skipped, not fatal" do
      assert Rides.ingest_workouts([%{"id" => "x"}, "junk", %{"start" => "yesterday"}]) == 0
      assert Rides.ingest_workouts(nil) == 0
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

    test "dates are the Pacific day an activity happened on" do
      # 00:05 UTC on the 12th is still the evening of the 11th in California.
      assert Units.date(~U[2026-09-12 00:05:26Z]) == "11 Sep 2026"
      assert Units.day(~U[2026-09-12 00:05:26Z]) == "Fri 11 Sep 2026"
    end
  end
end
