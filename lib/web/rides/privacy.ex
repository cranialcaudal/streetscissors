defmodule Web.Rides.Privacy do
  @moduledoc """
  A tripwire on what Komoot shows of a tour. It cuts nothing; it checks.

  Komoot draws the activities now — its embed, its tour page, its static map
  — and Komoot hides home: a privacy zone set in the Komoot app removes every
  point inside it from what anyone but the owner is given. That is the whole
  of the protection, and it lives on somebody else's server. A zone deleted by
  a slip of the thumb, or a change in how Komoot applies one, would put the
  front door back on a public page with nothing here to notice.

  So the site keeps its own note of the places that must not show
  (`RIDE_PRIVACY_ZONES`, in `.env` and never in code) and, each time the sync
  reads a tour the way a stranger would (`Web.Komoot.Client.public_tour/2`),
  asks where the answer comes within 100 metres of one of those places.
  `verdict/1` gives one of three:

    * **`:exposed`** — the route a stranger is shown *begins or ends* there.
      A zone that is doing its job trims exactly that, so this means it is
      not: the zone is gone, moved, or no longer applied. The overview
      reports it and the monitor mails it.
    * **`:passing`** — the ends are trimmed, and the route comes back within
      100 metres somewhere between them. **A zone trims where a tour starts
      and ends, and nothing else**, so a ride that comes home, stops, and
      goes out again is handed to a stranger with the middle of it whole,
      door included. This is ordinary use, not a fault, and nothing is
      mailed; the tour is held back all the same, until it is split or
      trimmed in the app.
    * **`:clear`** — it never comes that close.

  Only a clear tour is shown through Komoot. The other two keep their figures
  and lose everything Komoot would draw for them — no embed, no map image,
  no link to the tour — until a later read comes back clear.

  The distance is deliberately short. Komoot's zones are irregular shapes a
  few hundred metres across, and the nearest point a stranger is shown of a
  tour that starts at home has measured 500–600 m from it; the wire is far
  inside that, so it trips on a zone that is not there rather than on the
  edge of one that is.

  A zone is `lat,lng` — a third number, the radius the site used to cut by
  when it drew its own maps, is still accepted and no longer used. Several
  are separated by `;`. With none set nothing is checked: Komoot is trusted
  as it stands. A setting that cannot be read makes every tour exposed
  rather than waving them all through unchecked.
  """

  @earth_radius_m 6_371_000.0
  @tripwire_m 100

  @type zone :: {float, float}

  @doc "How close a stranger's view may come to a private place before it trips, in metres."
  def tripwire_m, do: @tripwire_m

  @type verdict :: :clear | :passing | :exposed

  @doc """
  What `points` — a stranger's view of a tour, as `{lat, lng}` tuples in the
  order they were ridden — shows of the private places: `:exposed` when it
  begins or ends within the tripwire of one (or the places cannot be read at
  all), `:passing` when only somewhere between its ends does, `:clear`
  otherwise.
  """
  @spec verdict([{number, number}]) :: verdict
  def verdict(points) do
    case zones() do
      {:ok, []} -> :clear
      {:ok, zones} -> judge(points, &Enum.any?(zones, fn zone -> near?(zone, &1) end))
      :invalid -> :exposed
    end
  end

  defp judge([], _near?), do: :clear

  defp judge(points, near?) do
    cond do
      near?.(hd(points)) or near?.(List.last(points)) -> :exposed
      Enum.any?(points, near?) -> :passing
      true -> :clear
    end
  end

  @doc "The private places configured, or `:invalid` when the setting cannot be read."
  @spec zones() :: {:ok, [zone]} | :invalid
  def zones do
    case Application.get_env(:web, :ride_privacy_zones) do
      nil -> {:ok, []}
      "" -> {:ok, []}
      spec when is_binary(spec) -> parse(spec)
      _ -> :invalid
    end
  end

  defp parse(spec) do
    zones =
      spec
      |> String.split(";", trim: true)
      |> Enum.map(fn zone ->
        with [lat, lng | rest] when length(rest) <= 1 <-
               zone |> String.split(",") |> Enum.map(&String.trim/1),
             {lat, ""} <- Float.parse(lat),
             {lng, ""} <- Float.parse(lng),
             true <- abs(lat) <= 90 and abs(lng) <= 180 do
          {lat, lng}
        else
          _ -> :invalid
        end
      end)

    if :invalid in zones, do: :invalid, else: {:ok, zones}
  end

  defp near?(zone, {lat, lng}), do: distance_m(zone, {lat, lng}) < @tripwire_m

  @doc "Great-circle distance between two `{lat, lng}` points, in metres."
  def distance_m({lat1, lng1}, {lat2, lng2}) do
    phi1 = radians(lat1)
    phi2 = radians(lat2)
    d_phi = radians(lat2 - lat1)
    d_lambda = radians(lng2 - lng1)

    a =
      :math.sin(d_phi / 2) ** 2 +
        :math.cos(phi1) * :math.cos(phi2) * :math.sin(d_lambda / 2) ** 2

    2 * @earth_radius_m * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
  end

  defp radians(degrees), do: degrees * :math.pi() / 180
end
