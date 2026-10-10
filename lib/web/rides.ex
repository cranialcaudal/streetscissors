defmodule Web.Rides do
  @moduledoc """
  The ride archive: every tour recorded on Komoot, mirrored by
  `Web.Rides.KomootSync`. Komoot is the only input and the only place a ride
  is edited — recording, renaming, re-routing, or deleting a tour in the app
  is what changes it here — and Komoot draws it: the pages show its embed.

  The one thing Komoot doesn't keep is what the watch measured. Heart rate
  and energy go to Apple Health instead, and arrive here as
  `Web.Rides.Workout`s (`Web.Rides.AppleHealth`), paired with rides by start
  time when read.
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

  @doc "The pairing window, in seconds, for whoever needs to pre-select workouts by it."
  def health_window_s, do: @health_window_s

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

  # --- What Komoot draws ------------------------------------------------------

  @doc """
  True when Komoot's own rendering of the tour may be shown: the sync has
  read it the way a stranger is given it and found it clear. Not an exposed
  tour or one that passes a private place mid-tour (`Web.Rides.Privacy`),
  not one Komoot hides from strangers altogether, and not one that has yet
  to be looked at.
  """
  def clear?(%Ride{stranger_view: view}), do: view == "clear"

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

  # --- What the watch measured ------------------------------------------------

  @doc """
  Stores workouts, updating any already stored (an export repeats itself, and
  `hk_id` keeps that idempotent). Each is a map of `Web.Rides.Workout`
  attributes; one that won't validate is skipped rather than failing the
  batch. Returns how many were stored.
  """
  def store_workouts(workouts) when is_list(workouts) do
    Enum.count(workouts, fn attrs -> match?({:ok, _workout}, upsert_workout(attrs)) end)
  end

  defp upsert_workout(attrs) do
    %Workout{}
    |> Workout.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace_all_except, [:id, :hk_id, :inserted_at]},
      conflict_target: :hk_id
    )
  end

  @doc """
  Reads an Apple Health export (`Web.Rides.AppleHealth.Export`) and stores
  the workouts in it that belong to a ride on file. Returns
  `{:ok, %{in_export, matched, stored, heart_samples}}` or `{:error, reason}`.

  Every ride is offered for pairing, false starts included: whether a ride
  is long enough to list is a question for the page, not for the import.
  """
  def import_health_export(path) do
    rides =
      Repo.all(from r in Ride, select: %{started_at: r.started_at, duration_s: r.duration_s})

    with {:ok, read} <- AppleHealth.Export.read(path, rides, @health_window_s) do
      {:ok,
       %{
         in_export: read.in_export,
         matched: length(read.workouts),
         stored: store_workouts(read.workouts),
         heart_samples: read.heart_samples
       }}
    end
  end

  @doc "How many Apple Health workouts are on file, matched to a ride or not."
  def count_workouts, do: Repo.aggregate(Workout, :count)

  @doc """
  The highest heart rate any workout on file reached, or nil without one. The
  heart-rate zones on a ride's page are shares of this: the site is told
  nobody's age, so the ceiling it measures against is the one the watch has
  actually seen.
  """
  def heart_rate_ceiling, do: Repo.aggregate(Workout, :max, :max_hr)

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
  What a set of rides adds up to:

      %{rides, distance_m, moving_s, ascent_m,   # Komoot's, for every ride
        measured, active_kcal, avg_hr, max_hr}    # the watch's, where it has them

  `measured` is how many of the rides have a workout paired with them, so a
  page can say "from 9 of 12" rather than pass a partial sum off as the
  whole. `avg_hr` is weighted by each workout's length; it and the other
  watch figures are nil when no ride in the set was measured.
  """
  def totals(rides) do
    measured = for %Ride{health: %Workout{} = workout} = ride <- rides, do: {ride, workout}

    %{
      rides: length(rides),
      distance_m: sum(rides, &(&1.distance_m || 0.0)),
      moving_s: sum(rides, &moving_s/1),
      ascent_m: sum(rides, &(&1.ascent_m || 0.0)),
      measured: length(measured),
      active_kcal: sum_present(measured, fn {_ride, workout} -> workout.active_kcal end),
      avg_hr: weighted_heart_rate(measured),
      max_hr:
        measured
        |> Enum.map(fn {_ride, workout} -> workout.max_hr end)
        |> Enum.reject(&is_nil/1)
        |> Enum.max(fn -> nil end)
    }
  end

  defp moving_s(ride), do: ride.time_in_motion_s || ride.duration_s || 0

  defp sum(items, value), do: items |> Enum.map(value) |> Enum.sum()

  defp sum_present(items, value) do
    case items |> Enum.map(value) |> Enum.reject(&is_nil/1) do
      [] -> nil
      values -> Enum.sum(values)
    end
  end

  # An hour at 150 and ten minutes at 100 average nearer 150 than 125.
  defp weighted_heart_rate(measured) do
    weighted =
      for {ride, %Workout{avg_hr: avg} = workout} <- measured, is_integer(avg) do
        seconds = Workout.duration_s(workout) || moving_s(ride)
        {avg * max(seconds, 1), max(seconds, 1)}
      end

    case weighted do
      [] ->
        nil

      pairs ->
        round(Enum.sum(Enum.map(pairs, &elem(&1, 0))) / Enum.sum(Enum.map(pairs, &elem(&1, 1))))
    end
  end
end
