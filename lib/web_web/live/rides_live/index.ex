defmodule WebWeb.RidesLive.Index do
  use WebWeb, :live_view

  alias Web.Rides
  alias Web.Rides.LiveTracking
  alias Web.SiteSettings
  alias WebWeb.RidesLive.Format

  def mount(_params, session, socket) do
    if connected?(socket), do: LiveTracking.subscribe()

    {:ok,
     assign(socket,
       page_title: "GPX Action",
       is_admin: session["admin_user"] == true,
       live: LiveTracking.current(),
       planned: Rides.list_planned_rides(),
       rides: Rides.list_recorded_rides(),
       totals: Rides.aggregate_stats(),
       komoot_embed: komoot_embed_url()
     )}
  end

  def handle_info({:live_ride, :started, info}, socket) do
    {:noreply, assign(socket, live: info)}
  end

  def handle_info({:live_ride, :ended}, socket) do
    {:noreply, assign(socket, live: nil)}
  end

  defp komoot_embed_url do
    case SiteSettings.get_setting("komoot_embed_url") do
      "https://www.komoot." <> _ = url -> url
      _ -> nil
    end
  end

  def render(assigns) do
    ~H"""
    <div class="rides-container steel">
      <WebWeb.FitnessSubnav.subnav active={:rides} is_admin={@is_admin} />

      <header class="rides-header">
        <h1 class="rides-title">GPX Action</h1>
        <p class="rides-sub">GPS tracks synced from Komoot</p>
      </header>

      <section :if={@totals.year.rides > 0} class="ride-totals">
        <div
          :for={
            {label, period} <- [
              {"this week", @totals.week},
              {"this month", @totals.month},
              {"this year", @totals.year}
            ]
          }
          class="ride-totals-cell"
        >
          <span class="ride-totals-label">{label}</span>
          <span class="ride-totals-value">{Format.distance(period.distance_m)}</span>
          <span class="ride-totals-sub">
            {period.rides} rides · {Format.duration(period.duration_s)} · {Format.elevation(
              period.ascent_m
            )} ↑
          </span>
        </div>
        <div :if={@totals.by_sport != []} class="ride-totals-cell">
          <span class="ride-totals-label">by sport</span>
          <span class="ride-totals-sub">
            <span :for={s <- @totals.by_sport} class="ride-totals-sport">
              {s.sport || "other"} · {Format.distance(s.distance_m)} ({s.rides})
            </span>
          </span>
        </div>
      </section>

      <.link
        :if={@live}
        navigate={~p"/fitness/rides/live"}
        id="rides-live-banner"
        class="rides-live-banner"
      >
        <span class="live-dot" aria-hidden="true"></span> LIVE — follow the ride
      </.link>

      <div class="rides-columns">
        <section class="ride-archive">
          <h2 class="ride-archive-heading">Recent activity</h2>

          <p :if={@rides == []} class="rides-empty">
            Nothing public yet. Activities land here from Komoot as soon as they're
            public there.
          </p>

          <.link :for={ride <- @rides} navigate={~p"/fitness/rides/#{ride.id}"} class="ride-card">
            <img
              :if={Web.Rides.Thumbs.exists?(ride)}
              class="ride-card-thumb"
              src={~p"/fitness/rides/#{ride.id}/thumb"}
              alt=""
              loading="lazy"
            />
            <div class="ride-card-main">
              <span class="ride-card-name">{ride.name || "Untitled ride"}</span>
              <span class="ride-card-date">{Format.date(ride.started_at)}</span>
            </div>
            <div class="ride-card-stats">
              <span>{Format.distance(ride.distance_m)}</span>
              <span>{Format.duration(ride.time_in_motion_s || ride.duration_s)}</span>
              <span>{Format.speed(ride.avg_speed_mps)} avg</span>
              <span>{Format.elevation(ride.ascent_m)} ↑</span>
              <span :if={ride.kcal}>{ride.kcal} kcal</span>
            </div>
          </.link>
        </section>

        <section :if={@planned != []} class="ride-planned">
          <h2 class="ride-archive-heading ride-archive-heading--secondary">
            Planned routes
          </h2>

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
      </div>

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
