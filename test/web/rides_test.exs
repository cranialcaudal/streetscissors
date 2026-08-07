defmodule Web.RidesTest do
  use Web.DataCase

  import Web.RidesFixtures

  alias Web.Rides
  alias Web.Rides.{Privacy, Stats}

  describe "privacy filtering" do
    test "points inside a zone are stored but hidden from public reads" do
      zones = Jason.encode!([%{"lat" => 54.54, "lon" => -3.15, "radius_m" => 200}])
      {:ok, _setting} = Web.SiteSettings.put_setting(Privacy.setting_key(), zones)

      {:ok, ride} = Rides.import_gpx(gpx_fixture(), %{"name" => "Zoned"})

      assert length(Rides.list_points(ride, public: false)) == 3
      public = Rides.list_points(ride)
      assert length(public) < 3
      assert Enum.all?(public, &(Stats.haversine_m({54.54, -3.15}, {&1.lat, &1.lon}) > 200))
    end
  end

  describe "GPX import" do
    test "creates a recorded ride with stats" do
      {:ok, ride} = Rides.import_gpx(gpx_fixture(), %{"name" => "Komoot import"})

      assert ride.kind == "recorded"
      assert ride.source == "gpx"
      assert ride.point_count == 3
      assert ride.duration_s == 120
      assert ride.distance_m > 0
      # 100 -> 110 -> 105: 10 m up, 5 m down
      assert_in_delta ride.ascent_m, 10.0, 0.01
      assert_in_delta ride.descent_m, 5.0, 0.01
      assert [%{id: id}] = Rides.list_recorded_rides()
      assert id == ride.id
    end

    @tag :capture_log
    test "rejects files without track points" do
      assert {:error, :no_track_points} = Rides.import_gpx("<gpx></gpx>", %{})
      assert {:error, :invalid_gpx} = Rides.import_gpx("not xml at all", %{})
    end
  end

  describe "create_imported_ride/3" do
    test "planned rides get distance and elevation but no duration or speeds" do
      points =
        Enum.with_index([{54.54, -3.15, 100.0}, {54.55, -3.15, 130.0}, {54.56, -3.15, 120.0}])
        |> Enum.map(fn {{lat, lon, alt}, i} ->
          %{
            lat: lat,
            lon: lon,
            altitude_m: alt,
            recorded_at: DateTime.add(~U[2026-07-08 08:00:00Z], i, :second)
          }
        end)

      {:ok, ride} =
        Rides.create_imported_ride(
          points,
          %{"name" => "Fred Whitton", "source" => "komoot", "komoot_id" => "123"},
          kind: "planned"
        )

      assert ride.kind == "planned"
      assert ride.distance_m > 2000
      assert_in_delta ride.ascent_m, 30.0, 0.01
      assert ride.duration_s == nil
      assert ride.avg_speed_mps == nil
      assert [%{id: id}] = Rides.list_planned_rides()
      assert id == ride.id
      assert Rides.list_recorded_rides() == []
    end
  end

  describe "komoot helpers" do
    test "known_komoot_ids returns the set of imported tour ids" do
      assert Rides.known_komoot_ids() == MapSet.new()

      {:ok, _ride} =
        Rides.import_gpx(gpx_fixture(), %{"source" => "komoot", "komoot_id" => "42"})

      assert Rides.known_komoot_ids() == MapSet.new(["42"])
    end

    test "attach_komoot accepts tour URLs and bare ids, rejects garbage" do
      {:ok, ride} = Rides.import_gpx(gpx_fixture(), %{"name" => "Manual"})

      assert {:ok, %{komoot_id: "987654321"}} =
               Rides.attach_komoot(ride, "https://www.komoot.com/tour/987654321?ref=wtd")

      assert {:ok, %{komoot_id: "555"}} = Rides.attach_komoot(ride, "555")
      assert {:error, :invalid_komoot_id} = Rides.attach_komoot(ride, "not a tour")
    end

    test "attach_komoot enforces uniqueness across rides" do
      {:ok, first} = Rides.import_gpx(gpx_fixture(), %{"name" => "First"})
      {:ok, second} = Rides.import_gpx(gpx_fixture(), %{"name" => "Second"})

      assert {:ok, _ride} = Rides.attach_komoot(first, "777")
      assert {:error, %Ecto.Changeset{}} = Rides.attach_komoot(second, "777")
    end
  end

  describe "visibility and accessors" do
    setup do
      File.rm_rf!(Web.Rides.Thumbs.dir())
      :ok
    end

    defp ride_points(start) do
      Enum.map(0..2, fn i ->
        %{
          lat: 54.54 + i / 100,
          lon: -3.15,
          altitude_m: 100.0,
          recorded_at: DateTime.add(start, i * 60, :second)
        }
      end)
    end

    test "private rides are hidden from public queries but visible to admin ones" do
      {:ok, ride} = Rides.import_gpx(gpx_fixture(), %{"name" => "Secret"})
      {:ok, ride} = Rides.update_ride(ride, %{"visibility" => "private"})

      assert Rides.list_recorded_rides() == []
      assert [%{id: id}] = Rides.list_recorded_rides(public: false)
      assert id == ride.id
      assert Rides.latest_recorded_ride() == nil
      assert Rides.get_public_ride(ride.id) == nil
      assert %Web.Rides.Ride{} = Rides.get_ride!(ride.id)
    end

    test "latest_recorded_ride returns the newest public recorded ride" do
      assert Rides.latest_recorded_ride() == nil

      {:ok, _older} =
        Rides.create_imported_ride(ride_points(~U[2026-06-01 08:00:00Z]), %{"name" => "Old"})

      {:ok, newer} =
        Rides.create_imported_ride(ride_points(~U[2026-07-01 08:00:00Z]), %{"name" => "New"})

      assert Rides.latest_recorded_ride().id == newer.id
    end

    test "aggregate_stats sums public recorded rides per calendar window" do
      recent = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-60, :second)
      {:ok, _ride} = Rides.create_imported_ride(ride_points(recent), %{"name" => "Recent"})

      {:ok, hidden} =
        Rides.create_imported_ride(
          ride_points(DateTime.add(recent, -600, :second)),
          %{"name" => "Hidden", "komoot_id" => "hidden-1"}
        )

      {:ok, _hidden} = Rides.update_ride(hidden, %{"visibility" => "private"})

      totals = Rides.aggregate_stats()
      assert totals.week.rides == 1
      assert totals.month.rides == 1
      assert totals.year.rides == 1
      assert totals.week.distance_m > 0
      assert [%{rides: 1}] = totals.by_sport
    end

    test "delete_ride removes the cached thumbnail" do
      {:ok, ride} = Rides.import_gpx(gpx_fixture(), %{"name" => "Thumbed"})
      :ok = Web.Rides.Thumbs.store(ride, "fake-jpeg")
      assert Web.Rides.Thumbs.exists?(ride)

      {:ok, _ride} = Rides.delete_ride(ride)
      refute Web.Rides.Thumbs.exists?(ride)
    end
  end

  describe "Stats" do
    test "haversine_m is ~111 km per degree of latitude" do
      assert_in_delta Stats.haversine_m({0.0, 0.0}, {1.0, 0.0}), 111_195, 100
    end

    test "elevation_gain_m ignores sub-threshold jitter" do
      points =
        [100.0, 100.5, 100.0, 100.5, 110.0, 109.0, 104.0]
        |> Enum.map(&%{altitude_m: &1})

      {ascent, descent} = Stats.elevation_gain_m(points)
      assert_in_delta ascent, 10.0, 0.01
      assert_in_delta descent, 6.0, 0.01
    end
  end
end
