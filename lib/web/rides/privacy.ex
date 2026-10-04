defmodule Web.Rides.Privacy do
  @moduledoc """
  Privacy zones: the parts of a recorded track that are never published.

  A zone is an address and a radius, set in `RIDE_PRIVACY_ZONES` as
  `lat,lng,radius_m` (several separated by `;`). Every point of a track that
  falls inside a zone is dropped — at the start, at the end, and anywhere the
  route passes back through — and the track is returned as the runs that are
  left.

  Three things keep the cuts from pointing back at the address:

    * **The published circle is not centred on the address.** Each zone is
      moved a fixed, secret distance in a fixed, secret direction and grown by
      the same amount, so the address is always at least `radius_m` inside the
      edge but the middle of the circle is somewhere else.
    * **A cut is not made on the circle.** Each end that meets a zone loses a
      further stretch of path, a different length per ride and per end, so the
      ends of many rides do not trace the edge.
    * **A straight line is never drawn across a zone.** Two consecutive points
      outside it whose chord crosses it (a paused recording) are split.

  Everything here is deterministic — the shift and the trims come from a hash
  of `RIDE_PRIVACY_SALT`, never from `:rand` — so a ride is cut in the same
  place on every render. A fresh cut each time would let the true edge be
  averaged out.

  A zone setting that cannot be read hides every track outright rather than
  publishing one uncut.
  """

  require Logger

  @earth_radius_m 6_371_000.0

  # The circle moves 10–35% of its radius off the address.
  @min_shift 0.10
  @shift_range 0.25

  # Each cut end loses up to this share of the radius again, along the path.
  @trim_range 0.25

  @type zone :: %{lat: float, lng: float, radius_m: float}

  @doc """
  The runs of `points` that may be published, in order. `points` are tuples
  whose first two elements are latitude and longitude; `ride_key` is anything
  stable that names the ride.

  Each run comes back as `{points, cut_start?, cut_end?}` — whether that end
  was made by a zone rather than by the recording starting or stopping there.
  """
  def redact(points, ride_key) do
    case zones() do
      {:ok, []} ->
        if points == [], do: [], else: [{points, false, false}]

      {:ok, zones} ->
        circles = Enum.map(zones, &published_circle/1)
        trim_m = zones |> Enum.map(& &1.radius_m) |> Enum.max() |> Kernel.*(@trim_range)

        points
        |> split(circles)
        |> Enum.with_index()
        |> Enum.map(fn {run, index} -> trim(run, ride_key, index, trim_m) end)
        |> Enum.reject(fn {run, _, _} -> match?([], run) or match?([_], run) end)

      :invalid ->
        []
    end
  end

  @doc """
  A fingerprint of the zones and the way they are applied. Anything derived
  from a redacted track is stored with it and discarded when it changes.
  """
  def key do
    :crypto.hash(:sha256, :erlang.term_to_binary({2, zones(), salt()}))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  @doc "The configured zones, or `:invalid` when the setting cannot be read."
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
        with [lat, lng, radius] <- zone |> String.split(",") |> Enum.map(&String.trim/1),
             {lat, ""} <- Float.parse(lat),
             {lng, ""} <- Float.parse(lng),
             {radius, ""} <- Float.parse(radius),
             true <- abs(lat) <= 90 and abs(lng) <= 180 and radius > 0 do
          %{lat: lat, lng: lng, radius_m: radius}
        else
          _ -> :invalid
        end
      end)

    if :invalid in zones do
      Logger.error(
        "RIDE_PRIVACY_ZONES is malformed — every ride track is hidden until it is fixed"
      )

      :invalid
    else
      {:ok, zones}
    end
  end

  defp salt, do: Application.get_env(:web, :ride_privacy_salt) || ""

  # The circle actually cut by: the zone moved off its address and grown by
  # the distance it moved, so the address keeps `radius_m` of cover all round.
  defp published_circle(%{lat: lat, lng: lng, radius_m: radius}) do
    {a, b} = unit_pair({"zone", lat, lng, radius})
    shift = radius * (@min_shift + @shift_range * a)
    bearing = 2 * :math.pi() * b

    dlat = shift * :math.cos(bearing) / @earth_radius_m
    dlng = shift * :math.sin(bearing) / (@earth_radius_m * :math.cos(radians(lat)))

    %{lat: lat + degrees(dlat), lng: lng + degrees(dlng), radius_m: radius + shift}
  end

  # Two numbers in [0, 1) fixed by the salt and `term`.
  defp unit_pair(term) do
    <<a::32, b::32, _::binary>> = :crypto.hash(:sha256, :erlang.term_to_binary({salt(), term}))
    {a / 4_294_967_296, b / 4_294_967_296}
  end

  # Runs of consecutive points outside every circle, each flagged with whether
  # a zone made its start and its end.
  defp split(points, circles) do
    {runs, current, cut_before?, _previous} =
      Enum.reduce(points, {[], [], false, nil}, fn point,
                                                   {runs, current, cut_before?, previous} ->
        cond do
          inside?(point, circles) ->
            {close(runs, current, cut_before?, true), [], true, nil}

          previous != nil and crosses?(previous, point, circles) ->
            {close(runs, current, cut_before?, true), [point], true, point}

          true ->
            {runs, [point | current], cut_before?, point}
        end
      end)

    runs |> close(current, cut_before?, false) |> Enum.reverse()
  end

  defp close(runs, [], _cut_start?, _cut_end?), do: runs

  defp close(runs, current, cut_start?, cut_end?),
    do: [{Enum.reverse(current), cut_start?, cut_end?} | runs]

  defp inside?(point, circles) do
    Enum.any?(circles, &(distance_m(point, &1) <= &1.radius_m))
  end

  # Whether the straight line from `a` to `b` passes through a circle, worked
  # in metres on a plane tangent at the circle's centre — exact enough at the
  # scale of a zone.
  defp crosses?(a, b, circles) do
    Enum.any?(circles, fn circle ->
      {ax, ay} = local(a, circle)
      {bx, by} = local(b, circle)
      {dx, dy} = {bx - ax, by - ay}
      length_sq = dx * dx + dy * dy

      t = if length_sq == 0.0, do: 0.0, else: -(ax * dx + ay * dy) / length_sq
      t = t |> max(0.0) |> min(1.0)

      :math.sqrt(:math.pow(ax + t * dx, 2) + :math.pow(ay + t * dy, 2)) <= circle.radius_m
    end)
  end

  defp local(point, circle) do
    {(elem(point, 1) - circle.lng)
     |> radians()
     |> Kernel.*(:math.cos(radians(circle.lat)))
     |> Kernel.*(@earth_radius_m),
     (elem(point, 0) - circle.lat) |> radians() |> Kernel.*(@earth_radius_m)}
  end

  # Takes the extra stretch off each end a zone made.
  defp trim({run, cut_start?, cut_end?}, ride_key, index, trim_m) do
    {head, tail} = unit_pair({"trim", ride_key, index})

    run = if cut_start?, do: drop_path(run, head * trim_m), else: run

    run =
      if cut_end?,
        do: run |> Enum.reverse() |> drop_path(tail * trim_m) |> Enum.reverse(),
        else: run

    {run, cut_start?, cut_end?}
  end

  defp drop_path([_first, _second | _] = run, metres) when metres > 0 do
    [first, second | _] = run
    step = distance_m(first, second)
    if step <= metres, do: drop_path(tl(run), metres - step), else: run
  end

  defp drop_path(run, _metres), do: run

  @doc "Great-circle distance in metres between two points or zones."
  def distance_m(a, b) do
    {lat1, lng1} = lat_lng(a)
    {lat2, lng2} = lat_lng(b)
    dlat = radians(lat2 - lat1)
    dlng = radians(lng2 - lng1)

    h =
      :math.pow(:math.sin(dlat / 2), 2) +
        :math.cos(radians(lat1)) * :math.cos(radians(lat2)) * :math.pow(:math.sin(dlng / 2), 2)

    2 * @earth_radius_m * :math.asin(min(1.0, :math.sqrt(h)))
  end

  defp lat_lng(%{lat: lat, lng: lng}), do: {lat, lng}
  defp lat_lng(point) when is_tuple(point), do: {elem(point, 0), elem(point, 1)}

  defp radians(degrees), do: degrees * :math.pi() / 180
  defp degrees(radians), do: radians * 180 / :math.pi()
end
