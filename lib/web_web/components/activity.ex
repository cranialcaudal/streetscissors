defmodule WebWeb.Activity do
  @moduledoc """
  The pieces an activity is drawn from, shared by the Activities archive and
  each ride page: the sport pills, the meta line, the plate (Komoot's own
  embed), the recent-training band, and the shelves of cards.

  **Komoot draws the rest.** The plate is its live embed — map, stats,
  elevation profile and photographs — for every tour it can show, private
  ones through their share token. Komoot cuts its privacy zones out of what
  it draws for a visitor, which is what makes the embed safe to show. Only a
  tour the sync has read as a stranger and found clear (`Web.Rides.clear?/1`)
  gets it: one the tripwire found exposed, one Komoot hides altogether, and
  one not looked at yet get no embed, no map image and no link, only their
  figures.

  Everything reads in Komoot's vocabulary (`Web.Rides.Units`), and a sport
  takes its family's pigment through an `activity--<kind>` class — the same
  colors The Week gives bike and run blocks on /fitness.

  ## How this file is laid out

  1. **The plate** (`title/1` to `figures/1`): the newest activity, large,
     with Komoot's map and its figures.
  2. **Recent totals and the route map** (`recent/1`, `route_map/1`).
  3. **Shelves and cards** (`shelf/1`, `card/1`): one sideways row per
     sport, of small cards.
  """
  use Phoenix.Component
  use WebWeb, :verified_routes

  alias Web.Rides
  alias Web.Rides.Units

  # ── The plate: title, sport pills and figures ─────────────────────────────

  @doc """
  What an activity is called. A visitor is told only its sport and distance
  (`Bike touring · 17.6 mi`): Komoot names are written for the author and
  often name a road, a creek or a neighbourhood. The admin (`admin?`) sees
  the name, or the sport when Komoot has none.
  """
  def title(ride, admin? \\ false)

  def title(ride, true), do: ride.name || Units.sport(ride.sport)

  def title(ride, _admin?),
    do: Units.sport(ride.sport) <> " · " <> Units.distance(ride.distance_m)

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
      <.link
        href={~p"/day/#{Date.to_iso8601(Web.Clock.local_today(@ride.started_at))}"}
        class="day-link"
      >
        {Units.day(@ride.started_at)}
      </.link>
    </p>
    """
  end

  attr :ride, :map, required: true
  attr :link, :boolean, default: false, doc: "link the fallback map to the ride's page"
  attr :downhill, :boolean, default: false
  attr :loading, :string, default: "lazy", values: ~w(lazy eager)
  attr :admin, :boolean, default: false, doc: "only the admin is given Komoot's live embed"

  @doc """
  The activity itself: Komoot's embed when Komoot will show the tour, the
  tripwire allows it and the reader is the admin, else the cached route
  image — or a blank plate — with our own figures beneath it. A visitor is
  never handed the embed: its address carries the tour's id (and, for a
  private tour, its share token), which opens the author's Komoot page.
  """
  def plate(assigns) do
    assigns = assign(assigns, :src, assigns.admin && Rides.embed_url(assigns.ride))

    ~H"""
    <iframe
      :if={@src}
      id={"komoot-embed-#{@ride.id}"}
      src={@src}
      class="activity-embed"
      title={"#{title(@ride, @admin)} on Komoot"}
      loading={@loading}
      allow="fullscreen"
    ></iframe>
    <.link
      :if={!@src && @link}
      navigate={~p"/fitness/rides/#{@ride.id}"}
      class="activity-map-link"
    >
      <.route_map ride={@ride} admin={@admin} />
    </.link>
    <.route_map :if={!@src && !@link} ride={@ride} admin={@admin} />
    <.figures :if={!@src} ride={@ride} downhill={@downhill} />
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

  # ── Power, estimated ──────────────────────────────────────────────────────

  attr :ride, :map, required: true

  @doc """
  The power the ride took, as `analysis/ride_power.R` estimated it from the
  route's speed and climb (or, with no route to read, the ride's totals): no
  power meter measured it, and the panel says so. Renders nothing without an
  estimate.
  """
  def power(assigns) do
    estimate = Web.Rides.Power.for_ride(assigns.ride)

    figures =
      if estimate,
        do:
          for(
            {label, value, format} <- [
              {"Avg power", estimate["avg_w"], &Units.watts/1},
              {"Peak power", estimate["peak_w"], &Units.watts/1},
              {"Work", estimate["work_kj"], &Units.kilojoules/1}
            ],
            is_number(value),
            do: {label, format.(value)}
          ),
        else: []

    assigns =
      assign(assigns,
        figures: figures,
        basis:
          if(estimate && estimate["basis"] == "totals",
            do: "from the ride's distance, time and climb",
            else: "from the route's speed and climb"
          )
      )

    ~H"""
    <section
      :if={@figures != []}
      class="activity-power"
      aria-labelledby={"activity-power-#{@ride.id}"}
    >
      <header class="activity-health-head">
        <h2 id={"activity-power-#{@ride.id}"} class="activity-health-title">
          <span class="activity-power-mark" aria-hidden="true">≈</span> Power, estimated
        </h2>
        <p class="activity-health-source">No power meter · worked out in R {@basis}</p>
      </header>

      <dl class="activity-figures">
        <div :for={{label, value} <- @figures} class="activity-figure">
          <dt class="activity-figure-label">{label}</dt>
          <dd class="activity-figure-value">{value}</dd>
        </div>
      </dl>
    </section>
    """
  end

  attr :week, :map, required: true, doc: "`Web.Rides.recent(rides, 7)`"
  attr :month, :map, required: true, doc: "`Web.Rides.recent(rides, 28)`"

  # ── Recent totals and the route map ───────────────────────────────────────

  @doc """
  The last seven and the last twenty-eight days at a glance: how often, how
  long, how far.
  """
  def recent(assigns) do
    ~H"""
    <section class="activity-recent" aria-label="Recent training">
      <div :for={{days, totals} <- [{7, @week}, {28, @month}]} id={"recent-#{days}"}>
        <h2 class="activity-recent-title">Last {days} days</h2>
        <dl class="activity-figures">
          <div :for={{name, value} <- recent_figures(totals)} class="activity-figure">
            <dt class="activity-figure-label">{name}</dt>
            <dd class="activity-figure-value">{value}</dd>
          </div>
        </dl>
      </div>
    </section>
    """
  end

  defp recent_figures(totals) do
    [
      {"Activities", to_string(totals.rides)},
      {"Time moving", Units.duration(totals.moving_s)},
      {"Distance", Units.distance(totals.distance_m)}
    ]
  end

  attr :ride, :map, required: true
  attr :admin, :boolean, default: false

  @doc """
  Komoot's own picture of the route, as it draws it for a stranger, or a
  blank plate when none is cached or the ride is not clear.
  """
  def route_map(assigns) do
    assigns = assign(assigns, :thumb, Rides.thumb_src(assigns.ride))

    ~H"""
    <img
      :if={@thumb}
      src={@thumb}
      alt={"Route map of #{title(@ride, @admin)}"}
      class="activity-map"
    />
    <div :if={!@thumb} class="activity-map activity-map--blank">{Units.sport(@ride.sport)}</div>
    """
  end

  attr :sport, :string, required: true
  attr :rides, :list, required: true
  attr :layout, :atom, default: :strip, values: [:strip, :grid]
  attr :admin, :boolean, default: false

  # ── Shelves and cards ─────────────────────────────────────────────────────

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
        <.card :for={ride <- @rides} ride={ride} admin={@admin} />
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
  attr :admin, :boolean, default: false

  @doc """
  One activity on a shelf, set the way Komoot sets a tour card: its route map
  at full colour, then name, day and Komoot's figures.
  """
  def card(assigns) do
    assigns = assign(assigns, :thumb, Rides.thumb_src(assigns.ride))

    ~H"""
    <.link navigate={~p"/fitness/rides/#{@ride.id}"} class="activity-card">
      <span class="activity-card-map">
        <img :if={@thumb} src={@thumb} alt="" loading="lazy" />
        <span :if={!@thumb} class="activity-card-blank">{Units.sport(@ride.sport)}</span>
      </span>
      <span class="activity-card-body">
        <span class="activity-card-name">{title(@ride, @admin)}</span>
        <span class="activity-card-day">{Units.day(@ride.started_at)}</span>
        <span class="activity-card-stats">{card_stats(@ride)}</span>
        <span :if={card_power(@ride)} class="activity-card-power">
          <span class="activity-power-mark" aria-hidden="true">≈</span> {card_power(@ride)}
        </span>
      </span>
    </.link>
    """
  end

  defp card_stats(ride) do
    Enum.join(
      [
        Units.distance(ride.distance_m),
        Units.duration(ride.time_in_motion_s || ride.duration_s),
        Units.elevation(ride.ascent_m) <> " up"
      ],
      " · "
    )
  end

  defp card_power(ride) do
    case Web.Rides.Power.for_ride(ride) do
      %{"avg_w" => avg, "peak_w" => peak} when is_number(avg) and is_number(peak) ->
        "#{Units.count(round(avg / 5) * 5)} W avg · #{Units.count(round(peak / 5) * 5)} W peak"

      %{"avg_w" => avg} when is_number(avg) ->
        "#{Units.count(round(avg / 5) * 5)} W avg"

      _ ->
        nil
    end
  end
end
