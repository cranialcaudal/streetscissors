defmodule WebWeb.AdminLive.RidesManager do
  use WebWeb, :live_view

  alias Web.Rides
  alias Web.Rides.{KomootSync, Units}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Activities | Admin",
       komoot_enabled: KomootSync.enabled?(),
       sync_running: false
     )
     |> load_rides()}
  end

  defp load_rides(socket), do: assign(socket, rides: Rides.list_rides())

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
        {:noreply, put_flash(socket, :error, "Komoot sync failed: #{inspect(reason)}")}
    end
  end

  def handle_async(:komoot_sync, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(sync_running: false)
     |> put_flash(:error, "Komoot sync crashed: #{inspect(reason)}")}
  end

  def render(assigns) do
    ~H"""
    <div class="rides-admin">
      <h1 class="rides-admin-title">Activities</h1>

      <section class="rides-admin-panel">
        <h2>Komoot sync</h2>
        <%= if @komoot_enabled do %>
          <p class="rides-admin-hint">
            The rides page mirrors every tour you record on Komoot, checked hourly.
            Edits, privacy changes, and deletions in the app carry over on their own.
            Private tours are listed too, with the route image in place of Komoot's embed.
          </p>
          <button phx-click="sync_komoot" class="theme-btn" disabled={@sync_running}>
            {if @sync_running, do: "Syncing…", else: "Sync now"}
          </button>
        <% else %>
          <p class="rides-admin-hint">
            Disabled — set <code>KOMOOT_EMAIL</code>
            and <code>KOMOOT_PASSWORD</code>
            in the environment.
          </p>
        <% end %>
      </section>

      <section class="rides-admin-panel">
        <h2>Archive ({length(@rides)})</h2>
        <table class="rides-admin-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Date</th>
              <th>Sport</th>
              <th>Distance</th>
              <th>Komoot</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={ride <- @rides}>
              <td>{ride.name || "Untitled"}</td>
              <td>{Units.date(ride.started_at)}</td>
              <td>{Units.sport(ride.sport)}</td>
              <td>{Units.distance(ride.distance_m)}</td>
              <td class={ride.visibility == "private" && "rides-admin-private"}>
                {ride.visibility}
              </td>
              <td>
                <.link navigate={~p"/fitness/rides/#{ride.id}"} class="rides-admin-view">view</.link>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <style>
        .rides-admin { max-width: 900px; color: #ddd; }
        .rides-admin-title { font-size: 1.8rem; font-weight: 800; color: #fff; margin-bottom: 2rem; }
        .rides-admin-panel { background: rgba(255,255,255,0.03); border: 1px solid #2a2a2a; border-radius: 10px; padding: 1.5rem; margin-bottom: 1.5rem; }
        .rides-admin-panel h2 { font-size: 1rem; text-transform: uppercase; letter-spacing: 2px; color: #999; margin-bottom: 1rem; }
        .rides-admin-hint { color: #777; font-size: 0.85rem; margin: 0.5rem 0 1rem; }
        .rides-admin-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
        .rides-admin-table th { text-align: left; color: #777; padding: 0.4rem 0.5rem; border-bottom: 1px solid #2a2a2a; font-weight: 600; }
        .rides-admin-table td { padding: 0.4rem 0.5rem; border-bottom: 1px solid #1a1a1a; }
        .rides-admin-view { color: #9db8f0; }
        .rides-admin-private { color: #f87171; }
      </style>
    </div>
    """
  end
end
