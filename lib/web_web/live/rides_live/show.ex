defmodule WebWeb.RidesLive.Show do
  use WebWeb, :live_view

  alias Web.Rides
  alias WebWeb.Activity

  def mount(%{"id" => id}, _session, socket) do
    ride = Rides.get_ride(id) || raise Ecto.NoResultsError, queryable: Web.Rides.Ride

    {:ok,
     assign(socket,
       ride: ride,
       komoot_url: Rides.tour_url(ride),
       page_title: Activity.title(ride)
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="blog-bento-wrapper steel activities">
      <.link navigate={~p"/fitness/rides"} class="activity-back">&larr; All activities</.link>

      <article class="activity-feature">
        <Activity.meta ride={@ride} />
        <h1 class="activity-title">{Activity.title(@ride)}</h1>

        <%!-- Komoot's embed for every tour it will show — a private one through
              its share token — else the static map cached at sync time. --%>
        <Activity.plate ride={@ride} downhill loading="eager" />

        <Activity.health ride={@ride} trace />

        <a
          :if={@komoot_url}
          href={@komoot_url}
          class="activity-komoot"
          target="_blank"
          rel="noopener"
        >
          Open on Komoot <span aria-hidden="true">↗</span>
        </a>
      </article>
    </div>
    """
  end
end
