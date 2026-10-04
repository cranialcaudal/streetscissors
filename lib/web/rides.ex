defmodule Web.Rides do
  @moduledoc """
  The ride archive: every tour recorded on Komoot, mirrored by
  `Web.Rides.KomootSync`. Komoot is the only input and the only place a ride
  is edited — recording, renaming, re-routing, or deleting a tour in the app
  is what changes it here.
  """

  import Ecto.Query, warn: false
  alias Web.Repo
  alias Web.Rides.{Privacy, Ride, Route, Track}

  # 0.2 mi. Anything shorter is a false start — the app left recording in a
  # pocket — and never reaches the site: not listed, not totaled, no page.
  @min_distance_m 321.8688

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

  @doc """
  Stores the track Komoot recorded for a ride, replacing any earlier one, and
  redraws the ride's card outline from it.
  """
  def store_track(%Ride{} = ride, points) when is_list(points) do
    track = Repo.get_by(Track, ride_id: ride.id) || %Track{}

    with {:ok, _track} <-
           track
           |> Track.changeset(%{ride_id: ride.id, points: Track.encode(points)})
           |> Repo.insert_or_update() do
      draw_route(ride, points)
    end
  end

  @doc "The ids of the rides whose track has been stored."
  def tracked_ride_ids do
    MapSet.new(Repo.all(from t in Track, select: t.ride_id))
  end

  @doc """
  The published route of a ride — its track with the privacy zones cut out —
  or nil when no track has been stored for it yet.
  """
  def route(%Ride{} = ride) do
    case Repo.get_by(Track, ride_id: ride.id) do
      nil -> nil
      track -> Route.build(Track.decode(track.points), ride.komoot_id)
    end
  end

  @doc """
  The ride's outline for a card, or nil when there is none or when the stored
  one was cut by zones other than the current ones.
  """
  def card_path(%Ride{route_path: path, route_key: key}) when is_binary(path) do
    if key == Privacy.key(), do: path
  end

  def card_path(_ride), do: nil

  @doc """
  Redraws the card outline of every ride whose stored one was cut by zones
  other than the current ones. Returns how many were redrawn.
  """
  def refresh_routes do
    key = Privacy.key()

    stale =
      Repo.all(
        from r in Ride,
          join: t in Track,
          on: t.ride_id == r.id,
          where: is_nil(r.route_key) or r.route_key != ^key,
          select: {r, t.points}
      )

    Enum.each(stale, fn {ride, points} -> draw_route(ride, Track.decode(points)) end)
    length(stale)
  end

  defp draw_route(ride, points) do
    route = Route.build(points, ride.komoot_id)
    update_ride(ride, %{route_path: Route.card_path(route), route_key: Privacy.key()})
  end

  @doc "Removes a ride and its track."
  def delete_ride(%Ride{} = ride) do
    Repo.delete_all(from t in Track, where: t.ride_id == ^ride.id)
    Repo.delete(ride)
  end

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
  Totals for each calendar year, newest first:
  `%{year, rides, distance_m, moving_s, ascent_m}`.

  Years are Pacific-local (via `Web.Clock`), so a New Year's Eve ride counts
  toward the year it was ridden in rather than the UTC year it ended in.
  """
  def yearly_totals(rides) do
    rides
    |> Enum.group_by(&Web.Clock.local_today(&1.started_at).year)
    |> Enum.map(fn {year, rides} ->
      %{
        year: year,
        rides: length(rides),
        distance_m: sum(rides, &(&1.distance_m || 0.0)),
        moving_s: sum(rides, &(&1.time_in_motion_s || &1.duration_s || 0)),
        ascent_m: sum(rides, &(&1.ascent_m || 0.0))
      }
    end)
    |> Enum.sort_by(& &1.year, :desc)
  end

  defp sum(rides, value), do: rides |> Enum.map(value) |> Enum.sum()
end
