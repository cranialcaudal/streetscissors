defmodule WebWeb.Activity do
  @moduledoc """
  The pieces an activity is drawn from, shared by the Activities archive and
  each ride page: the sport pills, the meta line, the figures panel, the route
  map, and the shelves of cards.

  Everything reads in Komoot's vocabulary (`Web.Rides.Units`), and a sport
  takes its family's pigment through an `activity--<kind>` class — the same
  colors The Week gives bike and run blocks on /fitness.
  """
  use Phoenix.Component
  use WebWeb, :verified_routes

  alias Web.Rides.{Thumbs, Units}

  @doc "An activity's name, or its sport when Komoot has none."
  def title(ride), do: ride.name || Units.sport(ride.sport)

  attr :shelves, :list, required: true, doc: "`[{sport, rides}]` from `Web.Rides.shelves/1`"
  attr :total, :integer, required: true
  attr :selected, :string, default: nil

  @doc "The sport filter: All, then one pill per shelf, each patching `?sport=`."
  def pills(assigns) do
    ~H"""
    <nav class="activity-pills" aria-label="Filter by sport">
      <.link
        patch={~p"/fitness/rides"}
        class={["activity-pill", is_nil(@selected) && "is-active"]}
        aria-current={is_nil(@selected) && "page"}
      >
        All <span class="activity-pill-count">{@total}</span>
      </.link>
      <.link
        :for={{sport, rides} <- @shelves}
        patch={~p"/fitness/rides?#{[sport: sport]}"}
        class={[
          "activity-pill",
          "activity--#{Units.sport_kind(sport)}",
          @selected == sport && "is-active"
        ]}
        aria-current={@selected == sport && "page"}
      >
        <span class="activity-dot" aria-hidden="true"></span>
        {Units.sport(sport)} <span class="activity-pill-count">{length(rides)}</span>
      </.link>
    </nav>
    """
  end

  attr :ride, :map, required: true

  @doc "`Bike touring • Fri 11 Sep 2026`, the sport in its family's color."
  def meta(assigns) do
    ~H"""
    <p class={["activity-meta", "activity--#{Units.sport_kind(@ride.sport)}"]}>
      <span class="activity-sport">{Units.sport(@ride.sport)}</span>
      <span class="activity-meta-dot" aria-hidden="true">•</span>
      <span>{Units.day(@ride.started_at)}</span>
    </p>
    """
  end

  attr :ride, :map, required: true
  attr :downhill, :boolean, default: false

  @doc "The figures Komoot records for a tour, one cell each in a rounded panel."
  def figures(assigns) do
    assigns = assign(assigns, :figures, figure_list(assigns.ride, assigns.downhill))

    ~H"""
    <dl class="activity-figures">
      <div :for={{label, value} <- @figures} class="activity-figure">
        <dt class="activity-figure-label">{label}</dt>
        <dd class="activity-figure-value">{value}</dd>
      </div>
    </dl>
    """
  end

  defp figure_list(ride, downhill?) do
    [
      {"Distance", Units.distance(ride.distance_m)},
      {"Duration", Units.duration(ride.time_in_motion_s || ride.duration_s)},
      {"Avg speed", Units.speed(ride.avg_speed_mps)},
      {"Uphill", Units.elevation(ride.ascent_m)}
    ] ++ if(downhill?, do: [{"Downhill", Units.elevation(ride.descent_m)}], else: [])
  end

  attr :ride, :map, required: true

  @doc "Komoot's own rendering of the route, or a blank plate when none is cached."
  def route_map(assigns) do
    assigns = assign(assigns, :cached, Thumbs.exists?(assigns.ride))

    ~H"""
    <img
      :if={@cached}
      src={~p"/fitness/rides/#{@ride.id}/thumb"}
      alt={"Route map of #{title(@ride)}"}
      class="activity-map"
    />
    <div :if={!@cached} class="activity-map activity-map--blank">{Units.sport(@ride.sport)}</div>
    """
  end

  attr :sport, :string, required: true
  attr :rides, :list, required: true
  attr :layout, :atom, default: :strip, values: [:strip, :grid]

  @doc """
  One sport's activities under a header. As a `:strip` the cards scroll
  sideways, snapping card by card, with ‹ › buttons for anyone without a
  trackpad. As a `:grid` (one sport filtered on) they wrap instead.
  """
  def shelf(assigns) do
    assigns = assign(assigns, :id, "shelf-#{assigns.sport || "other"}")

    ~H"""
    <section
      id={@id}
      class={[
        "activity-shelf",
        "activity-shelf--#{@layout}",
        "activity--#{Units.sport_kind(@sport)}"
      ]}
      phx-hook=".ShelfScroll"
      aria-labelledby={"#{@id}-title"}
    >
      <header class="activity-shelf-head">
        <h2 id={"#{@id}-title"} class="activity-shelf-title">
          <span class="activity-dot" aria-hidden="true"></span>
          {Units.sport(@sport)}
          <span class="activity-shelf-count">{length(@rides)}</span>
        </h2>
        <div :if={@layout == :strip} class="activity-shelf-nav">
          <button
            type="button"
            class="activity-shelf-btn"
            data-shelf-step="-1"
            aria-controls={"#{@id}-strip"}
            aria-label={"Scroll #{Units.sport(@sport)} back"}
          >
            ‹
          </button>
          <button
            type="button"
            class="activity-shelf-btn"
            data-shelf-step="1"
            aria-controls={"#{@id}-strip"}
            aria-label={"Scroll #{Units.sport(@sport)} forward"}
          >
            ›
          </button>
        </div>
      </header>

      <div id={"#{@id}-strip"} class="activity-shelf-strip">
        <.card :for={ride <- @rides} ride={ride} />
      </div>
    </section>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".ShelfScroll">
      // Pages the strip by as many whole cards as fit, and keeps the buttons and
      // the edge fade honest: a button greys out at its end of the strip, and the
      // fade only shows while there is more to the right.
      export default {
        mounted() {
          this.strip = this.el.querySelector(".activity-shelf-strip")
          this.buttons = this.el.querySelectorAll("[data-shelf-step]")

          this.buttons.forEach((button) => {
            button.addEventListener("click", () => {
              const card = this.strip.querySelector(".activity-card")
              const gap = parseFloat(getComputedStyle(this.strip).columnGap) || 0
              const step = card ? card.getBoundingClientRect().width + gap : this.strip.clientWidth
              const page = Math.max(1, Math.floor((this.strip.clientWidth + gap) / step)) * step

              this.strip.scrollBy({
                left: page * Number(button.dataset.shelfStep),
                behavior: "smooth"
              })
            })
          })

          this.onChange = () => this.sync()
          this.strip.addEventListener("scroll", this.onChange, { passive: true })
          window.addEventListener("resize", this.onChange)
          this.sync()
        },

        updated() {
          this.sync()
        },

        destroyed() {
          window.removeEventListener("resize", this.onChange)
        },

        sync() {
          const max = this.strip.scrollWidth - this.strip.clientWidth
          const left = this.strip.scrollLeft

          this.el.classList.toggle("is-overflowing", max > 1)
          this.el.classList.toggle("at-end", left >= max - 1)

          this.buttons.forEach((button) => {
            button.disabled =
              Number(button.dataset.shelfStep) < 0 ? left <= 1 : left >= max - 1
          })
        }
      }
    </script>
    """
  end

  attr :ride, :map, required: true

  @doc "One activity on a shelf: its route map, then name, day, and distance · duration."
  def card(assigns) do
    assigns = assign(assigns, :cached, Thumbs.exists?(assigns.ride))

    ~H"""
    <.link navigate={~p"/fitness/rides/#{@ride.id}"} class="activity-card">
      <span class="activity-card-map">
        <img :if={@cached} src={~p"/fitness/rides/#{@ride.id}/thumb"} alt="" loading="lazy" />
        <span :if={!@cached} class="activity-card-blank">{Units.sport(@ride.sport)}</span>
      </span>
      <span class="activity-card-body">
        <span class="activity-card-name">{title(@ride)}</span>
        <span class="activity-card-day">{Units.day(@ride.started_at)}</span>
        <span class="activity-card-stats">{card_stats(@ride)}</span>
      </span>
    </.link>
    """
  end

  defp card_stats(ride) do
    Units.distance(ride.distance_m) <>
      " · " <> Units.duration(ride.time_in_motion_s || ride.duration_s)
  end
end
