defmodule WebWeb.AdminLive.RidesManager do
  use WebWeb, :live_view

  alias Web.Rides
  alias Web.Rides.Privacy
  alias WebWeb.RidesLive.Format

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Rides | Admin",
       zones_json: Web.SiteSettings.get_setting(Privacy.setting_key(), "[]"),
       overland_url: overland_url(),
       gpx_results: []
     )
     |> load_rides()
     |> allow_upload(:gpx,
       accept: ~w(.gpx),
       max_entries: 5,
       max_file_size: 20_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  defp load_rides(socket) do
    assign(socket,
      active_ride: Rides.get_active_ride(),
      rides: Rides.list_completed_rides()
    )
  end

  def handle_event("start_ride", %{"name" => name}, socket) do
    {:ok, _ride} = Rides.start_ride(%{"name" => name})
    {:noreply, socket |> load_rides() |> put_flash(:info, "Ride started — tracker is live.")}
  end

  def handle_event("stop_ride", _params, socket) do
    case socket.assigns.active_ride do
      nil ->
        {:noreply, socket}

      ride ->
        {:ok, _ride} = Rides.stop_ride(ride)
        {:noreply, socket |> load_rides() |> put_flash(:info, "Ride completed and archived.")}
    end
  end

  def handle_event("rename_ride", %{"id" => id, "value" => name}, socket) do
    ride = Rides.get_ride!(id)
    {:ok, _ride} = Rides.update_ride(ride, %{"name" => name})
    {:noreply, load_rides(socket)}
  end

  def handle_event("delete_ride", %{"id" => id}, socket) do
    {:ok, _ride} = id |> Rides.get_ride!() |> Rides.delete_ride()
    {:noreply, socket |> load_rides() |> put_flash(:info, "Ride deleted.")}
  end

  def handle_event("save_zones", %{"zones" => json}, socket) do
    case Jason.decode(json) do
      {:ok, zones} when is_list(zones) ->
        {:ok, _setting} = Web.SiteSettings.put_setting(Privacy.setting_key(), json)
        {:noreply, assign(socket, zones_json: json) |> put_flash(:info, "Privacy zones saved.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid JSON — expected a list of zones.")}
    end
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  defp handle_progress(:gpx, entry, socket) do
    if entry.done? do
      results =
        consume_uploaded_entries(socket, :gpx, fn %{path: path}, meta ->
          name = meta.client_name |> Path.basename(".gpx") |> String.replace("-", " ")

          case Rides.import_gpx(File.read!(path), %{"name" => name}) do
            {:ok, ride} -> {:ok, {:imported, ride}}
            {:error, reason} -> {:ok, {:failed, meta.client_name, reason}}
          end
        end)

      {:noreply,
       socket
       |> load_rides()
       |> assign(gpx_results: results ++ socket.assigns.gpx_results)}
    else
      {:noreply, socket}
    end
  end

  defp overland_url do
    WebWeb.Endpoint.url() <>
      "/api/overland?token=" <> to_string(Application.get_env(:web, :overland_token))
  end

  def render(assigns) do
    ~H"""
    <div class="rides-admin">
      <h1 class="rides-admin-title">Ride Tracking</h1>

      <section class="rides-admin-panel">
        <h2>Live ride</h2>
        <%= if @active_ride do %>
          <p class="rides-admin-live">
            <span class="live-dot" aria-hidden="true"></span>
            <strong>{@active_ride.name || "Unnamed ride"}</strong>
            active since {Format.time(@active_ride.started_at)} UTC · {@active_ride.point_count} points
          </p>
          <button phx-click="stop_ride" class="theme-btn rides-admin-stop">
            Stop &amp; archive ride
          </button>
        <% else %>
          <form phx-submit="start_ride" class="rides-admin-start">
            <input
              type="text"
              name="name"
              placeholder="Ride name (e.g. Fred Whitton Challenge)"
              autocomplete="off"
            />
            <button type="submit" class="theme-btn">Start ride</button>
          </form>
          <p class="rides-admin-hint">
            Start the ride here, then begin tracking in Overland. Stale rides auto-close
            after 3 hours without points.
          </p>
        <% end %>
      </section>

      <section class="rides-admin-panel">
        <h2>Phone setup</h2>
        <p class="rides-admin-hint">
          Overland &rarr; Settings &rarr; Receiver Endpoint URL:
        </p>
        <input
          type="text"
          readonly
          value={@overland_url}
          class="rides-admin-url"
          onclick="this.select(); document.execCommand('copy');"
        />
        <p class="rides-admin-hint">(click to copy — contains the secret token)</p>
      </section>

      <section class="rides-admin-panel">
        <h2>Import GPX</h2>
        <p class="rides-admin-hint">
          Komoot: tour &rarr; share &rarr; export GPX. Apple Watch: export via HealthFit.
        </p>
        <form phx-change="validate">
          <.live_file_input upload={@uploads.gpx} />
        </form>
        <div :for={entry <- @uploads.gpx.entries} class="rides-admin-hint">
          uploading {entry.client_name}… {entry.progress}%
        </div>
        <ul :if={@gpx_results != []} class="rides-admin-results">
          <li :for={result <- @gpx_results}>
            <%= case result do %>
              <% {:imported, ride} -> %>
                ✓ imported “{ride.name}” — {Format.distance(ride.distance_m)}
              <% {:failed, name, reason} -> %>
                ✗ {name} failed: {inspect(reason)}
            <% end %>
          </li>
        </ul>
      </section>

      <section class="rides-admin-panel">
        <h2>Privacy zones</h2>
        <p class="rides-admin-hint">
          Points inside these zones are stored but never shown publicly. JSON list:
          <code>{~s|[{"lat": 38.58, "lon": -121.49, "radius_m": 1000}]|}</code>
        </p>
        <form phx-submit="save_zones">
          <textarea name="zones" rows="4" class="rides-admin-zones">{@zones_json}</textarea>
          <button type="submit" class="theme-btn">Save zones</button>
        </form>
      </section>

      <section class="rides-admin-panel">
        <h2>Archive ({length(@rides)})</h2>
        <table class="rides-admin-table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Date</th>
              <th>Distance</th>
              <th>Points</th>
              <th>Source</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={ride <- @rides}>
              <td>
                <input
                  type="text"
                  value={ride.name}
                  phx-blur="rename_ride"
                  phx-value-id={ride.id}
                  placeholder="Untitled ride"
                />
              </td>
              <td>{Format.date(ride.started_at)}</td>
              <td>{Format.distance(ride.distance_m)}</td>
              <td>{ride.point_count}</td>
              <td>{ride.source}</td>
              <td>
                <.link navigate={~p"/rides/#{ride.id}"} class="rides-admin-view">view</.link>
                <button
                  phx-click="delete_ride"
                  phx-value-id={ride.id}
                  phx-confirm="Delete this ride and all its GPS points?"
                  class="rides-admin-delete"
                >
                  delete
                </button>
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
        .rides-admin-hint { color: #777; font-size: 0.85rem; margin: 0.5rem 0; }
        .rides-admin-live { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 1rem; }
        .live-dot { width: 10px; height: 10px; border-radius: 50%; background: #f43f5e; animation: live-pulse 1.5s infinite; display: inline-block; }
        @keyframes live-pulse { 0%, 100% { opacity: 1; } 50% { opacity: 0.35; } }
        .rides-admin-start { display: flex; gap: 0.75rem; }
        .rides-admin-start input, .rides-admin-url, .rides-admin-zones, .rides-admin-table input {
          background: #000; border: 1px solid #333; color: #eee; border-radius: 6px; padding: 0.5rem 0.75rem; font-family: monospace; font-size: 0.85rem;
        }
        .rides-admin-start input { flex: 1; }
        .rides-admin-url { width: 100%; color: #9db8f0; }
        .rides-admin-zones { width: 100%; margin-bottom: 0.75rem; }
        .rides-admin-stop { background: #5a2525 !important; color: #ffadad !important; }
        .rides-admin-results { margin-top: 1rem; font-size: 0.85rem; color: #9f9; list-style: none; }
        .rides-admin-table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
        .rides-admin-table th { text-align: left; color: #777; padding: 0.4rem 0.5rem; border-bottom: 1px solid #2a2a2a; font-weight: 600; }
        .rides-admin-table td { padding: 0.4rem 0.5rem; border-bottom: 1px solid #1a1a1a; }
        .rides-admin-table input { width: 100%; padding: 0.25rem 0.5rem; }
        .rides-admin-view { color: #9db8f0; margin-right: 1rem; }
        .rides-admin-delete { background: none; border: none; color: #c66; cursor: pointer; font-size: 0.85rem; }
        .rides-admin-delete:hover { color: #f88; text-decoration: underline; }
      </style>
    </div>
    """
  end
end
