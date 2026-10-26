defmodule Web.Rides.Profile do
  @moduledoc """
  A tour's speed and climb, without where it went: for each point of the
  route Komoot gives a stranger, the seconds since the start, the metres
  covered and the altitude. No latitude or longitude is kept, so the profile
  cannot place the ride on a map; it only says how fast and how steep.

  It comes from the same stranger's read that decides whether a tour may be
  shown (`Web.Rides.Privacy`), so Komoot's privacy zones have already trimmed
  its ends. `analysis/ride_power.R` estimates a ride's power from it.

  Stored as `%{"t" => [s], "d" => [m], "alt" => [m]}`, three lists of the
  same length; `%{}` when Komoot's points carry no time or altitude, so that
  a tour is not read again for a profile it cannot give.
  """

  @earth 6_371_008.8

  @doc "The profile of a stranger's points (Komoot's `coordinates.items`)."
  def from_points(items) when is_list(items) do
    points =
      for %{"lat" => lat, "lng" => lng, "alt" => alt, "t" => t} <- items,
          Enum.all?([lat, lng, alt, t], &is_number/1),
          do: {lat / 1, lng / 1, alt / 1, t / 1000}

    case points do
      [_, _ | _] ->
        {_, ds} =
          Enum.reduce(tl(points), {hd(points), [0.0]}, fn p, {prev, [d | _] = acc} ->
            {p, [d + metres(prev, p) | acc]}
          end)

        %{
          "t" => Enum.map(points, fn {_, _, _, t} -> round(t) end),
          "d" => ds |> Enum.reverse() |> Enum.map(&Float.round(&1, 1)),
          "alt" => Enum.map(points, fn {_, _, alt, _} -> Float.round(alt, 1) end)
        }

      _ ->
        %{}
    end
  end

  def from_points(_), do: %{}

  # The great-circle distance between two points, in metres.
  defp metres({lat1, lng1, _, _}, {lat2, lng2, _, _}) do
    rad = :math.pi() / 180
    dlat = (lat2 - lat1) * rad
    dlng = (lng2 - lng1) * rad

    a =
      :math.pow(:math.sin(dlat / 2), 2) +
        :math.cos(lat1 * rad) * :math.cos(lat2 * rad) * :math.pow(:math.sin(dlng / 2), 2)

    2 * @earth * :math.asin(min(1.0, :math.sqrt(a)))
  end
end
