defmodule WebWeb.RidesLive.Show do
  use WebWeb, :live_view

  alias Web.Rides
  alias WebWeb.Activity

  def mount(%{"id" => id}, _session, socket) do
    ride = Rides.get_ride(id) || raise Ecto.NoResultsError, queryable: Web.Rides.Ride

    {:ok,
     assign(socket,
       ride: ride,
       route: Rides.route(ride),
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

        <Activity.plate ride={@ride} route={@route} downhill />
      </article>
    </div>
    """
  end
end
