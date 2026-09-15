defmodule WebWeb.RidesLive.Index do
  @moduledoc """
  The Activities archive. The sport filter lives in the URL (`?sport=jogging`)
  so any view of it can be linked, the way `/logs` keeps its keyword filter.
  """
  use WebWeb, :live_view

  alias Web.Rides
  alias Web.Rides.Units
  alias WebWeb.Activity

  def mount(_params, session, socket) do
    rides = Rides.list_rides()

    {:ok,
     assign(socket,
       is_admin: session["admin_user"] == true,
       rides: rides,
       shelves: Rides.shelves(rides)
     )}
  end

  def handle_params(params, _uri, socket) do
    %{rides: rides, shelves: shelves} = socket.assigns
    sport = selected_sport(params["sport"], shelves)
    visible = if sport, do: Enum.filter(rides, &(&1.sport == sport)), else: rides

    {:noreply,
     assign(socket,
       page_title: if(sport, do: "#{Units.sport(sport)} · Activities", else: "Activities"),
       sport: sport,
       featured: List.first(visible),
       visible_shelves: Enum.filter(shelves, fn {key, _} -> is_nil(sport) or key == sport end),
       years: Rides.yearly_totals(visible)
     )}
  end

  # Only a sport that actually has a shelf; anything else means All, so a stale
  # or hand-edited link never renders an empty page.
  defp selected_sport(key, shelves) when is_binary(key) do
    if List.keymember?(shelves, key, 0), do: key
  end

  defp selected_sport(_key, _shelves), do: nil

  # "2026 · 57 activities · 608.7 mi · 18,749 ft up"
  defp totals_line(year) do
    count = if year.rides == 1, do: "1 activity", else: "#{year.rides} activities"

    Enum.join(
      [
        year.year,
        count,
        Units.distance(year.distance_m),
        Units.elevation(year.ascent_m) <> " up"
      ],
      " · "
    )
  end

  def render(assigns) do
    ~H"""
    <div class="blog-bento-wrapper steel activities">
      <header class="blog-header-card">
        <h1 class="blog-header-title">Activities</h1>
        <div class="blog-header-subtitle">Recorded on Komoot</div>
      </header>

      <WebWeb.FitnessSubnav.subnav active={:rides} is_admin={@is_admin} />

      <p :if={@rides == []} class="activities-empty">
        Nothing synced yet. Activities recorded on Komoot land here within the hour.
      </p>

      <Activity.pills
        :if={@shelves != []}
        shelves={@shelves}
        total={length(@rides)}
        selected={@sport}
      />

      <%!-- The lightbox: the newest activity in view owns the first screen. --%>
      <article :if={@featured} class="activity-feature">
        <Activity.meta ride={@featured} />
        <h2 class="activity-title">
          <.link navigate={~p"/fitness/rides/#{@featured.id}"}>{Activity.title(@featured)}</.link>
        </h2>
        <.link navigate={~p"/fitness/rides/#{@featured.id}"} class="activity-map-link">
          <Activity.route_map ride={@featured} />
        </.link>
        <Activity.figures ride={@featured} />
      </article>

      <Activity.shelf
        :for={{sport, rides} <- @visible_shelves}
        sport={sport}
        rides={rides}
        layout={if @sport, do: :grid, else: :strip}
      />

      <footer :if={@years != []} class="activity-totals">
        <p :for={year <- @years}>{totals_line(year)}</p>
      </footer>
    </div>
    """
  end
end
