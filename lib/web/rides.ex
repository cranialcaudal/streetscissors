defmodule Web.Rides do
  @moduledoc """
  The ride archive: rides imported from Komoot (auto-sync or manual GPX
  upload), split into recorded rides and planned routes.

  Privacy rule: points inside a configured privacy zone are stored raw but
  filtered out of every public egress — `list_points/2` defaults to
  `public: true`. Admin callers must explicitly pass `public: false` to see
  everything.
  """

  import Ecto.Query, warn: false
  alias Web.Repo
  alias Web.Rides.{Ride, RidePoint, Privacy, Stats, GPX, Thumbs}

  @insert_chunk 500

  ## Rides

  def get_ride!(id), do: Repo.get!(Ride, id)

  @doc "Fetches a ride only when publicly visible; nil for private or unknown ids."
  def get_public_ride(id) do
    case Repo.get(Ride, id) do
      %Ride{visibility: "private"} -> nil
      ride -> ride
    end
  end

  @doc """
  Recorded rides, newest first. `public: true` (the default) hides rides
  whose Komoot tour is private; admin callers pass `public: false`.
  """
  def list_recorded_rides(opts \\ []) do
    from(r in Ride, where: r.kind == "recorded", order_by: [desc: r.started_at])
    |> visible(opts)
    |> Repo.all()
  end

  @doc "The most recent publicly visible recorded ride, or nil."
  def latest_recorded_ride do
    from(r in Ride,
      where: r.kind == "recorded" and r.visibility != "private",
      order_by: [desc: r.started_at],
      limit: 1
    )
    |> Repo.one()
  end

  def list_planned_rides(opts \\ []) do
    from(r in Ride, where: r.kind == "planned", order_by: [desc: r.started_at])
    |> visible(opts)
    |> Repo.all()
  end

  defp visible(query, opts) do
    if Keyword.get(opts, :public, true) do
      from(r in query, where: r.visibility != "private")
    else
      query
    end
  end

  def update_ride(%Ride{} = ride, attrs) do
    ride |> Ride.changeset(attrs) |> Repo.update()
  end

  @doc """
  Applies non-nil overrides outside the changeset cast whitelist — used by
  the Komoot sync to write API-sourced stats over the locally computed ones.
  """
  def override_stats(%Ride{} = ride, overrides) do
    changes = Enum.reject(overrides, fn {_key, value} -> is_nil(value) end)

    case changes do
      [] -> {:ok, ride}
      changes -> ride |> Ecto.Changeset.change(changes) |> Repo.update()
    end
  end

  def delete_ride(%Ride{} = ride) do
    Thumbs.delete(ride)
    Repo.delete(ride)
  end

  @doc "Set of komoot tour ids already imported — used by the sync for idempotency."
  def known_komoot_ids do
    from(r in Ride, where: not is_nil(r.komoot_id), select: r.komoot_id)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Distance/time/ascent totals for public recorded rides over calendar
  windows (Pacific-local via `Web.Clock`): this week, this month, this
  year, plus per-sport totals for the year.
  """
  def aggregate_stats do
    today = Web.Clock.local_today()
    week_start = to_utc(Date.beginning_of_week(today))
    month_start = to_utc(Date.beginning_of_month(today))
    year_start = to_utc(Date.new!(today.year, 1, 1))

    %{
      week: period_stats(week_start),
      month: period_stats(month_start),
      year: period_stats(year_start),
      by_sport: sport_stats(year_start)
    }
  end

  defp to_utc(date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  defp period_stats(since) do
    from(r in Ride,
      where: r.kind == "recorded" and r.visibility != "private" and r.started_at >= ^since,
      select: %{
        rides: count(r.id),
        distance_m: coalesce(sum(r.distance_m), 0.0),
        duration_s: coalesce(sum(coalesce(r.time_in_motion_s, r.duration_s)), 0),
        ascent_m: coalesce(sum(r.ascent_m), 0.0)
      }
    )
    |> Repo.one()
  end

  defp sport_stats(since) do
    from(r in Ride,
      where: r.kind == "recorded" and r.visibility != "private" and r.started_at >= ^since,
      group_by: r.sport,
      select: %{
        sport: r.sport,
        rides: count(r.id),
        distance_m: coalesce(sum(r.distance_m), 0.0)
      },
      order_by: [desc: sum(r.distance_m)]
    )
    |> Repo.all()
  end

  @doc "Imported komoot rides keyed by tour id — the sync's insert/update dispatch."
  def komoot_index do
    from(r in Ride, where: not is_nil(r.komoot_id))
    |> Repo.all()
    |> Map.new(&{&1.komoot_id, &1})
  end

  @doc """
  Attaches a Komoot tour to an existing ride so its embed renders on the
  detail page. Accepts a full tour URL or a bare numeric id.
  """
  def attach_komoot(%Ride{} = ride, url_or_id) do
    case parse_komoot_id(url_or_id) do
      nil -> {:error, :invalid_komoot_id}
      id -> update_ride(ride, %{"komoot_id" => id})
    end
  end

  defp parse_komoot_id(value) do
    value = String.trim(to_string(value))

    cond do
      value =~ ~r/^\d+$/ -> value
      match = Regex.run(~r{komoot\.[a-z.]+/tour/(\d+)}, value) -> Enum.at(match, 1)
      true -> nil
    end
  end

  ## Points

  @doc """
  Ordered points for a ride. `public: true` (the default) applies the
  privacy-zone filter; admin reads pass `public: false`.
  """
  def list_points(%Ride{} = ride, opts \\ []) do
    points =
      from(p in RidePoint, where: p.ride_id == ^ride.id, order_by: p.recorded_at)
      |> Repo.all()

    if Keyword.get(opts, :public, true), do: Privacy.filter(points), else: points
  end

  ## Imports

  @doc """
  Creates a ride from a GPX file's contents. Files without timestamps still
  import (distance/elevation stats only).
  """
  def import_gpx(xml, attrs \\ %{}) do
    with {:ok, points, has_time?} <- GPX.parse(xml) do
      create_imported_ride(points, attrs, has_time?: has_time?)
    end
  end

  @doc """
  Creates a ride from a list of point maps (`lat`, `lon`, `recorded_at`,
  optional `altitude_m`/`speed_mps`/`accuracy_m`).

  Options:

    * `:has_time?` — whether `recorded_at` values are real timestamps;
      duration and speed stats are skipped otherwise (default `true`)
    * `:kind` — `"recorded"` or `"planned"`; planned routes never get
      duration/speed stats (default `"recorded"`)
    * `:overrides` — map of stat fields whose non-nil values win over the
      locally computed ones (API-sourced stats from the Komoot sync)
  """
  def create_imported_ride(points, attrs \\ %{}, opts \\ []) do
    kind = Keyword.get(opts, :kind, "recorded")
    timed? = Keyword.get(opts, :has_time?, true) and kind == "recorded"
    overrides = Keyword.get(opts, :overrides, %{})

    result =
      %Ride{}
      |> Ride.changeset(attrs)
      |> Ecto.Changeset.put_change(:kind, kind)
      |> Repo.insert()

    with {:ok, ride} <- result do
      points
      |> Enum.uniq_by(& &1.recorded_at)
      |> Enum.map(&Map.put(&1, :ride_id, ride.id))
      |> Enum.chunk_every(@insert_chunk)
      |> Enum.each(&Repo.insert_all(RidePoint, &1, on_conflict: :nothing))

      stored = list_points(ride, public: false)
      stats = Stats.compute(stored)

      with {:ok, ride} <-
             ride
             |> Ecto.Changeset.change(
               started_at: ride.started_at || if(timed?, do: List.first(stored).recorded_at),
               ended_at: if(timed?, do: List.last(stored).recorded_at),
               point_count: length(stored),
               distance_m: stats.distance_m,
               ascent_m: stats.ascent_m,
               descent_m: stats.descent_m,
               duration_s: if(timed?, do: stats.duration_s),
               avg_speed_mps: if(timed?, do: stats.avg_speed_mps),
               max_speed_mps: if(timed?, do: stats.max_speed_mps)
             )
             |> Repo.update() do
        override_stats(ride, overrides)
      end
    end
  end
end
