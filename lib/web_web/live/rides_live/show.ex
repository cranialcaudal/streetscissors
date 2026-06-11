defmodule WebWeb.RidesLive.Show do
  use WebWeb, :live_view

  alias Web.Rides
  alias WebWeb.RidesLive.Format

  def mount(%{"id" => id}, _session, socket) do
    ride = Rides.get_ride!(id)

    socket =
      socket
      |> assign(ride: ride, page_title: ride.name || "Ride")
      |> push_trail(ride)

    {:ok, socket}
  end

  defp push_trail(socket, ride) do
    if connected?(socket) do
      points = Rides.list_points(ride)

      socket
      |> push_event("ride:init", %{points: Format.encode_points(points)})
      |> push_event("elevation:init", Format.elevation_series(points))
    else
      socket
    end
  end

  def render(assigns) do
    ~H"""
    <div class="rides-container">
      <header class="rides-header ride-show-header">
        <.link navigate={~p"/fitness/rides"} class="ride-back">&larr; all rides</.link>
        <h1 class="rides-title">{@ride.name || "Untitled ride"}</h1>
        <p class="rides-sub">
          <%= if @ride.kind == "planned" do %>
            planned route
          <% else %>
            {Format.date(@ride.started_at)}
          <% end %>
          <span :if={@ride.source == "komoot"} class="ride-source-tag">komoot</span>
          <span :if={@ride.source == "gpx"} class="ride-source-tag">imported</span>
        </p>
      </header>

      <div class="ride-stats-grid">
        <div class="ride-stat">
          <span class="ride-stat-value">{Format.distance(@ride.distance_m)}</span>
          <span class="ride-stat-label">distance</span>
        </div>
        <%= if @ride.kind == "recorded" do %>
          <div class="ride-stat">
            <span class="ride-stat-value">{Format.duration(@ride.duration_s)}</span>
            <span class="ride-stat-label">moving time</span>
          </div>
          <div class="ride-stat">
            <span class="ride-stat-value">{Format.speed(@ride.avg_speed_mps)}</span>
            <span class="ride-stat-label">avg speed</span>
          </div>
          <div class="ride-stat">
            <span class="ride-stat-value">{Format.speed(@ride.max_speed_mps)}</span>
            <span class="ride-stat-label">max speed</span>
          </div>
        <% end %>
        <div class="ride-stat">
          <span class="ride-stat-value">{Format.elevation(@ride.ascent_m)}</span>
          <span class="ride-stat-label">ascent</span>
        </div>
        <div class="ride-stat">
          <span class="ride-stat-value">{Format.elevation(@ride.descent_m)}</span>
          <span class="ride-stat-label">descent</span>
        </div>
      </div>

      <div
        id={"ride-map-#{@ride.id}"}
        class="ride-map"
        phx-hook="RideMap"
        phx-update="ignore"
      >
      </div>

      <canvas
        id={"ride-elevation-#{@ride.id}"}
        class="ride-elevation"
        phx-hook="ElevationProfile"
        phx-update="ignore"
      >
      </canvas>

      <p :if={@ride.description} class="ride-description">{@ride.description}</p>

      <iframe
        :if={@ride.komoot_id}
        src={"https://www.komoot.com/tour/#{@ride.komoot_id}/embed?profile=1"}
        class="ride-komoot-embed"
        title="Komoot tour"
        loading="lazy"
      >
      </iframe>
    </div>
    """
  end
end
