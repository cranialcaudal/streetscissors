defmodule Web.Rides.KomootSync do
  @moduledoc """
  Pulls new recorded and planned tours from Komoot into the ride archive.

  Entirely optional: with no KOMOOT_EMAIL / KOMOOT_PASSWORD configured the
  sync reports `:disabled` and does nothing. Already-imported tours are
  skipped by `komoot_id`, so re-runs are cheap and idempotent. Edits to an
  already-synced tour on Komoot are not picked up — delete the ride in the
  admin and re-sync to refresh it.
  """

  require Logger

  alias Web.Komoot.Client
  alias Web.Rides

  @kinds [{"tour_recorded", "recorded"}, {"tour_planned", "planned"}]

  def enabled? do
    config = Application.get_env(:web, :komoot) || []
    is_binary(config[:email]) and is_binary(config[:password])
  end

  @doc "Quantum entry point — never raises, never returns an error."
  def run_scheduled do
    case sync() do
      {:ok, summary} ->
        if summary.imported + summary.failed > 0 do
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
  skipped (already known), and failed tours, `:disabled` without
  credentials, or `{:error, reason}` when login or a tour listing fails.
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
    known = Rides.known_komoot_ids()

    Enum.reduce_while(@kinds, {:ok, %{imported: 0, skipped: 0, failed: 0}}, fn
      {type, kind}, {:ok, acc} ->
        case Client.list_tours(auth, type) do
          {:ok, tours} -> {:cont, {:ok, import_tours(tours, kind, auth, known, acc)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end

  defp import_tours(tours, kind, auth, known, acc) do
    Enum.reduce(tours, acc, fn tour, acc ->
      komoot_id = to_string(tour["id"])

      cond do
        MapSet.member?(known, komoot_id) ->
          %{acc | skipped: acc.skipped + 1}

        match?({:ok, _}, import_tour(tour, kind, auth, komoot_id)) ->
          %{acc | imported: acc.imported + 1}

        true ->
          %{acc | failed: acc.failed + 1}
      end
    end)
  end

  defp import_tour(tour, kind, auth, komoot_id) do
    with {:ok, date, _offset} <- DateTime.from_iso8601(to_string(tour["date"])),
         {:ok, items} <- Client.fetch_coordinates(auth, tour["id"]) do
      date = DateTime.truncate(date, :second)
      points = Enum.map(items, &coordinate_to_point(&1, date))

      attrs = %{
        "name" => tour["name"],
        "sport" => tour["sport"],
        "source" => "komoot",
        "komoot_id" => komoot_id,
        "started_at" => date
      }

      Rides.create_imported_ride(points, attrs, kind: kind)
    end
  rescue
    error ->
      Logger.warning("Komoot tour #{komoot_id} import failed: #{Exception.message(error)}")
      {:error, error}
  end

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
