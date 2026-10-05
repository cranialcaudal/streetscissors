defmodule Web.Rides.KomootSync do
  @moduledoc """
  Mirrors the tours recorded on Komoot into the ride archive. Komoot is the
  only input: a tour recorded in the app appears here, an edit there (name,
  sport, stats, privacy, route) is copied over, and a tour deleted there is
  deleted here. Nothing about a ride is entered on the site.

  A ride's figures come from the tour listing, read with the owner's login.
  Everything a visitor is *shown* of the route comes from a second read made
  with no login at all (`Client.public_tour/2`): Komoot applies its privacy
  zones to what it hands a stranger, so the static map cached for the cards
  is already cut, and so is the embed the pages point at. The owner's view of
  a route — the whole of it, front door included — is never fetched.

  That second read settles what a stranger is given of the tour, recorded as
  the ride's `stranger_view` (`Web.Rides.Privacy.verdict/1`). A route that
  stays clear of every private place is `"clear"`, and only that is shown
  through Komoot. One that begins or ends at a private place is `"exposed"`:
  the zone is not trimming it, which is the alarm. One whose ends are trimmed
  and which comes back past a private place in between is `"passing"`: a
  zone trims a tour's ends and nothing else, so a ride that came home and
  went out again lands here, held back without any alarm. And a tour that
  never leaves the zone is `"hidden"`: Komoot refuses a stranger the whole
  of it, which is an answer, not a failure.

  A private tour also gets its Komoot share token, asked for once, because
  neither the embed nor a stranger's read will show a tour that isn't public
  without one.

  A tour is looked at this way when it is first seen, when it changes on
  Komoot, and whenever something it should have is missing. `force: true` —
  the admin's "Sync now" — looks at every tour again, which makes that
  button a full re-check of what strangers can see.

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
  alias Web.Rides.Privacy
  alias Web.Rides.Thumbs
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
    etag = if force?, do: nil, else: SiteSettings.get_setting(@etag_key)
    summary = %{imported: 0, updated: 0, deleted: 0, skipped: 0, failed: 0, unchanged: false}

    case Client.list_tours(auth, etag) do
      :not_modified ->
        {:ok, %{summary | unchanged: true}}

      {:ok, tours, new_etag} ->
        summary = sync_tour_list(tours, summary, auth, force?)

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

  defp sync_tour_list(tours, summary, auth, force?) do
    known = Rides.komoot_index()

    summary =
      Enum.reduce(tours, summary, fn tour, acc ->
        komoot_id = to_string(tour["id"])

        outcome =
          case Map.fetch(known, komoot_id) do
            {:ok, ride} -> update_tour(ride, tour, komoot_id, auth, force?)
            :error -> import_tour(tour, komoot_id, auth)
          end

        Map.update!(acc, outcome, &(&1 + 1))
      end)

    summary = delete_missing(known, tours, summary)

    # Whatever is left in the cache that no ride now answers for: a deleted
    # tour's picture, an earlier cut of a route, and the whole-route images
    # an earlier version of the site kept under the bare ride id.
    Thumbs.sweep_all(Map.values(Rides.komoot_index()))

    summary
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
    with {:ok, ride} <- Rides.create_ride(tour_attrs(tour, komoot_id)),
         {:ok, _seen, _changed?} <- as_a_stranger(ride, auth) do
      :imported
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        Logger.warning("Komoot tour #{komoot_id} import failed: #{inspect(changeset.errors)}")
        :failed

      _ ->
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
  defp update_tour(ride, tour, komoot_id, auth, force?) do
    attrs = tour_attrs(tour, komoot_id)

    stale? =
      attrs.komoot_changed_at != nil and
        (is_nil(ride.komoot_changed_at) or
           DateTime.compare(attrs.komoot_changed_at, ride.komoot_changed_at) == :gt)

    cond do
      # A change on Komoot is also when its zones may have moved — editing
      # one touches every tour — so the route's picture and its privacy check
      # are both out of date. `komoot_changed_at` is recorded last, after the
      # stranger's view has been read, so a read that fails leaves the ride
      # looking stale and the next pass tries again.
      stale? or attrs.visibility != ride.visibility ->
        with {:ok, updated} <- Rides.update_ride(ride, Map.delete(attrs, :komoot_changed_at)),
             {:ok, seen, _changed?} <- as_a_stranger(updated, auth),
             {:ok, _ride} <-
               Rides.update_ride(seen, %{komoot_changed_at: attrs.komoot_changed_at}) do
          :updated
        else
          _ -> :failed
        end

      force? or unseen?(ride) ->
        case as_a_stranger(ride, auth) do
          {:ok, _seen, true} -> :updated
          {:ok, _seen, false} -> :skipped
          :error -> :failed
        end

      true ->
        :skipped
    end
  rescue
    error ->
      Logger.warning("Komoot tour #{komoot_id} update failed: #{Exception.message(error)}")
      :failed
  end

  # A ride that still wants a stranger's read: one never looked at, and a
  # clear one whose card has no picture yet. Anything else (exposed, passing,
  # hidden) is always looked at again, so that putting it right on Komoot
  # shows on the next pass that reads anything. (A quiet hour is a 304 and reads
  # nothing, so this costs a request per such ride only when something else
  # changed.)
  defp unseen?(%{stranger_view: "clear"} = ride),
    do: is_binary(ride.map_image_url) and not Thumbs.exists?(ride)

  defp unseen?(_ride), do: true

  # Reads the tour the way a visitor's browser will be given it, and records
  # what that view is: the share token it needs, the map Komoot draws for it,
  # and which of clear, passing, exposed or hidden it is.
  #
  # `{:ok, ride, changed?}` when the look succeeded, `changed?` saying
  # whether it found anything new. `:error` when any step failed, which
  # fails the tour and so leaves the ETag unstored: the next pass asks again,
  # the same rule a failed import follows.
  defp as_a_stranger(ride, auth) do
    with {:ok, tokened} <- with_share_token(ride, auth),
         {:ok, tokened, answer} <- read_as_a_stranger(tokened, auth),
         {:ok, seen} <- Rides.update_ride(tokened, view_attrs(answer)) do
      if seen.stranger_view == "clear" do
        unless Thumbs.exists?(seen), do: fetch_thumbnail(seen)
      else
        Thumbs.delete(seen)
      end

      if seen.stranger_view != ride.stranger_view, do: announce(seen)

      changed? =
        seen.map_image_url != ride.map_image_url or seen.stranger_view != ride.stranger_view or
          seen.share_token != ride.share_token

      {:ok, seen, changed?}
    else
      error ->
        Logger.warning(
          "Komoot tour #{ride.komoot_id} could not be read as a stranger: #{inspect(error)}"
        )

        :error
    end
  end

  # `{:ok, ride, answer}`, the answer being `:hidden` or the route and map a
  # stranger is given. A private tour refused with its token on file gets one
  # more try on a token asked for afresh: a share link switched off and on
  # again in the app is a new link, and the old one would otherwise fail the
  # tour for good.
  defp read_as_a_stranger(ride, auth) do
    case Client.public_tour(ride.komoot_id, token_for(ride)) do
      {:error, :access_denied} when ride.visibility == "private" ->
        with {:ok, token} when token != ride.share_token <-
               Client.share_token(auth, ride.komoot_id),
             {:ok, ride} <- Rides.update_ride(ride, %{share_token: token}) do
          answer(ride, Client.public_tour(ride.komoot_id, token))
        else
          _ -> {:error, :access_denied}
        end

      result ->
        answer(ride, result)
    end
  end

  defp answer(ride, :hidden), do: {:ok, ride, :hidden}
  defp answer(ride, {:ok, view}), do: {:ok, ride, view}
  defp answer(_ride, {:error, reason}), do: {:error, reason}

  defp view_attrs(:hidden), do: %{stranger_view: "hidden", map_image_url: nil}

  defp view_attrs(%{points: points, map_image: image}) do
    %{
      stranger_view: Atom.to_string(Privacy.verdict(points)),
      map_image_url: map_image_url(image)
    }
  end

  # Said once, when a tour's view changes, and without its coordinates, which
  # are the thing at stake.
  defp announce(%{stranger_view: "exposed"} = ride) do
    Logger.warning(
      "Komoot tour #{ride.komoot_id} is exposed: a stranger's view of it begins or ends " <>
        "within #{Privacy.tripwire_m()} m of a private place, so Komoot's privacy zone is not " <>
        "hiding it. Its embed and map are withheld."
    )
  end

  defp announce(%{stranger_view: "passing"} = ride) do
    Logger.info(
      "Komoot tour #{ride.komoot_id} passes within #{Privacy.tripwire_m()} m of a private " <>
        "place mid-tour, which a privacy zone does not trim. Its embed and map are withheld."
    )
  end

  defp announce(%{stranger_view: "hidden"} = ride) do
    Logger.info(
      "Komoot tour #{ride.komoot_id} lies inside a privacy zone: Komoot shows a stranger " <>
        "nothing of it, so the site shows its figures alone."
    )
  end

  defp announce(_ride), do: :ok

  # A private tour can only be embedded, or read by a stranger at all,
  # through its share link, so one is asked for the first time the sync sees
  # the tour private without it, and kept from then on (it survives a flip
  # to public and back).
  defp with_share_token(%{visibility: "private", share_token: nil} = ride, auth) do
    with {:ok, token} <- Client.share_token(auth, ride.komoot_id) do
      Rides.update_ride(ride, %{share_token: token})
    end
  end

  defp with_share_token(ride, _auth), do: {:ok, ride}

  defp token_for(%{visibility: "private", share_token: token}), do: token
  defp token_for(_ride), do: nil

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

  # Anything short of public (private, friends-only) is private here: the
  # ride is still listed, but Komoot's embed would refuse to show it.
  defp tour_visibility(tour), do: if(tour["status"] == "public", do: "public", else: "private")

  # Komoot's map image is a URL template. Sized here for a card.
  defp map_image_url(src) when is_binary(src) do
    src =
      src
      |> String.replace("{width}", "800")
      |> String.replace("{height}", "450")
      |> drop_templated_params()

    if String.starts_with?(src, "https://"), do: src
  end

  defp map_image_url(_src), do: nil

  # Real map_image srcs template more parameters than width/height (e.g.
  # &crop={crop}); any parameter left with literal braces makes the URL an
  # invalid request target, so unresolved ones are dropped.
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

  # A picture that will not come does not fail the tour: the card shows the
  # sport's name instead, and `unseen?/1` has the next pass try again.
  defp fetch_thumbnail(%{map_image_url: url} = ride) when is_binary(url) and url != "" do
    case Client.download_image(url) do
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
