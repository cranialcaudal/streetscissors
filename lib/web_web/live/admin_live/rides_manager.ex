defmodule WebWeb.AdminLive.RidesManager do
  use WebWeb, :live_view

  alias Web.Rides
  alias Web.Rides.{KomootSync, Privacy}
  alias WebWeb.RidesLive.Format

  @embed_setting "komoot_embed_url"

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Rides | Admin",
       zones_json: Web.SiteSettings.get_setting(Privacy.setting_key(), "[]"),
       embed_url: Web.SiteSettings.get_setting(@embed_setting, ""),
       komoot_enabled: KomootSync.enabled?(),
       sync_running: false,
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
      rides: Rides.list_recorded_rides() ++ Rides.list_planned_rides()
    )
  end

  def handle_event("sync_komoot", _params, socket) do
    {:noreply,
     socket
     |> assign(sync_running: true)
     |> start_async(:komoot_sync, fn -> KomootSync.sync() end)}
  end

  def handle_event("save_embed", %{"url" => url}, socket) do
    url = String.trim(url)

    if url == "" or String.starts_with?(url, "https://www.komoot.") do
      {:ok, _setting} = Web.SiteSettings.put_setting(@embed_setting, url)
      {:noreply, assign(socket, embed_url: url) |> put_flash(:info, "Komoot embed saved.")}
    else
      {:noreply, put_flash(socket, :error, "Embed URL must start with https://www.komoot.")}
    end
  end

  def handle_event("attach_komoot", %{"id" => id, "value" => value}, socket) do
    ride = Rides.get_ride!(id)

    case String.trim(value) do
      "" ->
        {:noreply, socket}

      value ->
        case Rides.attach_komoot(ride, value) do
          {:ok, _ride} ->
            {:noreply, socket |> load_rides() |> put_flash(:info, "Komoot tour attached.")}

          {:error, :invalid_komoot_id} ->
            {:noreply, put_flash(socket, :error, "Expected a komoot tour URL or numeric id.")}

          {:error, _changeset} ->
            {:noreply,
             put_flash(socket, :error, "That komoot tour is already attached to another ride.")}
        end
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

  def handle_async(:komoot_sync, {:ok, result}, socket) do
    socket = assign(socket, sync_running: false)

    case result do
      {:ok, %{imported: imported, skipped: skipped, failed: failed}} ->
        {:noreply,
         socket
         |> load_rides()
         |> put_flash(
           :info,
           "Komoot sync: #{imported} imported, #{skipped} known, #{failed} failed."
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

  def render(assigns) do
    ~H"""
    <div class="rides-admin">
      <h1 class="rides-admin-title">Rides</h1>

      <section class="rides-admin-panel">
        <h2>Komoot sync</h2>
        <%= if @komoot_enabled do %>
          <p class="rides-admin-hint">
            New recorded and planned tours are pulled hourly. Already-imported tours are
            skipped — to refresh one, delete it below and sync again.
          </p>
          <button phx-click="sync_komoot" class="theme-btn" disabled={@sync_running}>
            {if @sync_running, do: "Syncing…", else: "Sync now"}
          </button>
        <% else %>
          <p class="rides-admin-hint">
            Disabled — set <code>KOMOOT_EMAIL</code> and <code>KOMOOT_PASSWORD</code> in the
            environment to enable auto-sync. Manual GPX import below always works.
          </p>
        <% end %>
      </section>

      <section class="rides-admin-panel">
        <h2>Komoot embed</h2>
        <p class="rides-admin-hint">
          Profile or collection embed URL shown on the rides page (komoot &rarr; share &rarr;
          embed &rarr; copy the iframe <code>src</code>). Leave empty to hide.
        </p>
        <form phx-submit="save_embed" class="rides-admin-embed">
          <input
            type="text"
            name="url"
            value={@embed_url}
            placeholder="https://www.komoot.com/…/embed"
            autocomplete="off"
          />
          <button type="submit" class="theme-btn">Save</button>
        </form>
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
          Note: an attached komoot embed shows komoot's own map — rely on komoot's
          account privacy zones there.
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
              <th>Kind</th>
              <th>Distance</th>
              <th>Source</th>
              <th>Komoot</th>
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
              <td>{ride.kind}</td>
              <td>{Format.distance(ride.distance_m)}</td>
              <td>{ride.source}</td>
              <td>
                <input
                  type="text"
                  value={ride.komoot_id}
                  phx-blur="attach_komoot"
                  phx-value-id={ride.id}
                  placeholder="tour URL or id"
                />
              </td>
              <td>
                <.link navigate={~p"/fitness/rides/#{ride.id}"} class="rides-admin-view">view</.link>
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
        .rides-admin-embed { display: flex; gap: 0.75rem; }
        .rides-admin-embed input { flex: 1; }
        .rides-admin-embed input, .rides-admin-zones, .rides-admin-table input {
          background: #000; border: 1px solid #333; color: #eee; border-radius: 6px; padding: 0.5rem 0.75rem; font-family: monospace; font-size: 0.85rem;
        }
        .rides-admin-zones { width: 100%; margin-bottom: 0.75rem; }
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
