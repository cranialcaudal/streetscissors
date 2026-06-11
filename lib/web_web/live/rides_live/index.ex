defmodule WebWeb.RidesLive.Index do
  use WebWeb, :live_view

  alias Web.Rides
  alias WebWeb.RidesLive.Format

  def mount(_params, _session, socket) do
    if connected?(socket), do: Rides.subscribe()

    socket =
      socket
      |> assign(page_title: "Rides")
      |> load_rides()
      |> push_active_trail()

    {:ok, socket}
  end

  def handle_info({:ride_points, ride_id, points}, socket) do
    case socket.assigns.active_ride do
      %{id: ^ride_id} ->
        {:noreply, push_event(socket, "ride:append", %{points: Format.encode_points(points)})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:ride_started, _ride}, socket) do
    {:noreply, socket |> load_rides() |> push_active_trail()}
  end

  def handle_info({:ride_stopped, _ride}, socket) do
    {:noreply, load_rides(socket)}
  end

  defp load_rides(socket) do
    assign(socket,
      active_ride: Rides.get_active_ride(),
      rides: Rides.list_completed_rides()
    )
  end

  defp push_active_trail(socket) do
    with true <- connected?(socket),
         %{} = ride <- socket.assigns.active_ride do
      points = Rides.list_points(ride)
      push_event(socket, "ride:init", %{points: Format.encode_points(points)})
    else
      _ -> socket
    end
  end

  def render(assigns) do
    ~H"""
    <div class="rides-container">
      <header class="rides-header">
        <h1 class="rides-title">Rides</h1>
        <p class="rides-sub">GPS tracks, live from the road when one is rolling</p>
      </header>

      <%= if @active_ride do %>
        <section class="ride-live-frame">
          <div class="ride-live-banner">
            <span class="live-dot" aria-hidden="true"></span>
            Live — {@active_ride.name || "ride in progress"}
            <span class="live-since">since {Format.time(@active_ride.started_at)} UTC</span>
          </div>
          <div
            id="live-ride-map"
            class="ride-map"
            phx-hook="RideMap"
            phx-update="ignore"
            data-mode="live"
          >
          </div>
        </section>
      <% end %>

      <section class="ride-archive">
        <h2 :if={@active_ride} class="ride-archive-heading">Past rides</h2>

        <p :if={@rides == [] && !@active_ride} class="rides-empty">
          No rides logged yet. The next one will show up here — live.
        </p>

        <.link :for={ride <- @rides} navigate={~p"/rides/#{ride.id}"} class="ride-card">
          <div class="ride-card-main">
            <span class="ride-card-name">{ride.name || "Untitled ride"}</span>
            <span class="ride-card-date">{Format.date(ride.started_at)}</span>
          </div>
          <div class="ride-card-stats">
            <span>{Format.distance(ride.distance_m)}</span>
            <span>{Format.duration(ride.duration_s)}</span>
            <span>{Format.speed(ride.avg_speed_mps)} avg</span>
            <span>{Format.elevation(ride.ascent_m)} ↑</span>
          </div>
        </.link>
      </section>
    </div>
    """
  end
end
