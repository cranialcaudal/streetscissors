defmodule Web.Rides.KomootSync do
  @moduledoc """
  Pulls new recorded and planned tours from Komoot into the ride archive
  and refreshes already-imported tours whose `changed_at` moved on Komoot
  (name, sport, stats, visibility, thumbnail). The GPS track itself is
  never re-fetched — delete the ride in the admin and re-sync to refresh a
  re-routed tour.

  Entirely optional: with no KOMOOT_EMAIL / KOMOOT_PASSWORD configured the
  sync reports `:disabled` and does nothing. Every field beyond the basics
  is nil-tolerated — the API is unofficial and its schema can drift.
  """

  require Logger

  alias Web.Komoot.Client
  alias Web.Rides
  alias Web.Rides.Thumbs

  @kinds [{"tour_recorded", "recorded"}, {"tour_planned", "planned"}]

  def enabled? do
    config = Application.get_env(:web, :komoot) || []
    is_binary(config[:email]) and is_binary(config[:password])
  end

  @doc "Quantum entry point — never raises, never returns an error."
  def run_scheduled do
    case sync() do
      {:ok, summary} ->
        if summary.imported + summary.updated + summary.failed > 0 do
          Logger.info("Komoot sync: #{inspect(summary)}")
        end

      :disabled ->
        :ok

      {:error, reason} ->
        Logger.warning("Komoot sync failed: #{inspect(reason)}")
    end

    :ok
  rescue
    error ->
      Logger.warning("Komoot sync crashed: #{Exception.message(error)}")
      :ok
  end

  @doc """
  Runs a full sync. Returns `{:ok, summary}` with counts of imported,
  updated, skipped, and failed tours, `:disabled` without credentials, or
  `{:error, reason}` when login or a tour listing fails.
  """
  def sync do
    config = Application.get_env(:web, :komoot) || []

    if enabled?() do
      case Client.login(config[:email], config[:password]) do
        {:ok, auth} -> sync_tours(auth)
        {:error, reason} -> {:error, reason}
      end
    else
      :disabled
    end
  end

  defp sync_tours(auth) do
    known = Rides.komoot_index()
    zero = %{imported: 0, updated: 0, skipped: 0, failed: 0}

    Enum.reduce_while(@kinds, {:ok, zero}, fn
      {type, kind}, {:ok, acc} ->
        case Client.list_tours(auth, type) do
          {:ok, tours} -> {:cont, {:ok, sync_tour_list(tours, kind, auth, known, acc)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end

  defp sync_tour_list(tours, kind, auth, known, acc) do
    Enum.reduce(tours, acc, fn tour, acc ->
      komoot_id = to_string(tour["id"])

      case Map.get(known, komoot_id) do
        nil ->
          case import_tour(tour, kind, auth, komoot_id) do
            {:ok, _ride} -> %{acc | imported: acc.imported + 1}
            _ -> %{acc | failed: acc.failed + 1}
          end

        ride ->
          case maybe_update_tour(ride, tour, komoot_id) do
            :updated -> %{acc | updated: acc.updated + 1}
            :skipped -> %{acc | skipped: acc.skipped + 1}
            :failed -> %{acc | failed: acc.failed + 1}
          end
      end
    end)
  end

  defp import_tour(tour, kind, auth, komoot_id) do
    with {:ok, date, _offset} <- DateTime.from_iso8601(to_string(tour["date"])),
         {:ok, items} <- Client.fetch_coordinates(auth, tour["id"]) do
      date = DateTime.truncate(date, :second)
      points = Enum.map(items, &coordinate_to_point(&1, date))

      attrs =
        Map.merge(
          %{
            "name" => tour["name"],
            "sport" => tour["sport"],
            "source" => "komoot",
            "komoot_id" => komoot_id,
            "started_at" => date
          },
          enrichment_attrs(tour)
        )

      with {:ok, ride} <-
             Rides.create_imported_ride(points, attrs,
               kind: kind,
               overrides: stat_overrides(tour)
             ) do
        fetch_thumbnail(ride)
        {:ok, ride}
      end
    end
  rescue
    error ->
      Logger.warning("Komoot tour #{komoot_id} import failed: #{Exception.message(error)}")
      {:error, error}
  end

  # Metadata-only refresh: applies when the tour changed on Komoot, or —
  # when the ride has no komoot_changed_at yet — as a one-time backfill of
  # rides imported before the enrichment columns existed. Requires the API
  # to actually send changed_at, so responses without it never cause churn.
  defp maybe_update_tour(ride, tour, komoot_id) do
    changed_at = parse_datetime(tour["changed_at"])

    stale? =
      changed_at != nil and
        (is_nil(ride.komoot_changed_at) or
           DateTime.compare(changed_at, ride.komoot_changed_at) == :gt)

    cond do
      stale? ->
        attrs =
          Map.merge(
            %{"name" => tour["name"], "sport" => tour["sport"]},
            enrichment_attrs(tour)
          )

        with {:ok, updated} <- Rides.update_ride(ride, attrs),
             {:ok, updated} <- Rides.override_stats(updated, stat_overrides(tour)) do
          fetch_thumbnail(updated)
          :updated
        else
          _ -> :failed
        end

      # Komoot does not reliably bump changed_at when the *only* edit is a
      # tour's privacy setting, so visibility is mirrored on every pass
      # instead of riding on staleness — otherwise a tour made public on
      # Komoot would stay hidden here indefinitely. Komoot stays the source
      # of truth in both directions: this can only ever copy its flag.
      tour_visibility(tour) != ride.visibility ->
        case Rides.update_ride(ride, %{"visibility" => tour_visibility(tour)}) do
          {:ok, _ride} -> :updated
          _ -> :failed
        end

      is_binary(ride.map_image_url) and not Thumbs.exists?(ride) ->
        fetch_thumbnail(ride)
        :skipped

      true ->
        :skipped
    end
  rescue
    error ->
      Logger.warning("Komoot tour #{komoot_id} update failed: #{Exception.message(error)}")
      :failed
  end

  defp tour_visibility(tour), do: if(tour["status"] == "private", do: "private", else: "public")

  defp enrichment_attrs(tour) do
    %{
      "visibility" => tour_visibility(tour),
      "kcal" => int_or_nil(tour["kcal_active"]),
      "time_in_motion_s" => int_or_nil(tour["time_in_motion"]),
      "komoot_changed_at" => parse_datetime(tour["changed_at"]),
      "map_image_url" => map_image_url(tour)
    }
  end

  # API-sourced stats win over the locally computed ones where present.
  defp stat_overrides(tour) do
    distance = float_or_nil(tour["distance"])
    motion = int_or_nil(tour["time_in_motion"])

    %{
      distance_m: distance,
      duration_s: int_or_nil(tour["duration"]),
      ascent_m: float_or_nil(tour["elevation_up"]),
      descent_m: float_or_nil(tour["elevation_down"]),
      avg_speed_mps: if(distance != nil and motion != nil and motion > 0, do: distance / motion)
    }
  end

  defp map_image_url(tour) do
    src = get_in(tour, ["map_image", "src"]) || get_in(tour, ["map_image_preview", "src"])

    if is_binary(src) do
      src =
        src
        |> String.replace("{width}", "800")
        |> String.replace("{height}", "450")
        |> drop_templated_params()

      if String.starts_with?(src, "https://"), do: src
    end
  end

  # Real map_image srcs template more parameters than width/height (e.g.
  # &crop={crop}); any parameter left with literal braces makes the URL an
  # invalid request target, so unresolved ones are dropped. Applied at
  # download time too, for URLs stored before this sanitizing existed.
  defp drop_templated_params(url) do
    case String.split(url, "?", parts: 2) do
      [base, query] ->
        kept =
          query
          |> String.split("&")
          |> Enum.reject(&String.contains?(&1, ["{", "}"]))
          |> Enum.join("&")

        if kept == "", do: base, else: base <> "?" <> kept

      [base] ->
        base
    end
  end

  defp fetch_thumbnail(%{map_image_url: url} = ride) when is_binary(url) and url != "" do
    case Client.download_image(drop_templated_params(url)) do
      {:ok, binary, _content_type} ->
        Thumbs.store(ride, binary)

      {:error, reason} ->
        Logger.warning("Komoot thumbnail fetch failed for ride #{ride.id}: #{inspect(reason)}")
        :error
    end
  end

  defp fetch_thumbnail(_ride), do: :ok

  defp parse_datetime(value) do
    case DateTime.from_iso8601(to_string(value)) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp int_or_nil(value) when is_number(value), do: round(value)
  defp int_or_nil(_), do: nil

  defp float_or_nil(value) when is_number(value), do: value / 1
  defp float_or_nil(_), do: nil

  defp coordinate_to_point(item, date) do
    %{
      lat: item["lat"] / 1,
      lon: item["lng"] / 1,
      altitude_m: if(is_number(item["alt"]), do: item["alt"] / 1),
      recorded_at:
        date
        |> DateTime.add(round(item["t"] || 0), :millisecond)
        |> DateTime.truncate(:second),
      speed_mps: nil,
      accuracy_m: nil
    }
  end
end
