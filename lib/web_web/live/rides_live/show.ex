defmodule WebWeb.RidesLive.Show do
  @moduledoc """
  One activity: the power the ride took, estimated in R, then Komoot's embed
  with the map, its figures and the elevation profile.
  """
  use WebWeb, :live_view

  alias Web.Rides
  alias WebWeb.Activity

  def mount(%{"id" => id}, session, socket) do
    ride = Rides.get_ride(id) || raise Ecto.NoResultsError, queryable: Web.Rides.Ride

    # Komoot's embed and its link carry the tour's id (and a private tour's
    # share token), which open the author's page there: only the admin gets them.
    admin? = session["admin_user"] == true

    {:ok,
     assign(socket,
       is_admin: admin?,
       ride: ride,
       komoot_url: admin? && Rides.tour_url(ride),
       page_title: Activity.title(ride, admin?)
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="blog-bento-wrapper steel activities">
      <.link navigate={~p"/fitness/rides"} class="activity-back">&larr; All activities</.link>

      <article class="activity-feature">
        <Activity.meta ride={@ride} />
        <h1 class="activity-title">{Activity.title(@ride, @is_admin)}</h1>

        <Activity.power ride={@ride} />

        <%!-- Komoot's embed for every tour it will show — a private one through
              its share token — else the static map cached at sync time. --%>
        <Activity.plate ride={@ride} downhill loading="eager" admin={@is_admin} />

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
