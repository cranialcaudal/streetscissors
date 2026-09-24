defmodule Web.Rides do
  @moduledoc """
  The ride archive: every tour recorded on Komoot, mirrored by
  `Web.Rides.KomootSync`. Komoot is the only input and the only place a ride
  is edited — recording, renaming, re-routing, or deleting a tour in the app
  is what changes it here.

  The one thing Komoot doesn't keep is what the watch measured: heart rate
  and energy go to Apple Health instead. Those arrive as `Web.Rides.Workout`s
  from Health Auto Export and are paired with rides by start time when read.
  """

  import Ecto.Query, warn: false
  alias Web.Repo
  alias Web.Rides.{AppleHealth, Ride, Thumbs, Workout}

  # 0.2 mi. Anything shorter is a false start — the app left recording in a
  # pocket — and never reaches the site: not listed, not totaled, no page.
  @min_distance_m 321.8688

  # How far apart a tour's start and a workout's start may be and still be
  # one outing. The Komoot watch app starts both at once, so real pairs sit
  # seconds apart; ten minutes forgives a clock, not a second ride.
  @health_window_s 600

  @komoot "https://www.komoot.com"

  @doc "Every activity of at least 0.2 mi, newest first, with its health attached."
  def list_rides do
    Repo.all(from r in listed(), order_by: [desc: r.started_at]) |> attach_health()
  end

  @doc "A listed activity by id, or nil — safe to call with an id straight from a URL."
  def get_ride(id) when is_integer(id), do: listed() |> Repo.get(id) |> attach_health()

  def get_ride(id) when is_binary(id) do
    if id =~ ~r/^\d+$/, do: listed() |> Repo.get(id) |> attach_health()
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
  Komoot's embed for a tour — its live map, stats and elevation profile — or
  nil for a private tour whose share token hasn't arrived yet, which the
  embed would only answer with its "is private" page.
  """
  def embed_url(%Ride{} = ride) do
    if query = komoot_query(ride) do
      "#{@komoot}/tour/#{ride.komoot_id}/embed?" <> URI.encode_query(query ++ [profile: 1])
    end
  end

  @doc "The tour's own page on Komoot, or nil when a visitor couldn't open it."
  def tour_url(%Ride{} = ride) do
    case komoot_query(ride) do
      nil -> nil
      [] -> "#{@komoot}/tour/#{ride.komoot_id}"
      query -> "#{@komoot}/tour/#{ride.komoot_id}?" <> URI.encode_query(query)
    end
  end

  defp komoot_query(%Ride{visibility: "public"}), do: []
  defp komoot_query(%Ride{share_token: token}) when is_binary(token), do: [share_token: token]
  defp komoot_query(_ride), do: nil

  @doc """
  Stores Health Auto Export workouts, updating any already stored (the
  export repeats itself, and HealthKit's id keeps that idempotent). A
  workout that can't be read is skipped rather than failing the batch.
  Returns how many were stored.
  """
  def ingest_workouts(workouts) when is_list(workouts) do
    Enum.count(workouts, fn raw ->
      with {:ok, attrs} <- AppleHealth.workout_attrs(raw),
           {:ok, _workout} <- upsert_workout(attrs) do
        true
      else
        _ -> false
      end
    end)
  end

  def ingest_workouts(_workouts), do: 0

  defp upsert_workout(attrs) do
    %Workout{}
    |> Workout.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :hk_id, :inserted_at]},
      conflict_target: :hk_id
    )
  end

  @doc "How many Apple Health workouts have arrived, matched to a ride or not."
  def count_workouts, do: Repo.aggregate(Workout, :count)

  @doc """
  Fills each ride's virtual `health` with the Apple Health workout that
  started nearest to it, within #{div(@health_window_s, 60)} minutes, or nil.
  One query for the whole list. Takes a list of rides, a ride, or nil.
  """
  def attach_health(nil), do: nil
  def attach_health(%Ride{} = ride), do: hd(attach_health([ride]))
  def attach_health([]), do: []

  def attach_health(rides) when is_list(rides) do
    {earliest, latest} = rides |> Enum.map(&DateTime.to_unix(&1.started_at)) |> Enum.min_max()
    from = DateTime.from_unix!(earliest - @health_window_s)
    to = DateTime.from_unix!(latest + @health_window_s)

    workouts =
      Repo.all(from w in Workout, where: w.started_at >= ^from and w.started_at <= ^to)

    Enum.map(rides, &%{&1 | health: nearest_workout(workouts, &1.started_at)})
  end

  defp nearest_workout(workouts, started_at) do
    workouts
    |> Enum.map(&{abs(DateTime.diff(&1.started_at, started_at)), &1})
    |> Enum.filter(fn {gap, _workout} -> gap <= @health_window_s end)
    |> Enum.min_by(fn {gap, _workout} -> gap end, fn -> {nil, nil} end)
    |> elem(1)
  end

  @doc "Removes a ride and its cached thumbnail."
  def delete_ride(%Ride{} = ride) do
    Thumbs.delete(ride)
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
