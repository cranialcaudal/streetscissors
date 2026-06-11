defmodule Web.Rides.Privacy do
  @moduledoc """
  Privacy-zone filtering for ride points.

  Zones are stored as JSON in the `ride_privacy_zones` site setting:
  `[{"lat": 38.58, "lon": -121.49, "radius_m": 1000}, ...]`.
  Points inside any zone are stored raw but must never reach public output —
  apply `filter/1` (or `list_points(ride, public: true)`) at every public egress:
  page loads, PubSub broadcasts, and "last position" displays.
  """

  alias Web.Rides.Stats

  @setting_key "ride_privacy_zones"

  def setting_key, do: @setting_key

  def zones do
    case Web.SiteSettings.get_setting(@setting_key) do
      nil ->
        Application.get_env(:web, :ride_privacy_zones, [])

      json ->
        case Jason.decode(json) do
          {:ok, zones} when is_list(zones) -> Enum.filter(zones, &valid_zone?/1)
          _ -> []
        end
    end
  end

  @doc "Rejects points (maps or structs with lat/lon) inside any privacy zone."
  def filter(points), do: filter(points, zones())

  def filter(points, []), do: points

  def filter(points, zones) do
    Enum.reject(points, fn point ->
      Enum.any?(zones, fn zone ->
        Stats.haversine_m({point.lat, point.lon}, {zone["lat"], zone["lon"]}) <
          (zone["radius_m"] || 1000)
      end)
    end)
  end

  defp valid_zone?(%{"lat" => lat, "lon" => lon} = zone)
       when is_number(lat) and is_number(lon) do
    is_number(zone["radius_m"]) or is_nil(zone["radius_m"])
  end

  defp valid_zone?(_), do: false
end
