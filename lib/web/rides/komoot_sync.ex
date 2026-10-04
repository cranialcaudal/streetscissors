defmodule Web.Rides.KomootSync do
  @moduledoc """
  Mirrors the tours recorded on Komoot into the ride archive. Komoot is the
  only input: a tour recorded in the app appears here, an edit there (name,
  sport, stats, privacy, route) is copied over, and a tour deleted there is
  deleted here. Nothing about a ride is entered on the site.

  Each ride is built from the tour listing, plus its GPS track — one request
  per tour, made when the tour is first seen and again when it changes. The
  track is what the site draws its own map from, cut by the privacy zones
  (`Web.Rides.Privacy`); nothing of Komoot's own rendering is shown, since
  its embed, tour page and map image all show a route whole.

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
  alias Web.SiteSettings

  @etag_key "komoot_etag_tour_recorded"

  # When the last pass ran and how it went, for the admin. Written by sync/1
  # itself, so the hourly pass and the admin's "Sync now" both leave a trace —
  # a sync that fails every hour used to say so only in the journal.
  @last_run_at_key "komoot_last_sync_at"
  @last_run_result_key "komoot_last_sync_result"

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
      record_run({:error, {:crashed, Exception.message(error)}})
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
      opts
      |> Keyword.get(:force, false)
      |> authenticated_sync()
      |> record_run()
    else
      :disabled
    end
  end

  defp authenticated_sync(force?) do
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
  end

  @doc """
  The last pass, as the admin shows it: `%{at: DateTime.t() | nil, status:
  :ok | :partial | :failed | nil, detail: String.t() | nil}`. `status` is
  `:partial` when the listing arrived but some tours failed to import.
  """
  def last_run do
    at =
      with iso when is_binary(iso) <- SiteSettings.get_setting(@last_run_at_key),
           {:ok, at, _offset} <- DateTime.from_iso8601(iso) do
        at
      else
        _ -> nil
      end

    case SiteSettings.get_setting(@last_run_result_key) do
      "ok: " <> detail -> %{at: at, status: :ok, detail: detail}
      "partial: " <> detail -> %{at: at, status: :partial, detail: detail}
      "failed: " <> detail -> %{at: at, status: :failed, detail: detail}
      _ -> %{at: at, status: nil, detail: nil}
    end
  end

  @doc false
  def record_run(result) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    SiteSettings.put_setting(@last_run_at_key, now)
    SiteSettings.put_setting(@last_run_result_key, describe_run(result))
    result
  end

  defp describe_run({:ok, %{unchanged: true}}), do: "ok: unchanged since the last pass"

  defp describe_run({:ok, summary}) do
    counts =
      [:imported, :updated, :deleted, :failed]
      |> Enum.filter(&(summary[&1] > 0))
      |> Enum.map_join(", ", &"#{summary[&1]} #{&1}")

    cond do
      summary.failed > 0 -> "partial: " <> counts
      counts == "" -> "ok: no changes"
      true -> "ok: " <> counts
    end
  end

  defp describe_run({:error, reason}), do: "failed: " <> inspect(reason)

  defp sync_tours(auth, force?) do
    # A change of privacy zone reaches the cards here, on a pass that would
    # otherwise read nothing.
    Rides.refresh_routes()

    etag = if force?, do: nil, else: SiteSettings.get_setting(@etag_key)
    summary = %{imported: 0, updated: 0, deleted: 0, skipped: 0, failed: 0, unchanged: false}

    case Client.list_tours(auth, etag) do
      :not_modified ->
        {:ok, %{summary | unchanged: true}}

      {:ok, tours, new_etag} ->
        summary = sync_tour_list(tours, summary, auth)

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

  defp sync_tour_list(tours, summary, auth) do
    known = Rides.komoot_index()
    tracked = Rides.tracked_ride_ids()

    summary =
      Enum.reduce(tours, summary, fn tour, acc ->
        komoot_id = to_string(tour["id"])

        outcome =
          case Map.fetch(known, komoot_id) do
            {:ok, ride} ->
              update_tour(ride, tour, komoot_id, auth, MapSet.member?(tracked, ride.id))

            :error ->
              import_tour(tour, komoot_id, auth)
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

  defp import_tour(tour, komoot_id, auth) do
    case Rides.create_ride(tour_attrs(tour, komoot_id)) do
      {:ok, ride} ->
        with_track(:imported, ride, auth)

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
  defp update_tour(ride, tour, komoot_id, auth, tracked?) do
    attrs = tour_attrs(tour, komoot_id)

    stale? =
      attrs.komoot_changed_at != nil and
        (is_nil(ride.komoot_changed_at) or
           DateTime.compare(attrs.komoot_changed_at, ride.komoot_changed_at) == :gt)

    cond do
      # A route can be re-cut on Komoot, so an edit re-reads the track — and
      # first, so that a track that won't come leaves the ride looking stale
      # and the next pass tries again.
      stale? or (attrs.visibility != ride.visibility and not tracked?) ->
        with :updated <- with_track(:updated, ride, auth),
             {:ok, _updated} <- Rides.update_ride(ride, attrs) do
          :updated
        else
          _ -> :failed
        end

      # A privacy flip alone leaves the track as it was.
      attrs.visibility != ride.visibility ->
        case Rides.update_ride(ride, attrs) do
          {:ok, _updated} -> :updated
          {:error, _changeset} -> :failed
        end

      not tracked? ->
        with_track(:updated, ride, auth)

      true ->
        :skipped
    end
  rescue
    error ->
      Logger.warning("Komoot tour #{komoot_id} update failed: #{Exception.message(error)}")
      :failed
  end

  # Not getting a track fails the tour, which leaves the ETag unstored so the
  # next pass asks again — the same rule a failed import follows. Until then
  # the ride shows its figures and no map.
  defp with_track(outcome, ride, auth) do
    with {:ok, points} <- Client.tour_track(auth, ride.komoot_id),
         {:ok, _ride} <- Rides.store_track(ride, points) do
      outcome
    else
      error ->
        Logger.warning("Komoot track failed for tour #{ride.komoot_id}: #{inspect(error)}")
        :failed
    end
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
      komoot_changed_at: parse_datetime(tour["changed_at"])
    }
  end

  # Anything short of public (private, friends-only) is private here. The
  # ride is listed all the same.
  defp tour_visibility(tour), do: if(tour["status"] == "public", do: "public", else: "private")

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
