defmodule WebWeb.RidesLive.LiveRide do
  use WebWeb, :live_view

  alias Web.Rides
  alias Web.Rides.LiveTracking
  alias Web.SiteSettings
  alias WebWeb.RidesLive.Format

  def mount(_params, session, socket) do
    if connected?(socket), do: LiveTracking.subscribe()

    live = LiveTracking.current()

    {:ok,
     socket
     |> assign(
       page_title: "Live ride",
       og_title: "Live ride — streetscissors",
       og_description: "Follow the ride in real time, no app needed.",
       is_admin: session["admin_user"] == true,
       live: live,
       planned: Rides.list_planned_rides(),
       latest: Rides.latest_recorded_ride(),
       komoot_embed: komoot_embed_url()
     )
     |> schedule_expiry_check()}
  end

  defp komoot_embed_url do
    case SiteSettings.get_setting("komoot_embed_url") do
      "https://www.komoot." <> _ = url -> url
      _ -> nil
    end
  end

  # Expiry never broadcasts, so a page opened mid-session re-checks on its own.
  defp schedule_expiry_check(socket) do
    with true <- connected?(socket),
         %{expires_at: expires_at} <- socket.assigns.live do
      ms = max(DateTime.diff(expires_at, DateTime.utc_now(), :millisecond), 0) + 1_000
      Process.send_after(self(), :check_live, ms)
    end

    socket
  end

  def handle_info({:live_ride, :started, info}, socket) do
    {:noreply, socket |> assign(live: info) |> schedule_expiry_check()}
  end

  def handle_info({:live_ride, :ended}, socket) do
    {:noreply, assign(socket, live: nil)}
  end

  def handle_info(:check_live, socket) do
    {:noreply, socket |> assign(live: LiveTracking.current()) |> schedule_expiry_check()}
  end

  def render(assigns) do
    ~H"""
    <div class="rides-container steel">
      <WebWeb.FitnessSubnav.subnav active={:rides} is_admin={@is_admin} />

      <header class="rides-header">
        <h1 class="rides-title">Live</h1>
        <p class="rides-sub">Follow the ride here — no app needed</p>
      </header>

      <section :if={@live} id="live-ride-active">
        <div class="ride-live-banner">
          <span class="live-dot" aria-hidden="true"></span>
          LIVE — riding now <span class="live-since">since {Format.time(@live.started_at)} UTC</span>
        </div>
        <p :if={@live.note != ""} class="live-ride-note">{@live.note}</p>

        <a
          id="live-komoot-cta"
          class="live-ride-cta"
          href={@live.url}
          target="_blank"
          rel="noopener"
        >
          Follow live on Komoot &rarr;
        </a>
      </section>

      <section :if={!@live} id="live-ride-idle">
        <p class="rides-empty">
          Not riding right now. When a ride is live, this page tracks it as it happens.
        </p>

        <section :if={@planned != []} class="ride-planned">
          <h2 class="ride-archive-heading">Up next</h2>
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

        <section :if={@latest} class="ride-archive">
          <h2 class="ride-archive-heading">Latest ride</h2>
          <.link navigate={~p"/fitness/rides/#{@latest.id}"} class="ride-card">
            <div class="ride-card-main">
              <span class="ride-card-name">{@latest.name || "Untitled ride"}</span>
              <span class="ride-card-date">{Format.date(@latest.started_at)}</span>
            </div>
            <div class="ride-card-stats">
              <span>{Format.distance(@latest.distance_m)}</span>
              <span>{Format.duration(@latest.duration_s)}</span>
              <span>{Format.speed(@latest.avg_speed_mps)} avg</span>
              <span>{Format.elevation(@latest.ascent_m)} ↑</span>
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
      </section>
    </div>
    """
  end
end
