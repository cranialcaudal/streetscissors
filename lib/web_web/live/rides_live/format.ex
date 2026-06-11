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

  def distance(nil), do: "—"

  def distance(meters) do
    miles = meters / 1609.344
    "#{:erlang.float_to_binary(miles, decimals: 1)} mi"
  end

  def duration(nil), do: "—"

  def duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    if hours > 0,
      do: "#{hours}h #{String.pad_leading(to_string(minutes), 2, "0")}m",
      else: "#{minutes}m"
  end

  def speed(nil), do: "—"

  def speed(mps) do
    mph = mps * 2.236936
    "#{:erlang.float_to_binary(mph, decimals: 1)} mph"
  end

  def elevation(nil), do: "—"

  def elevation(meters) do
    feet = round(meters * 3.28084)

    feet
    |> to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
    |> Kernel.<>(" ft")
  end

  def date(nil), do: "—"
  def date(%DateTime{} = dt), do: Calendar.strftime(dt, "%-d %b %Y")

  def time(nil), do: "—"
  def time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
end
