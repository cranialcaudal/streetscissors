defmodule WebWeb.RidesLive.Show do
  use WebWeb, :live_view

  alias Web.Rides
  alias WebWeb.Activity

  def mount(%{"id" => id}, _session, socket) do
    ride = Rides.get_ride(id) || raise Ecto.NoResultsError, queryable: Web.Rides.Ride

    {:ok, assign(socket, ride: ride, page_title: Activity.title(ride))}
  end

  def render(assigns) do
    ~H"""
    <div class="blog-bento-wrapper steel activities">
      <.link navigate={~p"/fitness/rides"} class="activity-back">&larr; All activities</.link>

      <article class="activity-feature">
        <Activity.meta ride={@ride} />
        <h1 class="activity-title">{Activity.title(@ride)}</h1>

        <iframe
          :if={@ride.visibility == "public"}
          src={"https://www.komoot.com/tour/#{@ride.komoot_id}/embed?profile=1"}
          class="activity-embed"
          title="Komoot tour"
          loading="lazy"
        >
        </iframe>

        <%!-- Komoot's embed refuses tours that aren't public, so those show the
              static map cached at sync time instead. --%>
        <Activity.route_map :if={@ride.visibility != "public"} ride={@ride} />

        <Activity.figures ride={@ride} downhill />
      </article>
    </div>
    """
  end
end
