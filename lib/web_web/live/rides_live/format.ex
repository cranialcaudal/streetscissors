defmodule WebWeb.RidesLive.Format do
  @moduledoc """
  Display formatting and wire encoding shared by the ride LiveViews.
  """

  alias Web.Rides.Stats

  @doc "Compact `[[lat, lon], ...]` payload for the RideMap hook, 5 dp (~1 m)."
  def encode_points(points) do
    Enum.map(points, fn p -> [Float.round(p.lat, 5), Float.round(p.lon, 5)] end)
  end

  @doc """
  `%{dist: [...], ele: [...]}` series for the ElevationProfile hook —
  cumulative distance (m) at each point that has an altitude.
  """
  def elevation_series(points) do
    {series, _cum, _prev} =
      Enum.reduce(points, {[], 0.0, nil}, fn point, {series, cum, prev} ->
        cum =
          if prev,
            do: cum + Stats.haversine_m({prev.lat, prev.lon}, {point.lat, point.lon}),
            else: cum

        series =
          if is_number(point.altitude_m),
            do: [{Float.round(cum, 1), Float.round(point.altitude_m, 1)} | series],
            else: series

        {series, cum, point}
      end)

    {dist, ele} = series |> Enum.reverse() |> Enum.unzip()
    %{dist: dist, ele: ele}
  end

  defdelegate distance(meters), to: Web.Rides.Units
  defdelegate duration(seconds), to: Web.Rides.Units
  defdelegate speed(mps), to: Web.Rides.Units
  defdelegate elevation(meters), to: Web.Rides.Units
  defdelegate date(dt), to: Web.Rides.Units
  defdelegate time(dt), to: Web.Rides.Units
end
