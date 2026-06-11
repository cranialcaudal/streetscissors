defmodule Web.Rides do
  @moduledoc """
  Ride tracking: live GPS ingestion from the Overland phone app, the ride
  archive, and GPX imports.

  Privacy rule: points inside a configured privacy zone are stored raw but
  filtered out of every public egress — `list_points/2` defaults to
  `public: true`, and live broadcasts only carry filtered points. Admin
  callers must explicitly pass `public: false` to see everything.
  """

  import Ecto.Query, warn: false
  alias Web.Repo
  alias Web.Rides.{Ride, RidePoint, Privacy, Stats, GPX}

  @topic "rides:live"
  @insert_chunk 500
  @stale_after_hours 3

  def subscribe do
    Phoenix.PubSub.subscribe(Web.PubSub, @topic)
  end

  ## Rides

  def get_active_ride do
    from(r in Ride, where: r.status == "active", order_by: [desc: r.started_at], limit: 1)
    |> Repo.one()
  end

  def get_ride!(id), do: Repo.get!(Ride, id)

  def list_completed_rides do
    from(r in Ride, where: r.status == "completed", order_by: [desc: r.started_at])
    |> Repo.all()
  end

  @doc "Starts a new active ride, closing any ride still active."
  def start_ride(attrs \\ %{}) do
    if ride = get_active_ride(), do: stop_ride(ride)

    result =
      %Ride{}
      |> Ride.changeset(attrs)
      |> Ecto.Changeset.put_change(:status, "active")
      |> Ecto.Changeset.put_change(:started_at, now())
      |> Repo.insert()

    with {:ok, ride} <- result do
      broadcast({:ride_started, ride})
      {:ok, ride}
    end
  end

  @doc "Completes a ride: computes and persists stats from its points."
  def stop_ride(%Ride{} = ride) do
    points = list_points(ride, public: false)
    stats = Stats.compute(points)
    ended_at = if last = List.last(points), do: last.recorded_at, else: now()

    result =
      ride
      |> Ecto.Changeset.change(
        status: "completed",
        ended_at: ended_at,
        point_count: length(points),
        distance_m: stats.distance_m,
        duration_s: stats.duration_s,
        avg_speed_mps: stats.avg_speed_mps,
        max_speed_mps: stats.max_speed_mps,
        ascent_m: stats.ascent_m,
        descent_m: stats.descent_m
      )
      |> Repo.update()

    with {:ok, ride} <- result do
      broadcast({:ride_stopped, ride})
      {:ok, ride}
    end
  end

  @doc "Closes the active ride if it has received no points for #{@stale_after_hours}h. Run by Quantum."
  def auto_close_stale_ride do
    with %Ride{} = ride <- get_active_ride() do
      last_at = last_point_at(ride) || ride.started_at

      if DateTime.diff(now(), last_at, :hour) >= @stale_after_hours do
        stop_ride(ride)
      end
    end

    :ok
  end

  def update_ride(%Ride{} = ride, attrs) do
    ride |> Ride.changeset(attrs) |> Repo.update()
  end

  def delete_ride(%Ride{} = ride), do: Repo.delete(ride)

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

  @doc """
  Ingests a batch of Overland GeoJSON features into the active ride.

  Tolerates Overland's retry behavior: duplicate timestamps are dropped via
  the `[ride_id, recorded_at]` unique index, and late out-of-order arrivals
  after signal dead zones are fine because reads order by `recorded_at`.
  Returns `{:ok, accepted_count}`; with no active ride the batch is
  discarded (still a success — the phone must not requeue it).
  """
  def ingest_locations(locations) when is_list(locations) do
    case get_active_ride() do
      nil ->
        {:ok, 0}

      ride ->
        rows =
          locations
          |> Enum.map(&parse_feature/1)
          |> Enum.reject(&is_nil/1)
          |> Enum.filter(&(DateTime.compare(&1.recorded_at, ride.started_at) != :lt))
          |> Enum.uniq_by(& &1.recorded_at)
          |> Enum.sort_by(& &1.recorded_at, DateTime)
          |> Enum.map(&Map.put(&1, :ride_id, ride.id))

        rows
        |> Enum.chunk_every(@insert_chunk)
        |> Enum.each(&Repo.insert_all(RidePoint, &1, on_conflict: :nothing))

        update_point_count(ride)

        case Privacy.filter(rows) do
          [] -> :ok
          public_rows -> broadcast({:ride_points, ride.id, public_rows})
        end

        {:ok, length(rows)}
    end
  end

  defp parse_feature(%{"geometry" => %{"coordinates" => [lon, lat | _]}} = feature)
       when is_number(lon) and is_number(lat) do
    props = feature["properties"] || %{}

    case DateTime.from_iso8601(to_string(props["timestamp"])) do
      {:ok, dt, _offset} ->
        %{
          lat: lat / 1,
          lon: lon / 1,
          recorded_at: DateTime.truncate(dt, :second),
          altitude_m: number_or_nil(props["altitude"]),
          # Overland reports -1 for unknown speed/accuracy
          speed_mps: non_negative_or_nil(props["speed"]),
          accuracy_m: non_negative_or_nil(props["horizontal_accuracy"])
        }

      _ ->
        nil
    end
  end

  defp parse_feature(_), do: nil

  defp number_or_nil(value) when is_number(value), do: value / 1
  defp number_or_nil(_), do: nil

  defp non_negative_or_nil(value) when is_number(value) and value >= 0, do: value / 1
  defp non_negative_or_nil(_), do: nil

  defp update_point_count(%Ride{} = ride) do
    count = Repo.aggregate(from(p in RidePoint, where: p.ride_id == ^ride.id), :count)
    from(r in Ride, where: r.id == ^ride.id) |> Repo.update_all(set: [point_count: count])
  end

  defp last_point_at(%Ride{} = ride) do
    from(p in RidePoint, where: p.ride_id == ^ride.id, select: max(p.recorded_at))
    |> Repo.one()
  end

  ## GPX import

  @doc """
  Creates a completed ride from a GPX file's contents. Files without
  timestamps still import (distance/elevation stats only).
  """
  def import_gpx(xml, attrs \\ %{}) do
    with {:ok, points, has_time?} <- GPX.parse(xml),
         {:ok, ride} <- insert_gpx_ride(points, has_time?, attrs) do
      {:ok, ride}
    end
  end

  defp insert_gpx_ride(points, has_time?, attrs) do
    result =
      %Ride{}
      |> Ride.changeset(attrs)
      |> Ecto.Changeset.put_change(:status, "completed")
      |> Ecto.Changeset.put_change(:source, "gpx")
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
        started_at: if(has_time?, do: List.first(stored).recorded_at),
        ended_at: if(has_time?, do: List.last(stored).recorded_at),
        point_count: length(stored),
        distance_m: stats.distance_m,
        ascent_m: stats.ascent_m,
        descent_m: stats.descent_m,
        duration_s: if(has_time?, do: stats.duration_s),
        avg_speed_mps: if(has_time?, do: stats.avg_speed_mps),
        max_speed_mps: if(has_time?, do: stats.max_speed_mps)
      )
      |> Repo.update()
    end
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Web.PubSub, @topic, message)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
