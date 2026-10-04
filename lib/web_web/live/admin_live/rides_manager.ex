defmodule WebWeb.AdminLive.RidesManager do
  @moduledoc """
  Activities: the Komoot mirror's one control and its contents.

  There is nothing to edit here — Komoot is the only input — so the page is a
  "Sync now" button, when the last pass ran and what came of it
  (`KomootSync.last_run/0`, written by every pass, hourly or manual), and the
  archive, plus the privacy zones the published routes are cut by — how many,
  never where.
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
     |> load_rides()}
  end

  defp load_rides(socket),
    do: assign(socket, rides: Rides.list_rides(), last_run: KomootSync.last_run())

  def handle_event("sync_komoot", _params, socket) do
    {:noreply,
     socket
     |> assign(sync_running: true)
     # force: true — the button exists for "read Komoot again now", so it
     # must not be answered by a cached ETag saying nothing changed.
     |> start_async(:komoot_sync, fn -> KomootSync.sync(force: true) end)}
  end

  def handle_async(:komoot_sync, {:ok, result}, socket) do
    socket = assign(socket, sync_running: false)

    case result do
      {:ok, summary} ->
        {:noreply,
         socket
         |> load_rides()
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
         |> load_rides()
         |> put_flash(:error, "Komoot sync failed: #{inspect(reason)}")}
    end
  end

  def handle_async(:komoot_sync, {:exit, reason}, socket) do
    KomootSync.record_run({:error, {:crashed, reason}})

    {:noreply,
     socket
     |> assign(sync_running: false)
     |> load_rides()
     |> put_flash(:error, "Komoot sync crashed: #{inspect(reason)}")}
  end

  def render(assigns) do
    ~H"""
    <.page_head slug="Sync / Activities" title="Activities">
      <:lede>
        Every tour recorded on Komoot, checked hourly. Edits, privacy changes and deletions in
        the app carry over on their own.
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

    <.panel title="Komoot">
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
        <li :if={@komoot_enabled}>
          <span class={["adm-status-dot", zones_class(@zones)]} aria-hidden="true"></span>
          <span class="adm-status-name">Privacy zones</span>
          <span class="adm-status-detail">{zones_line(@zones)}</span>
        </li>
      </ul>
    </.panel>

    <.panel title="Archive" count={length(@rides)}>
      <.rows id="rides" rows={@rides} row_id={&"ride-#{&1.id}"}>
        <:col :let={ride} label="Name" class="adm-cell-title">{ride.name || "Untitled"}</:col>
        <:col :let={ride} label="Date">{Units.date(ride.started_at)}</:col>
        <:col :let={ride} label="Sport">{Units.sport(ride.sport)}</:col>
        <:col :let={ride} label="Distance" class="adm-cell-num">
          {Units.distance(ride.distance_m)}
        </:col>
        <:col :let={ride} label="On Komoot">
          <.pill :if={ride.visibility == "private"} tone="quiet" class="ride-private">Private</.pill>
          <.pill :if={ride.visibility != "private"} tone="live">Public</.pill>
          <.pill :if={is_nil(ride.route_key)} tone="held">No track yet</.pill>
        </:col>
        <:action :let={ride}>
          <.link navigate={~p"/fitness/rides/#{ride.id}"} class="adm-link">View</.link>
        </:action>
        <:empty>Nothing synced yet.</:empty>
      </.rows>
    </.panel>
    """
  end

  defp run_line(%{at: nil}), do: "No pass recorded yet."
  defp run_line(%{at: at, detail: detail}), do: "#{ago(at)} — #{detail}"

  defp zones_line(:invalid),
    do: "RIDE_PRIVACY_ZONES can't be read — every route is hidden until it is fixed."

  defp zones_line({:ok, []}),
    do: "None set — routes are published whole. Set RIDE_PRIVACY_ZONES (lat,lng,radius_m)."

  defp zones_line({:ok, [_]}), do: "1 zone — routes are cut where they enter it."

  defp zones_line({:ok, zones}),
    do: "#{length(zones)} zones — routes are cut where they enter one."

  defp zones_class({:ok, [_ | _]}), do: "adm-status-dot--ok"
  defp zones_class({:ok, []}), do: "adm-status-dot--warn"
  defp zones_class(:invalid), do: "adm-status-dot--fail"

  defp run_class(:ok), do: "adm-status-dot--ok"
  defp run_class(:partial), do: "adm-status-dot--warn"
  defp run_class(:failed), do: "adm-status-dot--fail"
  defp run_class(_), do: nil
end
