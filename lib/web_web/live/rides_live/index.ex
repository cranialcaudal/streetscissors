defmodule WebWeb.RidesLive.Index do
  use WebWeb, :live_view

  alias Web.Rides
  alias Web.SiteSettings
  alias WebWeb.RidesLive.Format

  def mount(_params, session, socket) do
    {:ok,
     assign(socket,
       page_title: "Rides",
       is_admin: session["admin_user"] == true,
       planned: Rides.list_planned_rides(),
       rides: Rides.list_recorded_rides(),
       komoot_embed: komoot_embed_url()
     )}
  end

  defp komoot_embed_url do
    case SiteSettings.get_setting("komoot_embed_url") do
      "https://www.komoot." <> _ = url -> url
      _ -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <div class="rides-container">
      <WebWeb.FitnessSubnav.subnav active={:rides} is_admin={@is_admin} />

      <header class="rides-header">
        <h1 class="rides-title">Rides</h1>
        <p class="rides-sub">GPS tracks synced from Komoot</p>
      </header>

      <section :if={@planned != []} class="ride-planned">
        <h2 class="ride-archive-heading">Planned routes</h2>

        <.link
          :for={ride <- @planned}
          navigate={~p"/fitness/rides/#{ride.id}"}
          class="ride-card ride-card--planned"
        >
          <div class="ride-card-main">
            <span class="ride-card-name">{ride.name || "Untitled route"}</span>
            <span class="ride-card-date">planned</span>
          </div>
          <div class="ride-card-stats">
            <span>{Format.distance(ride.distance_m)}</span>
            <span>{Format.elevation(ride.ascent_m)} ↑</span>
          </div>
        </.link>
      </section>

      <section class="ride-archive">
        <h2 :if={@planned != []} class="ride-archive-heading">Rides</h2>

        <p :if={@rides == []} class="rides-empty">
          No rides logged yet. The next one will land here straight from Komoot.
        </p>

        <.link :for={ride <- @rides} navigate={~p"/fitness/rides/#{ride.id}"} class="ride-card">
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

      <section :if={@komoot_embed}>
        <h2 class="ride-archive-heading">On Komoot</h2>
        <iframe
          src={@komoot_embed}
          class="ride-komoot-embed"
          title="Komoot profile"
          loading="lazy"
        >
        </iframe>
      </section>
    </div>
    """
  end
end
