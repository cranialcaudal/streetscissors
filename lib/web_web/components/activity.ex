defmodule WebWeb.Activity do
  @moduledoc """
  The pieces an activity is drawn from, shared by the Activities archive and
  each ride page: the sport pills, the meta line, the plate (Komoot's own
  embed), the health panel, and the shelves of cards.

  Komoot draws the activity wherever there is room for it: the plate is its
  live embed — map, stats and elevation profile — for every tour it can show,
  private ones through their share token. Only a private tour whose token
  hasn't synced yet falls back to the cached route image and our own figures.
  What the watch measured (heart rate, energy) comes from Apple Health, since
  Komoot keeps none of it.

  Everything reads in Komoot's vocabulary (`Web.Rides.Units`), and a sport
  takes its family's pigment through an `activity--<kind>` class — the same
  colors The Week gives bike and run blocks on /fitness.
  """
  use Phoenix.Component
  use WebWeb, :verified_routes

  alias Web.Rides
  alias Web.Rides.{Thumbs, Units, Workout}

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
  attr :link, :boolean, default: false, doc: "link the fallback map to the ride's page"
  attr :downhill, :boolean, default: false
  attr :loading, :string, default: "lazy", values: ~w(lazy eager)

  @doc """
  The activity itself: Komoot's embed when Komoot will show the tour, else
  the cached route image with our figures beneath it.
  """
  def plate(assigns) do
    assigns = assign(assigns, :src, Rides.embed_url(assigns.ride))

    ~H"""
    <iframe
      :if={@src}
      id={"komoot-embed-#{@ride.id}"}
      src={@src}
      class="activity-embed"
      title={"#{title(@ride)} on Komoot"}
      loading={@loading}
      allow="fullscreen"
    >
    </iframe>
    <.link
      :if={!@src && @link}
      navigate={~p"/fitness/rides/#{@ride.id}"}
      class="activity-map-link"
    >
      <.route_map ride={@ride} />
    </.link>
    <.route_map :if={!@src && !@link} ride={@ride} />
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

  attr :ride, :map, required: true
  attr :trace, :boolean, default: false, doc: "draw the heart rate over the ride"

  @doc """
  What the watch measured, from the Apple Health workout paired with the
  ride: average and peak heart rate and active energy, and on a ride's own
  page the heart rate over the whole ride. Renders nothing without a workout.
  """
  def health(%{ride: %{health: %Workout{} = workout}} = assigns) do
    figures =
      for {label, value, format} <- [
            {"Avg heart rate", workout.avg_hr, &Units.bpm/1},
            {"Max heart rate", workout.max_hr, &Units.bpm/1},
            {"Active energy", workout.active_kcal, &Units.kcal/1}
          ],
          value != nil,
          do: {label, format.(value)}

    trace = if assigns.trace, do: Workout.trace(workout), else: []

    assigns =
      assign(assigns,
        figures: figures,
        trace: if(length(trace) >= 2, do: trace_geometry(trace))
      )

    ~H"""
    <section
      :if={@figures != [] || @trace}
      class="activity-health"
      aria-labelledby={"activity-health-#{@ride.id}"}
    >
      <header class="activity-health-head">
        <h2 id={"activity-health-#{@ride.id}"} class="activity-health-title">
          <span class="activity-health-mark" aria-hidden="true">♥</span> Heart &amp; energy
        </h2>
        <p class="activity-health-source">Apple Watch · Apple Health</p>
      </header>

      <dl :if={@figures != []} class="activity-figures">
        <div :for={{label, value} <- @figures} class="activity-figure">
          <dt class="activity-figure-label">{label}</dt>
          <dd class="activity-figure-value">{value}</dd>
        </div>
      </dl>

      <.heart_trace :if={@trace} id={"heart-trace-#{@ride.id}"} geometry={@trace} />
    </section>
    """
  end

  def health(assigns), do: ~H""

  # The chart's frame: 1000 units wide so a point's x is its share of the ride
  # in tenths of a percent, 200 tall. The bpm axis runs between clean tens a
  # little outside the ride's own range, gridded every 10, 20 or 40 bpm so
  # there are two to four rules.
  @trace_w 1000
  @trace_h 200

  defp trace_geometry(points) do
    {first_t, _} = hd(points)
    {last_t, _} = List.last(points)
    span = max(last_t - first_t, 1)
    {lo_bpm, hi_bpm} = points |> Enum.map(&elem(&1, 1)) |> Enum.min_max()
    lo = div(max(lo_bpm - 5, 0), 10) * 10
    hi = div(hi_bpm + 14, 10) * 10
    step = Enum.find([10, 20, 40], 40, &(div(hi - lo, &1) <= 4))

    x = fn t -> Float.round((t - first_t) / span * @trace_w, 1) end
    y = fn bpm -> Float.round(@trace_h - (bpm - lo) / (hi - lo) * @trace_h, 1) end

    line =
      points
      |> Enum.map(fn {t, bpm} -> "#{x.(t)},#{y.(bpm)}" end)
      |> Enum.join(" L")

    grid =
      for bpm <- lo..hi//10, rem(bpm, step) == 0 and bpm > lo and bpm < hi do
        %{bpm: bpm, pct: Float.round((hi - bpm) / (hi - lo) * 100, 2)}
      end

    %{
      line: "M" <> line,
      area: "M#{x.(first_t)},#{@trace_h} L" <> line <> " L#{x.(last_t)},#{@trace_h} Z",
      grid: grid,
      points:
        Enum.map(points, fn {t, bpm} ->
          [Float.round((t - first_t) / span, 4), Float.round((hi - bpm) / (hi - lo), 4), t, bpm]
        end),
      duration: Units.duration(last_t),
      start: elapsed(first_t),
      finish: elapsed(last_t),
      low: lo_bpm,
      high: hi_bpm,
      w: @trace_w,
      h: @trace_h
    }
  end

  # Time into the ride on a stopwatch, as the trace's axis and cursor read it:
  # "4:05", "1:02:30".
  defp elapsed(seconds) do
    seconds = max(seconds, 0)
    {h, m, s} = {div(seconds, 3600), div(rem(seconds, 3600), 60), rem(seconds, 60)}
    pad = &String.pad_leading(to_string(&1), 2, "0")
    if h > 0, do: "#{h}:#{pad.(m)}:#{pad.(s)}", else: "#{m}:#{pad.(s)}"
  end

  attr :id, :string, required: true
  attr :geometry, :map, required: true

  # Heart rate over the ride: one hot-metal line on a faint wash, bpm rules in
  # the panel's hairline, labels in text tokens (never the line's colour).
  # The SVG stretches to the panel, so the stroke opts out of scaling. A
  # pointer anywhere over the plot snaps a crosshair to the nearest sample
  # (`.HeartTrace`); the figures above give the same numbers without it.
  defp heart_trace(assigns) do
    ~H"""
    <figure
      id={@id}
      class="heart-trace"
      phx-hook=".HeartTrace"
      data-points={Jason.encode!(@geometry.points)}
    >
      <figcaption class="heart-trace-caption">
        Heart rate over {@geometry.duration} · {@geometry.low}–{@geometry.high} bpm
      </figcaption>
      <div class="heart-trace-plot">
        <div
          :for={rule <- @geometry.grid}
          class="heart-trace-rule"
          style={"top: #{rule.pct}%"}
        >
          <span class="heart-trace-tick">{rule.bpm}</span>
        </div>
        <svg
          viewBox={"0 0 #{@geometry.w} #{@geometry.h}"}
          preserveAspectRatio="none"
          role="img"
          aria-label={"Heart rate from #{@geometry.low} to #{@geometry.high} bpm over #{@geometry.duration}"}
        >
          <path class="heart-trace-area" d={@geometry.area} />
          <path class="heart-trace-line" d={@geometry.line} vector-effect="non-scaling-stroke" />
        </svg>
        <div class="heart-trace-cursor" aria-hidden="true" hidden>
          <span class="heart-trace-dot"></span>
          <span class="heart-trace-tip">
            <strong class="heart-trace-tip-value"></strong>
            <span class="heart-trace-tip-time"></span>
          </span>
        </div>
      </div>
      <div class="heart-trace-axis" aria-hidden="true">
        <span>{@geometry.start}</span>
        <span>{@geometry.finish}</span>
      </div>
    </figure>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".HeartTrace">
      // Snaps a crosshair to the sample nearest the pointer and reads it out.
      // Each point is [x 0..1, y 0..1 from the top, seconds in, bpm].
      export default {
        mounted() {
          this.points = JSON.parse(this.el.dataset.points)
          this.plot = this.el.querySelector(".heart-trace-plot")
          this.cursor = this.el.querySelector(".heart-trace-cursor")
          this.dot = this.el.querySelector(".heart-trace-dot")
          this.value = this.el.querySelector(".heart-trace-tip-value")
          this.time = this.el.querySelector(".heart-trace-tip-time")

          this.plot.addEventListener("pointermove", (e) => this.show(e))
          this.plot.addEventListener("pointerleave", () => (this.cursor.hidden = true))
        },

        show(e) {
          const box = this.plot.getBoundingClientRect()
          const x = (e.clientX - box.left) / box.width
          let nearest = this.points[0]

          for (const point of this.points) {
            if (Math.abs(point[0] - x) < Math.abs(nearest[0] - x)) nearest = point
          }

          const [px, py, seconds, bpm] = nearest
          this.cursor.hidden = false
          this.cursor.style.left = `${px * 100}%`
          this.dot.style.top = `${py * 100}%`
          this.cursor.classList.toggle("is-flipped", px > 0.75)
          this.value.textContent = `${bpm} bpm`
          this.time.textContent = this.clock(seconds)
        },

        clock(seconds) {
          const h = Math.floor(seconds / 3600)
          const m = Math.floor((seconds % 3600) / 60)
          const s = Math.floor(seconds % 60)
          const pad = (n) => String(n).padStart(2, "0")
          return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`
        }
      }
    </script>
    """
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

  @doc """
  One activity on a shelf, set the way Komoot sets a tour card: its route map
  at full colour, then name, day, Komoot's figures, and — when the watch's
  workout paired with it — heart rate and energy.
  """
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
        <span :if={card_health(@ride)} class="activity-card-health">
          <span class="activity-health-mark" aria-hidden="true">♥</span> {card_health(@ride)}
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

  # "142 bpm · 612 kcal", whichever of the two the workout carries.
  defp card_health(%{health: %Workout{} = workout}) do
    [
      workout.avg_hr && Units.bpm(workout.avg_hr),
      workout.active_kcal && Units.kcal(workout.active_kcal)
    ]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp card_health(_ride), do: nil
end
