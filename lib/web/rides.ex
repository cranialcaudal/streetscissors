defmodule Web.Rides do
  @moduledoc """
  The ride archive: every tour recorded on Komoot, mirrored by
  `Web.Rides.KomootSync`.

  Komoot is the only input and the only place a ride is edited — recording,
  renaming, re-routing, or deleting a tour in the app is what changes it here —
  and Komoot draws it: the pages show its embed.
  """

  import Ecto.Query, warn: false
  alias Web.Repo
  alias Web.Rides.{Ride, Thumbs}

  # 0.2 mi. Anything shorter is a false start — the app left recording in a
  # pocket — and never reaches the site: not listed, not totaled, no page.
  @min_distance_m 321.8688

  @komoot "https://www.komoot.com"

  @doc "Every activity of at least 0.2 mi, newest first."
  def list_rides do
    Repo.all(from r in listed(), order_by: [desc: r.started_at])
  end

  @doc "A listed activity by id, or nil — safe to call with an id straight from a URL."
  def get_ride(id) when is_integer(id), do: Repo.get(listed(), id)

  def get_ride(id) when is_binary(id) do
    if id =~ ~r/^\d+$/, do: Repo.get(listed(), id)
  end

  def get_ride(_id), do: nil

  # A NULL distance fails the comparison too, so an activity Komoot sent no
  # distance for stays off the site with the false starts.
  defp listed, do: from(r in Ride, where: r.distance_m >= ^@min_distance_m)

  @doc """
  Every ride keyed by Komoot tour id, false starts included — the sync's
  insert/update/delete dispatch has to see the whole archive.
  """
  def komoot_index do
    Map.new(Repo.all(Ride), &{&1.komoot_id, &1})
  end

  def create_ride(attrs) do
    %Ride{} |> Ride.changeset(attrs) |> Repo.insert()
  end

  def update_ride(%Ride{} = ride, attrs) do
    ride |> Ride.changeset(attrs) |> Repo.update()
  end

  # --- What Komoot draws ------------------------------------------------------

  @doc """
  True when Komoot's own rendering of the tour may be shown: the sync has
  read it the way a stranger is given it and found it clear. Not an exposed
  tour or one that passes a private place mid-tour (`Web.Rides.Privacy`),
  not one Komoot hides from strangers altogether, and not one that has yet
  to be looked at.
  """
  def clear?(%Ride{stranger_view: view}), do: view == "clear"

  # Komoot's sports a person pedals: no e-bike, whose motor no estimate of
  # the rider's power can see past.
  @pedalled ~w(racebike touringbicycle mtb mtb_easy mtb_advanced downhillbike)

  @doc "Whether a ride was on a bike with no motor, the rides power is estimated for."
  def pedalled?(%Ride{sport: sport}), do: sport in @pedalled

  @doc "Whether a ride has yet to be given a profile by a stranger's read."
  def needs_profile?(%Ride{id: id}),
    do: Repo.exists?(from r in Ride, where: r.id == ^id and is_nil(r.profile))

  @doc """
  Komoot's embed for a tour — its live map, stats, elevation profile and
  photographs — or nil when there is nothing safe or possible to embed: a
  tour that is not clear (`clear?/1`), or a private one with no share token,
  which the embed would only answer with its "is private" page.
  """
  def embed_url(%Ride{} = ride) do
    if query = komoot_query(ride) do
      "#{@komoot}/tour/#{ride.komoot_id}/embed?" <>
        URI.encode_query(query ++ [profile: 1, gallery: 1])
    end
  end

  @doc "The tour's own page on Komoot, or nil when a visitor couldn't or shouldn't open it."
  def tour_url(%Ride{} = ride) do
    case komoot_query(ride) do
      nil -> nil
      [] -> "#{@komoot}/tour/#{ride.komoot_id}"
      query -> "#{@komoot}/tour/#{ride.komoot_id}?" <> URI.encode_query(query)
    end
  end

  defp komoot_query(%Ride{stranger_view: "clear", visibility: "public"}), do: []

  defp komoot_query(%Ride{stranger_view: "clear", share_token: token}) when is_binary(token),
    do: [share_token: token]

  defp komoot_query(_ride), do: nil

  @doc "True when the ride's cached route image may be shown: the ride is clear, and there is one."
  def thumb?(%Ride{} = ride), do: clear?(ride) and Thumbs.exists?(ride)

  @doc """
  The address of the ride's cached route image, or nil when there is none to
  show. It carries the fingerprint of the map the picture was drawn from, so
  a route Komoot re-cut is a new address rather than the old picture out of
  somebody's cache.
  """
  def thumb_src(%Ride{} = ride) do
    if thumb?(ride) do
      "/fitness/rides/#{ride.id}/thumb?v=#{Thumbs.fingerprint(ride.map_image_url)}"
    end
  end

  @doc """
  The listed rides whose route, as a stranger is shown it, begins or ends at
  a private place: the ones Komoot's zone is failing to trim.
  """
  def exposed, do: Repo.all(from r in listed(), where: r.stranger_view == "exposed")

  @doc """
  How many listed rides are in each state of `stranger_view`, as a map:
  `%{"clear" => 61, "passing" => 2, nil => 1}`.
  """
  def stranger_views do
    Map.new(
      Repo.all(
        from r in listed(), group_by: r.stranger_view, select: {r.stranger_view, count(r.id)}
      )
    )
  end

  @doc "Removes a ride and its cached thumbnail."
  def delete_ride(%Ride{} = ride) do
    Thumbs.delete(ride)
    Repo.delete(ride)
  end

  # --- Reading the archive ----------------------------------------------------

  @doc """
  One shelf per sport: `[{sport, rides}]`, the largest shelf first, ties going
  to the sport done most recently. Takes rides newest first, as
  `list_rides/0` returns them, and keeps each shelf in that order.
  """
  def shelves(rides) do
    rides
    |> Enum.group_by(& &1.sport)
    |> Enum.sort_by(fn {_sport, [newest | _] = rides} ->
      {-length(rides), -DateTime.to_unix(newest.started_at)}
    end)
  end

  @doc """
  Totals for each calendar year, newest first — the fields of `totals/1` plus
  `year`.

  Years are Pacific-local (via `Web.Clock`), so a New Year's Eve ride counts
  toward the year it was ridden in rather than the UTC year it ended in.
  """
  def yearly_totals(rides) do
    rides
    |> Enum.group_by(&Web.Clock.local_today(&1.started_at).year)
    |> Enum.map(fn {year, rides} -> Map.put(totals(rides), :year, year) end)
    |> Enum.sort_by(& &1.year, :desc)
  end

  @doc """
  The activities of the last `days` days, counting today, summed by
  `totals/1`. Days are Pacific-local, like everything else dated here.
  """
  def recent(rides, days, today \\ Web.Clock.local_today()) do
    since = Date.add(today, -(days - 1))

    rides
    |> Enum.filter(fn ride ->
      day = Web.Clock.local_today(ride.started_at)
      Date.compare(day, since) != :lt and Date.compare(day, today) != :gt
    end)
    |> totals()
  end

  @doc """
  What a set of rides adds up to: `%{rides, distance_m, moving_s, ascent_m}`.
  """
  def totals(rides) do
    %{
      rides: length(rides),
      distance_m: sum(rides, &(&1.distance_m || 0.0)),
      moving_s: sum(rides, &moving_s/1),
      ascent_m: sum(rides, &(&1.ascent_m || 0.0))
    }
  end

  defp moving_s(ride), do: ride.time_in_motion_s || ride.duration_s || 0

  defp sum(items, value), do: items |> Enum.map(value) |> Enum.sum()
end
