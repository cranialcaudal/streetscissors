defmodule Web.RidesFixtures do
  @moduledoc """
  Test helpers for the `Web.Rides` context.
  """

  @doc """
  An Overland GeoJSON feature with sensible defaults. The default timestamp
  is now + 1s so the point lands after any just-started ride's `started_at`.
  """
  def overland_feature(attrs \\ %{}) do
    props =
      Map.merge(
        %{
          "timestamp" => iso_in(1),
          "speed" => 5.0,
          "altitude" => 12.0,
          "horizontal_accuracy" => 5.0
        },
        Map.get(attrs, "properties", %{})
      )

    %{
      "type" => "Feature",
      "geometry" => %{
        "type" => "Point",
        "coordinates" => Map.get(attrs, "coordinates", [-121.49, 38.58])
      },
      "properties" => props
    }
  end

  @doc "ISO8601 timestamp `seconds` from now."
  def iso_in(seconds) do
    DateTime.utc_now()
    |> DateTime.add(seconds)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  @doc "A minimal valid GPX document with three timestamped track points."
  def gpx_fixture do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="komoot" xmlns="http://www.topografix.com/GPX/1/1">
      <trk>
        <name>Test Tour</name>
        <trkseg>
          <trkpt lat="54.5400" lon="-3.1500"><ele>100.0</ele><time>2026-07-08T08:00:00Z</time></trkpt>
          <trkpt lat="54.5410" lon="-3.1510"><ele>110.0</ele><time>2026-07-08T08:01:00Z</time></trkpt>
          <trkpt lat="54.5420" lon="-3.1520"><ele>105.0</ele><time>2026-07-08T08:02:00Z</time></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """
  end
end
