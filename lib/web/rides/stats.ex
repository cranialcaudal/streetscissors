defmodule Web.Rides.Stats do
  @moduledoc """
  Pure ride-statistics math over chronologically ordered points.
  """

  @earth_radius_m 6_371_000.0
  # Segments with worse GPS accuracy than this don't contribute to speed stats.
  @max_accuracy_m 50.0
  # Altitude deltas smaller than this are treated as GPS noise.
  @ele_threshold_m 2.0

  @doc "Great-circle distance in meters between two {lat, lon} pairs."
  def haversine_m({lat1, lon1}, {lat2, lon2}) do
    dlat = deg2rad(lat2 - lat1)
    dlon = deg2rad(lon2 - lon1)

    a =
      :math.sin(dlat / 2) ** 2 +
        :math.cos(deg2rad(lat1)) * :math.cos(deg2rad(lat2)) * :math.sin(dlon / 2) ** 2

    2 * @earth_radius_m * :math.asin(min(1.0, :math.sqrt(a)))
  end

  @doc """
  Computes ride stats from ordered points. Returns a map with
  distance_m, duration_s, avg_speed_mps, max_speed_mps, ascent_m, descent_m.
  """
  def compute(points) when length(points) < 2 do
    %{
      distance_m: 0.0,
      duration_s: 0,
      avg_speed_mps: nil,
      max_speed_mps: max_recorded_speed(points),
      ascent_m: 0.0,
      descent_m: 0.0
    }
  end

  def compute(points) do
    distance = total_distance_m(points)
    duration = duration_s(points)
    {ascent, descent} = elevation_gain_m(points)

    %{
      distance_m: distance,
      duration_s: duration,
      avg_speed_mps: if(duration > 0, do: distance / duration),
      max_speed_mps: max_speed_mps(points),
      ascent_m: ascent,
      descent_m: descent
    }
  end

  def total_distance_m(points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(0.0, fn [a, b], acc ->
      acc + haversine_m({a.lat, a.lon}, {b.lat, b.lon})
    end)
  end

  def duration_s(points) do
    DateTime.diff(List.last(points).recorded_at, List.first(points).recorded_at)
  end

  @doc """
  Max speed, preferring device-recorded speeds and falling back to computed
  segment speeds; segments with poor accuracy are ignored to avoid GPS spikes.
  """
  def max_speed_mps(points) do
    case max_recorded_speed(points) do
      nil -> max_computed_speed(points)
      max -> max
    end
  end

  defp max_recorded_speed(points) do
    points
    |> Enum.map(& &1.speed_mps)
    |> Enum.filter(&(is_number(&1) and &1 >= 0))
    |> Enum.max(fn -> nil end)
  end

  defp max_computed_speed(points) do
    points
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] ->
      dt = DateTime.diff(b.recorded_at, a.recorded_at)

      if dt > 0 and accurate?(a) and accurate?(b) do
        haversine_m({a.lat, a.lon}, {b.lat, b.lon}) / dt
      end
    end)
    |> Enum.filter(&is_number/1)
    |> Enum.max(fn -> nil end)
  end

  defp accurate?(point) do
    is_nil(point.accuracy_m) or point.accuracy_m <= @max_accuracy_m
  end

  @doc """
  Total ascent/descent from altitudes, only counting moves of at least
  #{@ele_threshold_m} m between local extremes so GPS jitter doesn't inflate
  totals. Returns `{ascent_m, descent_m}`.
  """
  def elevation_gain_m(points) do
    points
    |> Enum.map(& &1.altitude_m)
    |> Enum.filter(&is_number/1)
    |> Enum.reduce({0.0, 0.0, nil}, fn ele, {up, down, anchor} ->
      cond do
        is_nil(anchor) -> {up, down, ele}
        ele - anchor >= @ele_threshold_m -> {up + (ele - anchor), down, ele}
        anchor - ele >= @ele_threshold_m -> {up, down + (anchor - ele), ele}
        true -> {up, down, anchor}
      end
    end)
    |> then(fn {up, down, _} -> {up, down} end)
  end

  defp deg2rad(deg), do: deg * :math.pi() / 180.0
end
