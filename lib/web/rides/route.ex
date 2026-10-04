defmodule Web.Rides.Route do
  @moduledoc """
  The part of a ride's track that is published, and the three things drawn
  from it: the map line, the elevation profile and the small outline on a
  card.

  `build/2` is the only way from a recorded track to anything a visitor
  sees, and it goes through `Web.Rides.Privacy` first. Distances along a
  route count the published runs only, closed up end to end, so the profile
  never shows how much path a zone took out.
  """

  alias Web.Rides.Privacy

  defstruct segments: [], start?: false, finish?: false, length_m: 0.0

  # Enough to follow a street grid at any zoom the map allows.
  @max_points 1200
  @max_card_points 160

  @card_width 160
  @card_height 90
  @card_pad 10

  @profile_width 1000
  @profile_height 200

  @doc """
  The published route of a recorded track: `segments` of
  `{lat, lng, alt_m, distance_m}`, and whether the route's own start and
  finish are among them (`start?`, `finish?`) or were cut away.
  """
  def build(points, ride_key) do
    runs = Privacy.redact(points, ride_key)
    step = max(1, ceil(Enum.sum(Enum.map(runs, fn {run, _, _} -> length(run) end)) / @max_points))

    {segments, length_m} =
      Enum.map_reduce(runs, 0.0, fn {run, _, _}, offset ->
        {measured, total} = measure(run, offset)
        {thin(measured, step), total}
      end)

    %__MODULE__{
      segments: segments,
      start?: match?([{_, false, _} | _], runs),
      finish?: match?({_, _, false}, List.last(runs)),
      length_m: length_m
    }
  end

  def empty?(%__MODULE__{segments: segments}), do: segments == []

  defp measure([first | _] = run, offset) do
    {points, {_last, total}} =
      Enum.map_reduce(run, {first, offset}, fn {lat, lng, alt, _t} = point,
                                               {previous, distance} ->
        distance = distance + Privacy.distance_m(previous, point)
        {{lat, lng, alt, distance}, {point, distance}}
      end)

    {points, total}
  end

  # Every `step`-th point, always keeping a run's last.
  defp thin(points, 1), do: points

  defp thin(points, step) do
    last = List.last(points)
    kept = Enum.take_every(points, step)
    if List.last(kept) == last, do: kept, else: kept ++ [last]
  end

  @doc """
  What the map hook reads: each segment as `[lng, lat, distance_m, alt_m]`,
  coordinates rounded to about a metre.
  """
  def map_data(%__MODULE__{} = route) do
    %{
      segments:
        Enum.map(route.segments, fn segment ->
          Enum.map(segment, fn {lat, lng, alt, distance} ->
            [Float.round(lng / 1, 5), Float.round(lat / 1, 5), round(distance), alt && round(alt)]
          end)
        end),
      start: route.start?,
      finish: route.finish?
    }
  end

  @doc """
  The elevation profile as SVG paths in a `#{@profile_width}×#{@profile_height}`
  box — `line` and the filled `area` under it — with the lowest and highest
  altitude and the length it spans. Nil when the track has no altitudes.
  """
  def profile(%__MODULE__{segments: segments, length_m: length_m}) do
    alts = for segment <- segments, {_, _, alt, _} <- segment, is_number(alt), do: alt

    if alts != [] and length_m > 0 do
      {low, high} = Enum.min_max(alts)
      # A flat ride still gets a band to sit in, rather than a divide by zero.
      span = max(high - low, 10.0)

      runs =
        for segment <- segments do
          for {_, _, alt, distance} <- segment, is_number(alt) do
            {distance / length_m * @profile_width,
             @profile_height - (alt - low) / span * @profile_height * 0.9}
          end
        end
        |> Enum.reject(&(length(&1) < 2))

      %{
        width: @profile_width,
        height: @profile_height,
        line: Enum.map_join(runs, " ", &path/1),
        area: Enum.map_join(runs, " ", &area/1),
        low_m: low,
        high_m: high,
        length_m: length_m
      }
    end
  end

  defp area([{first_x, _} | _] = run) do
    {last_x, _} = List.last(run)
    path(run) <> " L#{fmt(last_x)} #{@profile_height} L#{fmt(first_x)} #{@profile_height} Z"
  end

  @doc """
  The route's outline as one SVG path in a `#{@card_width}×#{@card_height}` box, north up
  and undistorted. Nil for a route with nothing to show.
  """
  def card_path(%__MODULE__{segments: []}), do: nil

  def card_path(%__MODULE__{segments: segments}) do
    count = segments |> Enum.map(&length/1) |> Enum.sum()
    step = max(1, ceil(count / @max_card_points))

    all = List.flatten(segments)
    {min_lat, max_lat} = all |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    {min_lng, max_lng} = all |> Enum.map(&elem(&1, 1)) |> Enum.min_max()

    # Equirectangular at the route's own latitude: a degree of longitude is
    # narrower than one of latitude, by cos(lat).
    squeeze = :math.cos((min_lat + max_lat) / 2 * :math.pi() / 180)
    width = max((max_lng - min_lng) * squeeze, 1.0e-9)
    height = max(max_lat - min_lat, 1.0e-9)

    scale = min((@card_width - 2 * @card_pad) / width, (@card_height - 2 * @card_pad) / height)
    left = (@card_width - width * scale) / 2
    top = (@card_height - height * scale) / 2

    segments
    |> Enum.map(&thin(&1, step))
    |> Enum.map_join(" ", fn segment ->
      segment
      |> Enum.map(fn {lat, lng, _, _} ->
        {left + (lng - min_lng) * squeeze * scale, top + (max_lat - lat) * scale}
      end)
      |> path()
    end)
  end

  def card_box, do: "0 0 #{@card_width} #{@card_height}"

  defp path([{x, y} | rest]) do
    "M#{fmt(x)} #{fmt(y)}" <> Enum.map_join(rest, "", fn {x, y} -> " L#{fmt(x)} #{fmt(y)}" end)
  end

  defp fmt(number), do: :erlang.float_to_binary(number / 1, decimals: 1)
end
