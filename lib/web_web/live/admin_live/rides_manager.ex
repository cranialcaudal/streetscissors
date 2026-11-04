defmodule WebWeb.AdminLive.RidesManager do
  @moduledoc """
  Activities: the Komoot mirror's controls and what a stranger can see of it.

  There is nothing to edit here — Komoot is the only input — so the page is:

    * **Komoot.** A "Sync now" button, when the last pass ran and what came
      of it (`KomootSync.last_run/0`, written by every pass), and the
      tripwire's verdict (`Web.Rides.Privacy`): whether any activity, read
      the way a visitor's browser reads it, still shows a private place.
      "Sync now" forces every tour to be looked at again, so it is also the
      button for "check what strangers can see".
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Rides
  alias Web.Rides.{KomootSync, Privacy, Units}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Activities | Admin",
       komoot_enabled: KomootSync.enabled?(),
       zones: Privacy.zones(),
       sync_running: false
     )
     |> load()}
  end

  defp load(socket) do
    rides = Rides.list_rides()

    assign(socket,
      rides: rides,
      last_run: KomootSync.last_run(),
      views: Enum.frequencies_by(rides, & &1.stranger_view)
    )
  end

  # --- Komoot ----------------------------------------------------------------

  def handle_event("sync_komoot", _params, socket) do
    {:noreply,
     socket
     |> assign(sync_running: true)
     # force: true — the button exists for "read Komoot again now", so it
     # must not be answered by a cached ETag saying nothing changed, and it
     # re-reads every tour as a stranger rather than only the ones that moved.
     |> start_async(:komoot_sync, fn -> KomootSync.sync(force: true) end)}
  end

  def handle_async(:komoot_sync, {:ok, result}, socket) do
    socket = assign(socket, sync_running: false)

    case result do
      {:ok, summary} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(
           :info,
           "Komoot sync: #{summary.imported} imported, #{summary.updated} updated, " <>
             "#{summary.deleted} deleted, #{summary.failed} failed."
         )}

      :disabled ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Komoot sync is disabled — set KOMOOT_EMAIL and KOMOOT_PASSWORD."
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(:error, "Komoot sync failed: #{inspect(reason)}")}
    end
  end

  def handle_async(:komoot_sync, {:exit, reason}, socket) do
    KomootSync.record_run({:error, {:crashed, reason}})

    {:noreply,
     socket
     |> assign(sync_running: false)
     |> load()
     |> put_flash(:error, "Komoot sync crashed: #{inspect(reason)}")}
  end

  def render(assigns) do
    ~H"""
    <.page_head slug="Training / Activities" title="Activities">
      <:lede>
        Every tour recorded on Komoot, checked hourly and drawn by Komoot's own embed. Edits,
        privacy changes and deletions in the app carry over on their own.
      </:lede>
      <:actions>
        <button
          :if={@komoot_enabled}
          phx-click="sync_komoot"
          class="adm-btn adm-btn--primary"
          disabled={@sync_running}
        >
          <.icon name="hero-arrow-path" class="size-4" />
          {if @sync_running, do: "Syncing…", else: "Sync now"}
        </button>
      </:actions>
    </.page_head>

    <.panel title="Komoot" id="komoot">
      <ul class="adm-status">
        <li :if={!@komoot_enabled}>
          <span class="adm-status-dot" aria-hidden="true"></span>
          <span class="adm-status-name">Sync</span>
          <span class="adm-status-detail">
            Disabled — set <code>KOMOOT_EMAIL</code>
            and <code>KOMOOT_PASSWORD</code>
            in the environment.
          </span>
        </li>
        <li :if={@komoot_enabled}>
          <span class={["adm-status-dot", run_class(@last_run.status)]} aria-hidden="true"></span>
          <span class="adm-status-name">Last pass</span>
          <span class="adm-status-detail">
            {run_line(@last_run)}
          </span>
        </li>
        <li :if={@komoot_enabled} id="privacy-status">
          <span class={["adm-status-dot", privacy_class(@zones, @views)]} aria-hidden="true"></span>
          <span class="adm-status-name">What strangers see</span>
          <span class="adm-status-detail">{privacy_line(@zones, @views)}</span>
        </li>
      </ul>
      <p class="adm-help">
        Komoot hides home with the privacy zone set in its app. The site keeps its own note of
        where home is (<code>RIDE_PRIVACY_ZONES</code>) and checks each tour as a stranger is
        shown it: one that comes within {Privacy.tripwire_m()} m loses its embed and map until it
        no longer does. A zone trims where a tour starts and ends, not a pass back through it, so
        a ride that came home and went out again is held back too, with no alarm: split or trim
        it in the app to show it. "Sync now" looks at every tour again.
      </p>
    </.panel>

    <.panel title="Archive" count={length(@rides)}>
      <.rows id="rides" class="adm-rows--grid" rows={@rides} row_id={&"ride-#{&1.id}"}>
        <:col :let={ride} label="Name" class="adm-cell-title">{ride.name || "Untitled"}</:col>
        <:col :let={ride} label="Date">{Units.date(ride.started_at)}</:col>
        <:col :let={ride} label="Sport">{Units.sport(ride.sport)}</:col>
        <:col :let={ride} label="Distance" class="adm-cell-num">
          {Units.distance(ride.distance_m)}
        </:col>
        <:col :let={ride} label="On Komoot">
          <.pill :if={ride.visibility == "private"} tone="quiet" class="ride-private">Private</.pill>
          <.pill :if={ride.visibility != "private"} tone="live">Public</.pill>
          <.pill :if={ride.stranger_view == "exposed"} tone="failed">Exposed</.pill>
          <.pill :if={ride.stranger_view == "passing"} tone="held">Passes home</.pill>
          <.pill :if={ride.stranger_view == "hidden"} tone="quiet">Hidden by Komoot</.pill>
          <.pill :if={is_nil(ride.stranger_view)} tone="held">Not checked yet</.pill>
        </:col>
        <:action :let={ride}>
          <.link
            navigate={~p"/fitness/rides/#{ride.id}"}
            class="adm-btn adm-btn--small adm-btn--quiet"
          >
            View
          </.link>
        </:action>
        <:empty>Nothing synced yet.</:empty>
      </.rows>
    </.panel>
    """
  end

  defp run_line(%{at: nil}), do: "No pass recorded yet."
  defp run_line(%{at: at, detail: detail}), do: "#{ago(at)} — #{detail}"

  defp run_class(:ok), do: "adm-status-dot--ok"
  defp run_class(:partial), do: "adm-status-dot--warn"
  defp run_class(:failed), do: "adm-status-dot--fail"
  defp run_class(_), do: nil

  # Says how many, never where.
  defp privacy_line(:invalid, _views),
    do:
      "RIDE_PRIVACY_ZONES can't be read, so no tour can be checked: every embed and map is withheld until it is fixed."

  defp privacy_line({:ok, []}, views),
    do:
      "Not checked. Komoot's privacy zone is trusted as it stands; set RIDE_PRIVACY_ZONES (lat,lng) to have each tour verified." <>
        also(views)

  defp privacy_line({:ok, zones}, views) do
    case Map.get(views, "exposed", 0) do
      0 ->
        "No activity begins or ends near #{places(zones)} as a stranger is shown it. Komoot's privacy zone is doing its job."

      n ->
        "#{activities(n)} still #{if n == 1, do: "begins or ends", else: "begin or end"} at a private place as a stranger is shown #{if n == 1, do: "it", else: "them"}: " <>
          "Komoot's privacy zone is not hiding #{if n == 1, do: "it", else: "them"}. " <>
          "#{if n == 1, do: "Its embed and map are", else: "Their embeds and maps are"} withheld. " <>
          "Check the zone in the Komoot app, then Sync now."
    end <> also(views)
  end

  # The quieter states, when there are any: tours that pass home mid-way,
  # tours Komoot keeps from strangers altogether, and tours the sync has not
  # yet asked about.
  defp also(views) do
    passing =
      case Map.get(views, "passing", 0) do
        0 ->
          []

        1 ->
          [
            "1 passes it mid-tour, which a zone does not trim, and is shown without Komoot's map until it is split or trimmed in the app."
          ]

        n ->
          [
            "#{n} pass it mid-tour, which a zone does not trim, and are shown without Komoot's map until they are split or trimmed in the app."
          ]
      end

    hidden =
      case Map.get(views, "hidden", 0) do
        0 ->
          []

        1 ->
          ["1 lies wholly inside Komoot's zone, and Komoot shows a stranger nothing of it."]

        n ->
          ["#{n} lie wholly inside Komoot's zone, and Komoot shows a stranger nothing of them."]
      end

    waiting =
      case Map.get(views, nil, 0) do
        0 ->
          []

        n ->
          ["#{activities(n)} not checked yet: nothing of Komoot's is shown for one until it is."]
      end

    Enum.map_join(passing ++ hidden ++ waiting, &(" " <> &1))
  end

  defp places([_]), do: "the private place on file"
  defp places(zones), do: "the #{length(zones)} private places on file"

  defp activities(1), do: "1 activity"
  defp activities(n), do: "#{n} activities"

  defp privacy_class(:invalid, _views), do: "adm-status-dot--fail"
  defp privacy_class({:ok, []}, _views), do: "adm-status-dot--warn"
  defp privacy_class({:ok, _zones}, %{"exposed" => _n}), do: "adm-status-dot--fail"
  defp privacy_class({:ok, _zones}, _views), do: "adm-status-dot--ok"
end
