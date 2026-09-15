defmodule Web.Rides.KomootSync do
  @moduledoc """
  Mirrors the tours recorded on Komoot into the ride archive. Komoot is the
  only input: a tour recorded in the app appears here, an edit there (name,
  sport, stats, privacy, route) is copied over, and a tour deleted there is
  deleted here. Nothing about a ride is entered on the site.

  Each ride is built from the tour listing alone, plus one static-map
  thumbnail cached by `Web.Rides.Thumbs` — no GPS track is downloaded.

  Entirely optional: with no KOMOOT_EMAIL / KOMOOT_PASSWORD configured the
  sync reports `:disabled` and does nothing. Every field beyond the tour id
  and start date is nil-tolerated — the API is unofficial and its schema can
  drift.

  ## Cost of a pass

  The hourly schedule exists to catch a ride within an hour of finishing it,
  not because anything usually changes — so a pass is built to cost almost
  nothing when nothing did. The token is held by `Web.Komoot.Auth` instead of
  being re-minted every hour, and the listing is requested conditionally
  against the ETag stored from last time. Komoot's ETag is a plain md5 of the
  listing body, so a 304 proves no tour was added, edited, deleted, or
  flipped between private and public: a quiet hour is one 304 and no body.
  """

  require Logger

  alias Web.Komoot.Auth
  alias Web.Komoot.Client
  alias Web.Rides
  alias Web.Rides.Thumbs
  alias Web.SiteSettings

  @etag_key "komoot_etag_tour_recorded"

  def enabled? do
    config = Application.get_env(:web, :komoot) || []
    is_binary(config[:email]) and is_binary(config[:password])
  end

  @doc "Quantum entry point — never raises, never returns an error."
  def run_scheduled do
    case sync() do
      {:ok, summary} ->
        # A quiet hour is the common case and does not belong in the journal
        # at :info — but it should still be traceable when something looks
        # stuck, hence the debug line.
        if summary.imported + summary.updated + summary.deleted + summary.failed > 0 do
          Logger.info("Komoot sync: #{inspect(summary)}")
        else
          Logger.debug("Komoot sync: #{inspect(summary)}")
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
  Runs a full sync. Returns `{:ok, summary}` with counts of `imported`,
  `updated`, `deleted`, `skipped`, and `failed` tours, and `unchanged: true`
  when Komoot answered `304 Not Modified`. `:disabled` without credentials,
  `{:error, reason}` when login or the listing fails.

  Pass `force: true` to ignore the stored ETag and re-read the listing.
  """
  def sync(opts \\ []) do
    if enabled?() do
      force? = Keyword.get(opts, :force, false)

      with {:ok, auth} <- Auth.fetch() do
        case sync_tours(auth, force?) do
          # A cached token the API no longer accepts: drop it and run once
          # more on a fresh login. Without this the sync would stay broken
          # for as long as the cache held the dead token.
          {:error, {:http, status}} when status in [401, 403] ->
            Auth.invalidate()

            with {:ok, auth} <- Auth.fetch(), do: sync_tours(auth, force?)

          result ->
            result
        end
      end
    else
      :disabled
    end
  end

  defp sync_tours(auth, force?) do
    etag = if force?, do: nil, else: SiteSettings.get_setting(@etag_key)
    summary = %{imported: 0, updated: 0, deleted: 0, skipped: 0, failed: 0, unchanged: false}

    case Client.list_tours(auth, etag) do
      :not_modified ->
        {:ok, %{summary | unchanged: true}}

      {:ok, tours, new_etag} ->
        summary = sync_tour_list(tours, summary)

        # Only trust the new ETag when the whole listing landed cleanly.
        # Storing it after a failed import would 304 the next pass and the
        # tour would never be retried.
        store_etag(if summary.failed == 0, do: new_etag)

        {:ok, summary}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp store_etag(nil), do: SiteSettings.delete_setting(@etag_key)
  defp store_etag(etag), do: SiteSettings.put_setting(@etag_key, etag)

  defp sync_tour_list(tours, summary) do
    known = Rides.komoot_index()

    summary =
      Enum.reduce(tours, summary, fn tour, acc ->
        komoot_id = to_string(tour["id"])

        outcome =
          case Map.fetch(known, komoot_id) do
            {:ok, ride} -> update_tour(ride, tour, komoot_id)
            :error -> import_tour(tour, komoot_id)
          end

        Map.update!(acc, outcome, &(&1 + 1))
      end)

    delete_missing(known, tours, summary)
  end

  # A tour gone from the listing was deleted on Komoot. An empty listing is
  # the exception: a glitch looks exactly like that far more often than a
  # whole archive deleted at once, and believing it would wipe the site.
  defp delete_missing(_known, [], summary), do: summary

  defp delete_missing(known, tours, summary) do
    listed = MapSet.new(tours, &to_string(&1["id"]))

    Enum.reduce(known, summary, fn {komoot_id, ride}, acc ->
      if MapSet.member?(listed, komoot_id) do
        acc
      else
        {:ok, _ride} = Rides.delete_ride(ride)
        %{acc | deleted: acc.deleted + 1}
      end
    end)
  end

  defp import_tour(tour, komoot_id) do
    case Rides.create_ride(tour_attrs(tour, komoot_id)) do
      {:ok, ride} ->
        fetch_thumbnail(ride)
        :imported

      {:error, changeset} ->
        Logger.warning("Komoot tour #{komoot_id} import failed: #{inspect(changeset.errors)}")
        :failed
    end
  rescue
    error ->
      Logger.warning("Komoot tour #{komoot_id} import failed: #{Exception.message(error)}")
      :failed
  end

  # Re-applies the listing when the tour changed on Komoot — or, when the
  # ride has no komoot_changed_at yet, once as a backfill. Komoot does not
  # reliably bump changed_at when the *only* edit is a tour's privacy, so
  # visibility is compared on every read as well.
  defp update_tour(ride, tour, komoot_id) do
    attrs = tour_attrs(tour, komoot_id)

    stale? =
      attrs.komoot_changed_at != nil and
        (is_nil(ride.komoot_changed_at) or
           DateTime.compare(attrs.komoot_changed_at, ride.komoot_changed_at) == :gt)

    cond do
      stale? or attrs.visibility != ride.visibility ->
        case Rides.update_ride(ride, attrs) do
          {:ok, updated} ->
            # The static-map URL encodes the route's own polyline and the CDN
            # serves it `immutable`, so an unchanged URL can only ever return
            # the bytes already on disk — and most edits are a rename.
            if updated.map_image_url != ride.map_image_url or not Thumbs.exists?(updated) do
              fetch_thumbnail(updated)
            end

            :updated

          {:error, _changeset} ->
            :failed
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

  defp tour_attrs(tour, komoot_id) do
    distance = float_or_nil(tour["distance"])
    motion = int_or_nil(tour["time_in_motion"])

    %{
      komoot_id: komoot_id,
      name: tour["name"],
      sport: tour["sport"],
      started_at: parse_datetime(tour["date"]),
      distance_m: distance,
      duration_s: int_or_nil(tour["duration"]),
      time_in_motion_s: motion,
      avg_speed_mps: if(distance != nil and motion != nil and motion > 0, do: distance / motion),
      ascent_m: float_or_nil(tour["elevation_up"]),
      descent_m: float_or_nil(tour["elevation_down"]),
      kcal: int_or_nil(tour["kcal_active"]),
      visibility: tour_visibility(tour),
      komoot_changed_at: parse_datetime(tour["changed_at"]),
      map_image_url: map_image_url(tour)
    }
  end

  # Anything short of public (private, friends-only) is private here: the
  # ride is still listed, but Komoot's embed would refuse to show it.
  defp tour_visibility(tour), do: if(tour["status"] == "public", do: "public", else: "private")

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
end
