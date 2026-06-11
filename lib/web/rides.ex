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
  alias Web.Rides.{Ride, RidePoint, Privacy, Stats, GPX}

  @insert_chunk 500

  ## Rides

  def get_ride!(id), do: Repo.get!(Ride, id)

  def list_recorded_rides do
    from(r in Ride, where: r.kind == "recorded", order_by: [desc: r.started_at])
    |> Repo.all()
  end

  def list_planned_rides do
    from(r in Ride, where: r.kind == "planned", order_by: [desc: r.started_at])
    |> Repo.all()
  end

  def update_ride(%Ride{} = ride, attrs) do
    ride |> Ride.changeset(attrs) |> Repo.update()
  end

  def delete_ride(%Ride{} = ride), do: Repo.delete(ride)

  @doc "Set of komoot tour ids already imported — used by the sync for idempotency."
  def known_komoot_ids do
    from(r in Ride, where: not is_nil(r.komoot_id), select: r.komoot_id)
    |> Repo.all()
    |> MapSet.new()
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
  """
  def create_imported_ride(points, attrs \\ %{}, opts \\ []) do
    kind = Keyword.get(opts, :kind, "recorded")
    timed? = Keyword.get(opts, :has_time?, true) and kind == "recorded"

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
      |> Repo.update()
    end
  end
end
