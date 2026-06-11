defmodule Web.RidesTest do
  use Web.DataCase

  import Web.RidesFixtures

  alias Web.Rides
  alias Web.Rides.{Privacy, Stats}

  defp feature_in(seconds, coordinates) do
    overland_feature(%{
      "coordinates" => coordinates,
      "properties" => %{"timestamp" => iso_in(seconds)}
    })
  end

  describe "ride lifecycle" do
    test "start_ride/stop_ride computes stats from ingested points" do
      {:ok, ride} = Rides.start_ride(%{"name" => "Test loop"})
      assert ride.status == "active"
      assert Rides.get_active_ride().id == ride.id

      {:ok, 2} =
        Rides.ingest_locations([
          feature_in(1, [-121.49, 38.58]),
          feature_in(61, [-121.48, 38.58])
        ])

      {:ok, completed} = Rides.stop_ride(Rides.get_active_ride())
      assert completed.status == "completed"
      assert completed.point_count == 2
      assert completed.duration_s == 60
      # ~0.01 degrees of longitude at this latitude is ~870 m
      assert_in_delta completed.distance_m, 870, 30
      assert Rides.get_active_ride() == nil
      assert [%{id: id}] = Rides.list_completed_rides()
      assert id == completed.id
    end

    test "starting a new ride closes the previous active one" do
      {:ok, first} = Rides.start_ride(%{"name" => "First"})
      {:ok, second} = Rides.start_ride(%{"name" => "Second"})

      assert Rides.get_ride!(first.id).status == "completed"
      assert Rides.get_active_ride().id == second.id
    end

    test "auto_close_stale_ride leaves fresh rides alone" do
      {:ok, ride} = Rides.start_ride(%{"name" => "Fresh"})
      assert :ok = Rides.auto_close_stale_ride()
      assert Rides.get_active_ride().id == ride.id
    end
  end

  describe "ingest_locations/1" do
    test "without an active ride the batch is discarded but accepted" do
      assert {:ok, 0} = Rides.ingest_locations([feature_in(1, [0.0, 0.0])])
    end

    test "duplicate batches do not duplicate points (Overland retries)" do
      {:ok, _ride} = Rides.start_ride(%{})
      batch = [feature_in(1, [-121.49, 38.58])]

      {:ok, 1} = Rides.ingest_locations(batch)
      {:ok, 1} = Rides.ingest_locations(batch)

      assert Rides.get_active_ride().point_count == 1
    end

    test "malformed features and pre-ride timestamps are dropped" do
      {:ok, _ride} = Rides.start_ride(%{})

      {:ok, 1} =
        Rides.ingest_locations([
          %{"bogus" => true},
          %{"geometry" => %{"coordinates" => [1.0, 2.0]}, "properties" => %{}},
          feature_in(-3600, [-121.49, 38.58]),
          feature_in(1, [-121.49, 38.58])
        ])
    end
  end

  describe "privacy filtering" do
    test "points inside a zone are stored but hidden from public reads" do
      zones = Jason.encode!([%{"lat" => 38.58, "lon" => -121.49, "radius_m" => 1000}])
      {:ok, _setting} = Web.SiteSettings.put_setting(Privacy.setting_key(), zones)

      {:ok, _ride} = Rides.start_ride(%{})

      {:ok, 2} =
        Rides.ingest_locations([
          # inside the zone
          feature_in(1, [-121.49, 38.58]),
          # ~9 km east, well outside
          feature_in(300, [-121.39, 38.58])
        ])

      ride = Rides.get_active_ride()
      assert length(Rides.list_points(ride, public: false)) == 2
      assert [public_point] = Rides.list_points(ride)
      assert public_point.lon == -121.39
    end
  end

  describe "GPX import" do
    test "creates a completed ride with stats" do
      {:ok, ride} = Rides.import_gpx(gpx_fixture(), %{"name" => "Komoot import"})

      assert ride.status == "completed"
      assert ride.source == "gpx"
      assert ride.point_count == 3
      assert ride.duration_s == 120
      assert ride.distance_m > 0
      # 100 -> 110 -> 105: 10 m up, 5 m down
      assert_in_delta ride.ascent_m, 10.0, 0.01
      assert_in_delta ride.descent_m, 5.0, 0.01
    end

    @tag :capture_log
    test "rejects files without track points" do
      assert {:error, :no_track_points} = Rides.import_gpx("<gpx></gpx>", %{})
      assert {:error, :invalid_gpx} = Rides.import_gpx("not xml at all", %{})
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
