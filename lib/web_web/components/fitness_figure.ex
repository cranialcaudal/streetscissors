defmodule WebWeb.FitnessFigure do
  @moduledoc """
  The figure on an exercise's wiki page.

  ## The film

  When the exercise has a film of its figure (`Web.Fitness.Clip`), that is
  what the page shows: the body in three dimensions with the muscles the
  exercise works lit, filmed once on the bench and played here as a short
  silent `<video>` that loops. The phone decodes a hundred kilobytes; it
  builds nothing. A hold, which is one pose, is its first frame as a picture.
  Under the film the lit muscles are named, since the colour alone says
  where and not what.

  ## The drawing

  An exercise whose figure has not been filmed, or has changed since it was,
  gets the flat drawing `Web.Fitness.Figure.build/1` baked, which is always
  current. It is a body rather than a wire: every part is a rounded stroke
  as thick as the part is, laid down back to front in layers. The far limbs
  are dim, the trunk and head and the near limbs are the section's white, and
  the near limbs carry a dark edge so an arm reads against the body it
  crosses. Equipment that stands still is drawn dim behind it, a band or
  cable is a line to the hand that pulls it, and what is held is in hot
  metal. What is held can be **behind** the body for part of the loop: it is
  drawn twice, once under everything and once over the near leg, and each
  copy is shown only for the frames it belongs to.

  The drawing's motion is all in the markup: each part is a `<path>` whose
  `d` is animated through the baked frames by SMIL.

  ## The buttons

  Either way the picture moves with no script, and the `.Figure` hook only
  works the clock: pause, and a button per pose that stops the loop where
  that pose begins. A film plays by `autoplay`, so it does not wait for the
  page's socket, and its one `<source>` is offered only to a reader who has
  not asked for reduced motion (`media`): anyone who has is left with the
  poster, which is the first pose, until they press Play or a pose, when the
  hook hands the video its file. The Play button reads off the video's own
  `play` and `pause` events, so it is right when a browser refuses to start.

  The figure owns its element (`phx-update="ignore"`), so a patch to the page
  around it never restarts the loop. `still/1` draws one frame of the drawing
  with nothing moving. Styled by `fitness_wiki.css`, tokens only.
  """
  use Phoenix.Component

  @edge 1.6

  attr :id, :string, required: true
  attr :figure, :map, default: nil, doc: "the baked drawing, when there is no film"
  attr :clip, :map, default: nil, doc: "the film, from `Web.Fitness.Clip.find/2`"
  attr :muscles, :list, default: [], doc: "the names of the muscles lit"
  attr :label, :string, required: true, doc: "the exercise's name, for the picture's description"

  def figure(assigns) do
    stops = if assigns.clip, do: assigns.clip.stops, else: assigns.figure.stops

    assigns =
      assigns
      |> assign(:stops, stops)
      |> assign(
        :says,
        "#{assigns.label}, shown as a figure moving through: #{Enum.map_join(stops, ", ", & &1.name)}."
      )

    ~H"""
    <figure id={@id} class={["fig", @clip && "fig--film"]} phx-hook=".Figure" phx-update="ignore">
      <video
        :if={@clip && length(@stops) > 1}
        class="fig-film"
        width={@clip.width}
        height={@clip.height}
        poster={@clip.poster}
        aria-label={@says}
        data-film={@clip.video}
        autoplay
        muted
        loop
        playsinline
        preload="auto"
        disablepictureinpicture
      >
        <source src={@clip.video} type="video/mp4" media="(prefers-reduced-motion: no-preference)" />
      </video>
      <img
        :if={@clip && length(@stops) == 1}
        class="fig-film"
        src={@clip.poster}
        width={@clip.width}
        height={@clip.height}
        alt={"#{@label}, shown as a figure holding the position."}
      />
      <.stage :if={!@clip} id={@id} figure={@figure} frame={nil} label={@says} />

      <figcaption :if={length(@stops) > 1} class="fig-controls">
        <button
          type="button"
          class="fig-button fig-button--toggle"
          data-fig-toggle
          aria-pressed="false"
        >
          Pause
        </button>
        <button :for={stop <- @stops} type="button" class="fig-button" data-fig-stop={stop.at}>
          {stop.name}
        </button>
      </figcaption>

      <p :if={@muscles != []} class="fig-muscles">
        <span class="fig-muscles-label">Working</span>
        <span :for={muscle <- @muscles} class="fig-muscle">{muscle}</span>
      </p>
    </figure>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Figure">
      // The picture moves by itself (a video playing, or an SVG animating its
      // own paths); this only stops and starts its clock. A pose's button
      // sets the clock to the moment that pose begins and holds it there.
      export default {
        mounted() {
          const toggle = this.el.querySelector("[data-fig-toggle]")
          if (!toggle) return

          const video = this.el.querySelector("video")
          const svg = this.el.querySelector("svg")
          const stops = [...this.el.querySelectorAll("[data-fig-stop]")]
          let at = null

          const show = (paused) => {
            toggle.textContent = paused ? "Play" : "Pause"
            toggle.setAttribute("aria-pressed", String(paused))
            stops.forEach((stop) => stop.classList.toggle("is-held", paused && stop === at))
            this.paused = paused
          }

          if (video) {
            // A reader who asked for stillness was offered no source: the
            // file is handed over the first time they ask for the film.
            const ready = (then) => {
              if (video.readyState >= 1) return then()
              video.addEventListener("loadedmetadata", then, { once: true })
              if (!video.currentSrc) { video.src = video.dataset.film; video.load() }
            }

            // The button says what the video is doing, whoever stopped it.
            video.addEventListener("play", () => { at = null; show(false) })
            video.addEventListener("pause", () => show(true))

            toggle.addEventListener("click", () => {
              if (video.paused) ready(() => video.play().catch(() => show(true)))
              else video.pause()
            })

            stops.forEach((stop) => {
              stop.addEventListener("click", () => {
                at = stop
                ready(() => {
                  video.pause()
                  // a hair past the pose's first frame, never the one before it
                  video.currentTime = Number(stop.dataset.figStop) + 0.02
                  show(true)
                })
              })
            })

            show(video.paused)
          } else {
            const set = (paused) => {
              if (paused) svg.pauseAnimations()
              else svg.unpauseAnimations()
              show(paused)
            }

            toggle.addEventListener("click", () => { at = null; set(!this.paused) })

            stops.forEach((stop) => {
              stop.addEventListener("click", () => {
                at = stop
                svg.setCurrentTime(Number(stop.dataset.figStop))
                set(true)
              })
            })

            if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
              at = stops[0]
              svg.setCurrentTime(0)
              set(true)
            } else {
              set(false)
            }
          }
        }
      }
    </script>
    """
  end

  @doc "One frame of a figure, with nothing moving: a pose on its own."
  attr :id, :string, required: true
  attr :figure, :map, required: true
  attr :frame, :integer, required: true
  attr :label, :string, required: true

  def still(assigns) do
    ~H"""
    <.stage id={@id} figure={@figure} frame={@frame} label={@label} />
    """
  end

  # `frame` is nil for the moving figure, or the index of the one to draw.
  attr :id, :string, required: true
  attr :figure, :map, required: true
  attr :frame, :any, required: true
  attr :label, :string, required: true

  defp stage(assigns) do
    {held, rest} = Enum.split_with(assigns.figure.props, &Map.has_key?(&1, :behind))
    {lines, stood} = Enum.split_with(rest, &(&1.kind == :line))

    assigns =
      assigns
      |> assign(:box, assigns.figure.box)
      |> assign(:dur, "#{assigns.figure.seconds}s")
      |> assign(:held, held)
      |> assign(:stood, stood)
      |> assign(:lines, lines)
      |> assign(:clip, assigns.figure.floor && "#{assigns.id}-ground")

    ~H"""
    <svg
      class={"fig-stage fig-stage--#{@figure.view}"}
      viewBox={"#{@box.x} #{@box.y} #{@box.w} #{@box.h}"}
      role="img"
      aria-label={@label}
    >
      <clipPath :if={@clip} id={@clip}>
        <rect x="-40" y="-80" width="240" height={80 + @figure.ground} />
      </clipPath>

      <.gear :for={prop <- @stood} prop={prop} />
      <line
        :if={@figure.floor}
        class="fig-floor"
        x1="0"
        y1={@figure.ground}
        x2="160"
        y2={@figure.ground}
      />

      <g class="fig-figure" clip-path={@clip && "url(##{@clip})"}>
        <.line
          :for={line <- @lines}
          class={"fig-rope fig-rope--#{line.style}"}
          width={if(line.style == :pole, do: 2.6, else: 1.3)}
          values={line.d}
          frame={if(line.moves, do: @frame, else: 0)}
          dur={@dur}
        />
        <.held :for={prop <- @held} prop={prop} side={:behind} frame={@frame} dur={@dur} />
        <.layer :for={layer <- @figure.back} layer={layer} frame={@frame} dur={@dur} />
        <.held :for={prop <- @held} prop={prop} side={:front} frame={@frame} dur={@dur} />
        <.layer :for={layer <- @figure.top} layer={layer} frame={@frame} dur={@dur} />
      </g>
    </svg>
    """
  end

  # Equipment that stands still: what the figure is on, under or beside.
  attr :prop, :map, required: true

  defp gear(%{prop: %{kind: :disc}} = assigns) do
    ~H"""
    <circle class="fig-prop fig-prop--disc" cx={@prop.cx} cy={@prop.cy} r={@prop.r} />
    """
  end

  defp gear(%{prop: %{kind: :dome}} = assigns) do
    ~H"""
    <path class="fig-prop fig-prop--dome" d={@prop.d} />
    """
  end

  defp gear(assigns) do
    ~H"""
    <rect
      class={"fig-prop fig-prop--#{@prop.kind}"}
      x={@prop.x}
      y={@prop.y}
      width={@prop.w}
      height={@prop.h}
    />
    """
  end

  # A group of parts in one tone. With an edge, every part is first laid down
  # a little wider in the ground's colour, all of them before any is filled,
  # so the limb has one outline and no seam at its joint.
  attr :layer, :map, required: true
  attr :frame, :any, required: true
  attr :dur, :string, required: true

  defp layer(assigns) do
    assigns = assign(assigns, :edges, if(assigns.layer.edge, do: assigns.layer.parts, else: []))

    ~H"""
    <g class={"fig-layer fig-tone-#{@layer.tone}"} data-part={@layer.name}>
      <.line
        :for={part <- @edges}
        class="fig-edge"
        width={part.w + edge()}
        values={part.d}
        frame={@frame}
        dur={@dur}
      />
      <.dot :for={dot <- @layer.under} dot={dot} frame={@frame} dur={@dur} />
      <.line
        :for={part <- @layer.parts}
        class={["fig-fill", part[:targeted] && "fig-muscle-active"]}
        width={part.w}
        values={part.d}
        frame={@frame}
        dur={@dur}
      />
      <.line
        :for={shape <- @layer.shapes}
        class={["fig-solid", shape[:targeted] && "fig-muscle-active"]}
        width={shape.w}
        values={shape.d}
        frame={@frame}
        dur={@dur}
      />
      <.dot :for={dot <- @layer.over} dot={dot} frame={@frame} dur={@dur} />
    </g>
    """
  end

  defp edge, do: @edge

  attr :class, :any, required: true
  attr :width, :float, required: true
  attr :values, :list, required: true
  attr :frame, :any, required: true
  attr :dur, :string, required: true

  defp line(assigns) do
    ~H"""
    <path class={@class} stroke-width={Float.round(@width * 1.0, 1)} d={at(@values, @frame)}>
      <animate
        :if={is_nil(@frame)}
        attributeName="d"
        dur={@dur}
        repeatCount="indefinite"
        values={Enum.join(@values, ";")}
      />
    </path>
    """
  end

  attr :dot, :map, required: true
  attr :frame, :any, required: true
  attr :dur, :string, required: true
  attr :class, :any, default: "fig-dot"

  defp dot(assigns) do
    ~H"""
    <g class="fig-head-group">
      <circle
        class={@class}
        r={@dot.r}
        cx={at(@dot.cx, @frame)}
        cy={at(@dot.cy, @frame)}
      >
        <animate
          :if={is_nil(@frame)}
          attributeName="cx"
          dur={@dur}
          repeatCount="indefinite"
          values={Enum.join(@dot.cx, ";")}
        />
        <animate
          :if={is_nil(@frame)}
          attributeName="cy"
          dur={@dur}
          repeatCount="indefinite"
          values={Enum.join(@dot.cy, ";")}
        />
      </circle>
      <path
        :if={Map.has_key?(@dot, :visor)}
        class="fig-visor"
        d={at(@dot.visor, @frame)}
      >
        <animate
          :if={is_nil(@frame)}
          attributeName="d"
          dur={@dur}
          repeatCount="indefinite"
          values={Enum.join(@dot.visor, ";")}
        />
      </path>
    </g>
    """
  end

  # What is held, on one side of the body. A copy is left out altogether when
  # the weight is never on its side; otherwise it is hidden, frame by frame,
  # whenever the weight is on the other.
  attr :prop, :map, required: true
  attr :side, :atom, required: true
  attr :frame, :any, required: true
  attr :dur, :string, required: true

  defp held(assigns) do
    here = Enum.map(assigns.prop.behind, &(&1 == (assigns.side == :behind)))

    assigns =
      assigns
      |> assign(:ever, Enum.any?(here))
      |> assign(:always, Enum.all?(here))
      |> assign(:now, if(is_nil(assigns.frame), do: hd(here), else: Enum.at(here, assigns.frame)))
      # One value per step of the loop: the closing frame repeats the first.
      |> assign(
        :shown,
        here |> Enum.drop(-1) |> Enum.map_join(";", &if(&1, do: "visible", else: "hidden"))
      )

    ~H"""
    <g
      :if={@ever and (is_nil(@frame) or @now)}
      class={"fig-held fig-held--#{@prop.kind} fig-held--#{@side}"}
      visibility={if(@now, do: "visible", else: "hidden")}
    >
      <animate
        :if={is_nil(@frame) and not @always}
        attributeName="visibility"
        dur={@dur}
        repeatCount="indefinite"
        calcMode="discrete"
        values={@shown}
      />
      <.line class="fig-handle" width={2.4} values={@prop.handle} frame={@frame} dur={@dur} />
      <.dot class="fig-weight" dot={@prop} frame={@frame} dur={@dur} />
    </g>
    """
  end

  defp at(values, nil), do: hd(values)
  defp at(values, frame), do: Enum.at(values, frame)
end
