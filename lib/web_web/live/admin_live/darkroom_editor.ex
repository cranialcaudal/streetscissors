defmodule WebWeb.AdminLive.DarkroomEditor do
  @moduledoc """
  One print on the bench (`/admin/darkroom/:roll/:frame`): LightCraft's
  sliders beside the picture they make, a crop with straightening, the print
  as developed one key away, and Save, which prints it for the site.

  The picture is LightCraft's own at every step (`Web.Darkroom.Session`): a
  slider moved asks for a new one, and the newest that comes back is shown.
  The sliders are drawn from the engine's own schema, cut to what a print
  from film is edited with (`Web.Darkroom.sections/2`); a black and white
  print is offered no colour.

  **Cropping shows the whole picture.** While the crop is open the picture is
  drawn uncropped and level, turned by the straightening in the browser, with
  the crop's box over it (`.CropBox`): the box is LightCraft's rectangle, in
  fractions of the picture, and LightCraft turns the picture about its middle
  as the browser does. Closing the crop asks for the cropped picture.

  `.Darkroom` adds the keys: `\\` shows the print as developed while held,
  ⌘S / Ctrl+S saves, and leaving with unsaved edits asks first. Whether there
  are any is the server's to say (`data-dirty`).
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Darkroom
  alias Web.Darkroom.Session
  alias Web.Negatives

  def mount(%{"roll" => roll, "frame" => frame}, session, socket) do
    with true <- !!session["admin_user"] || :not_admin,
         {:ok, dir} <- Negatives.roll_dir(roll),
         {frame, ""} <- Integer.parse(frame),
         true <- File.regular?(Darkroom.print_path(dir, frame)) do
      source = Darkroom.source_path(dir, frame)
      recipe = Darkroom.recipe(dir, frame)

      socket =
        assign(socket,
          page_title: "Roll #{roll}, frame #{frame} | Admin",
          roll: roll,
          dir: dir,
          frame: frame,
          frames: Enum.map(Negatives.list_frames(roll), & &1.frame),
          grey: Darkroom.grey?(source),
          size: Darkroom.dimensions(source) || {3, 2},
          saved: recipe,
          recipe: recipe,
          session: nil,
          token: nil,
          schema: [],
          sections: [],
          n: 0,
          shown: 0,
          preview: nil,
          before: nil,
          showing_before: false,
          cropping: false,
          working: nil,
          error: nil,
          stamp: System.system_time(:second)
        )

      {:ok, if(connected?(socket), do: open(socket, source), else: socket)}
    else
      :not_admin ->
        {:ok, push_navigate(socket, to: "/")}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such print.")
         |> push_navigate(to: ~p"/admin/darkroom")}
    end
  end

  # LightCraft is opened on the picture the edits apply to, which moves from
  # the print to `developed/` on the first save and back on a revert.
  defp open(socket, source) do
    if socket.assigns.session, do: Session.stop(socket.assigns.session)

    case Session.start(source) do
      {:ok, pid, info} ->
        socket
        |> assign(
          session: pid,
          token: info.token,
          schema: info.schema,
          sections: Darkroom.sections(info.schema, socket.assigns.grey),
          before: picture(info.token, info.before),
          error: nil
        )
        |> draw()

      {:error, reason} ->
        assign(socket, session: nil, error: reason)
    end
  end

  defp picture(token, file), do: ~p"/admin/darkroom/picture/#{token}/#{file}"

  # Asks for the picture the bench now describes. While cropping that is the
  # whole picture, level: the browser turns it and draws the box.
  defp draw(%{assigns: %{session: nil}} = socket), do: socket

  defp draw(socket) do
    %{recipe: recipe, cropping: cropping, n: n, session: session} = socket.assigns
    Session.preview(session, if(cropping, do: %{recipe | crop: nil}, else: recipe), n + 1)
    assign(socket, n: n + 1)
  end

  # ── Sliders ───────────────────────────────────────────────────────────

  def handle_event("adjust", params, socket) do
    shown = for section <- socket.assigns.sections, c <- section.controls, do: c["id"]
    kept = Map.drop(socket.assigns.recipe.controls, shown)

    controls =
      Map.merge(kept, Darkroom.clean_controls(Map.take(params, shown), socket.assigns.schema))

    {:noreply, socket |> put_recipe(controls: controls) |> draw()}
  end

  def handle_event("reset_section", %{"section" => key}, socket) do
    ids =
      for section <- socket.assigns.sections,
          section.key == key,
          c <- section.controls,
          do: c["id"]

    controls = Map.drop(socket.assigns.recipe.controls, ids)
    {:noreply, socket |> put_recipe(controls: controls) |> draw()}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, socket |> assign(recipe: Darkroom.empty(), cropping: false) |> draw()}
  end

  # ── Crop ──────────────────────────────────────────────────────────────

  def handle_event("crop", _params, %{assigns: %{cropping: false}} = socket) do
    crop = socket.assigns.recipe.crop || %{rect: [0.0, 0.0, 1.0, 1.0], angle: 0.0}
    {:noreply, socket |> assign(cropping: true) |> put_recipe(crop: crop) |> draw()}
  end

  def handle_event("crop", _params, socket) do
    crop = Darkroom.clean_crop(crop_params(socket.assigns.recipe.crop))
    {:noreply, socket |> assign(cropping: false) |> put_recipe(crop: crop) |> draw()}
  end

  def handle_event("crop_rect", %{"rect" => rect}, socket) do
    angle = (socket.assigns.recipe.crop || %{angle: 0.0}).angle
    {:noreply, put_crop(socket, %{"rect" => rect, "angle" => angle})}
  end

  def handle_event("straighten", %{"angle" => angle}, socket) do
    rect = (socket.assigns.recipe.crop || %{rect: [0.0, 0.0, 1.0, 1.0]}).rect
    {:noreply, put_crop(socket, %{"rect" => rect, "angle" => angle})}
  end

  def handle_event("crop_reset", _params, socket) do
    {:noreply, put_crop(socket, %{"rect" => [0.0, 0.0, 1.0, 1.0], "angle" => 0.0})}
  end

  # ── The bench ─────────────────────────────────────────────────────────

  def handle_event("before", %{"on" => on}, socket) do
    {:noreply, assign(socket, showing_before: on == true)}
  end

  def handle_event("before", _params, socket) do
    {:noreply, assign(socket, showing_before: !socket.assigns.showing_before)}
  end

  def handle_event("save", _params, %{assigns: %{working: nil}} = socket) do
    recipe = finished(socket.assigns.recipe)
    %{dir: dir, frame: frame} = socket.assigns

    {:noreply,
     socket
     |> assign(working: :save, cropping: false, recipe: recipe)
     |> start_async(:print, fn -> {:save, recipe, Darkroom.save(dir, frame, recipe)} end)}
  end

  def handle_event("revert", _params, %{assigns: %{working: nil}} = socket) do
    %{dir: dir, frame: frame} = socket.assigns

    {:noreply,
     socket
     |> assign(working: :revert)
     |> start_async(:print, fn -> {:revert, Darkroom.empty(), Darkroom.revert(dir, frame)} end)}
  end

  def handle_event(event, _params, socket) when event in ["save", "revert"],
    do: {:noreply, socket}

  def handle_async(:print, {:ok, {what, recipe, :ok}}, socket) do
    %{dir: dir, frame: frame} = socket.assigns

    message =
      if what == :save and not Darkroom.empty?(recipe),
        do: "Printed. The site shows the edited print.",
        else: "The print is back as it was developed."

    {:noreply,
     socket
     |> assign(working: nil, saved: recipe, recipe: recipe, stamp: System.system_time(:second))
     |> put_flash(:info, message)
     |> open(Darkroom.source_path(dir, frame))}
  end

  def handle_async(:print, {:ok, {_what, _recipe, {:error, reason}}}, socket) do
    {:noreply, socket |> assign(working: nil) |> put_flash(:error, "Not printed: #{reason}")}
  end

  def handle_async(:print, {:exit, reason}, socket) do
    {:noreply,
     socket |> assign(working: nil) |> put_flash(:error, "Not printed: #{inspect(reason)}")}
  end

  def handle_info({:darkroom_preview, n, file}, socket) do
    if n >= socket.assigns.shown do
      {:noreply,
       assign(socket, shown: n, preview: picture(socket.assigns.token, file), error: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:darkroom_error, _n, reason}, socket) do
    {:noreply, assign(socket, error: reason)}
  end

  defp put_recipe(socket, changes),
    do: assign(socket, recipe: Map.merge(socket.assigns.recipe, Map.new(changes)))

  defp put_crop(socket, params) do
    crop = Darkroom.clean_crop(params) || %{rect: [0.0, 0.0, 1.0, 1.0], angle: 0.0}
    socket |> put_recipe(crop: crop) |> draw()
  end

  defp crop_params(nil), do: nil
  defp crop_params(crop), do: %{"rect" => crop.rect, "angle" => crop.angle}

  # The recipe as it is kept: a crop that is the whole picture and level is no crop.
  defp finished(recipe), do: %{recipe | crop: Darkroom.clean_crop(crop_params(recipe.crop))}

  defp dirty?(assigns), do: finished(assigns.recipe) != finished(assigns.saved)

  defp value(recipe, control), do: Map.get(recipe.controls, control["id"], control["default"])

  defp shown(value, control) do
    :erlang.float_to_binary(value * 1.0, decimals: control["decimals"] || 0)
  end

  defp neighbour(frames, frame, step) do
    case Enum.find_index(frames, &(&1 == frame)) do
      nil -> nil
      index when index + step < 0 -> nil
      index -> Enum.at(frames, index + step)
    end
  end

  # A track's own colours, as the engine describes them, for its stylesheet rule.
  defp track(%{"track" => %{"kind" => "gradient", "from" => from, "to" => to}}),
    do: {"adm-dr-track--gradient", "--from: #{from}; --to: #{to}"}

  defp track(%{"track" => %{"kind" => kind, "band" => band}}),
    do: {"adm-dr-track--#{kind} adm-dr-band-#{band}", nil}

  defp track(%{"track" => %{"kind" => kind}}), do: {"adm-dr-track--#{kind}", nil}
  defp track(_), do: {"adm-dr-track--plain", nil}

  def render(assigns) do
    {w, h} = assigns.size
    crop = assigns.recipe.crop || %{rect: [0.0, 0.0, 1.0, 1.0], angle: 0.0}
    [x0, y0, x1, y1] = crop.rect

    assigns =
      assign(assigns,
        dirty: dirty?(assigns),
        edited: not Darkroom.empty?(assigns.saved),
        previous: neighbour(assigns.frames, assigns.frame, -1),
        next: neighbour(assigns.frames, assigns.frame, 1),
        angle: crop.angle,
        box:
          "--x0: #{x0}; --y0: #{y0}; --x1: #{x1}; --y1: #{y1}; --angle: #{crop.angle}deg; " <>
            "--ar: #{Float.round(w / h, 4)}; aspect-ratio: #{w} / #{h}",
        rect: Enum.join(crop.rect, ","),
        print: Negatives.sized_url("/negatives/frame/#{assigns.roll}/#{assigns.frame}", 960)
      )

    ~H"""
    <.page_head slug={"Darkroom / Prints / Roll #{@roll}"} title={"Frame #{@frame}"}>
      <:lede>
        <span :if={@edited}>Edited. The print as it was developed is kept beside it.</span>
        <span :if={!@edited}>As it was developed.</span>
        <.pill :if={@dirty} tone="held">unsaved</.pill>
      </:lede>
      <:actions>
        <.link navigate={~p"/admin/darkroom?roll=#{@roll}"} class="adm-btn adm-btn--quiet">
          Roll {@roll}
        </.link>
        <.link
          :if={@previous}
          navigate={~p"/admin/darkroom/#{@roll}/#{@previous}"}
          class="adm-btn adm-btn--quiet"
          aria-label="Previous print"
        >
          <.icon name="hero-chevron-left" class="size-4" />
        </.link>
        <.link
          :if={@next}
          navigate={~p"/admin/darkroom/#{@roll}/#{@next}"}
          class="adm-btn adm-btn--quiet"
          aria-label="Next print"
        >
          <.icon name="hero-chevron-right" class="size-4" />
        </.link>
        <.link
          href={~p"/negatives/roll/#{@roll}/frame/#{@frame}"}
          target="_blank"
          class="adm-btn adm-btn--quiet"
        >
          <.icon name="hero-arrow-top-right-on-square" class="size-4" /> View
        </.link>
        <button
          :if={@edited}
          type="button"
          phx-click="revert"
          class="adm-btn"
          disabled={@working != nil}
          data-confirm="Put the print back as it was developed? The edits are forgotten."
        >
          Revert
        </button>
        <button
          type="button"
          phx-click="save"
          class="adm-btn adm-btn--primary"
          disabled={@working != nil or !@dirty}
        >
          {if @working == :save, do: "Printing…", else: "Save"}
        </button>
      </:actions>
    </.page_head>

    <div id="darkroom" class="adm-dr-bench" phx-hook=".Darkroom" data-dirty={to_string(@dirty)}>
      <figure class="adm-dr-stage">
        <div
          :if={@cropping}
          id="crop-box"
          class="adm-dr-frame"
          style={@box}
          data-rect={@rect}
          phx-hook=".CropBox"
        >
          <img :if={@preview} src={@preview} alt="" class="adm-dr-frame-picture" draggable="false" />
          <div class="adm-dr-crop" data-role="rect">
            <span
              :for={handle <- ~w[nw n ne e se s sw w]}
              class={"adm-dr-handle adm-dr-handle--#{handle}"}
              data-handle={handle}
            >
            </span>
          </div>
        </div>
        <img
          :if={!@cropping}
          src={(@showing_before && @before) || @preview || @print}
          alt={"Roll #{@roll}, frame #{@frame}"}
          class="adm-dr-picture"
        />
        <figcaption class="adm-dr-caption">
          <span :if={@showing_before}>As developed</span>
          <span :if={(!@showing_before and @session) && @n > @shown}>Drawing…</span>
          <span :if={@error} class="adm-dr-error" role="alert">{@error}</span>
          <span :if={!@session and !@error}>Opening LightCraft…</span>
        </figcaption>
      </figure>

      <aside class="adm-dr-panel" aria-label="Adjustments">
        <div class="adm-dr-tools">
          <button
            type="button"
            phx-click="before"
            class={["adm-btn adm-btn--small", @showing_before && "is-on"]}
            aria-pressed={to_string(@showing_before)}
            title="Before and after (\\)"
          >
            <.icon name="hero-eye" class="size-4" /> Before
          </button>
          <button
            type="button"
            phx-click="crop"
            class={["adm-btn adm-btn--small", @cropping && "is-on"]}
            aria-pressed={to_string(@cropping)}
          >
            <.icon name="hero-scissors" class="size-4" /> {if @cropping, do: "Done", else: "Crop"}
          </button>
          <button type="button" phx-click="reset" class="adm-btn adm-btn--small adm-btn--quiet">
            Reset all
          </button>
        </div>

        <form :if={@cropping} id="straighten" phx-change="straighten" class="adm-dr-section">
          <div class="adm-dr-section-head">
            <h2 class="adm-dr-section-title">Crop</h2>
            <button type="button" phx-click="crop_reset" class="adm-dr-reset">Reset</button>
          </div>
          <label class="adm-dr-control">
            <span class="adm-dr-label">Straighten</span>
            <output class="adm-dr-value">
              {:erlang.float_to_binary(@angle * 1.0, decimals: 1)}°
            </output>
            <input
              type="range"
              name="angle"
              min="-45"
              max="45"
              step="0.1"
              value={@angle}
              phx-throttle="60"
              class="adm-dr-range adm-dr-track--centered"
            />
          </label>
          <p class="adm-dr-hint">Drag the box's corners and sides, or the box itself.</p>
        </form>

        <form :if={!@cropping} id="adjust" phx-change="adjust">
          <fieldset :for={section <- @sections} class="adm-dr-section" id={"section-#{section.key}"}>
            <div class="adm-dr-section-head">
              <legend class="adm-dr-section-title">{section.title}</legend>
              <button
                type="button"
                phx-click="reset_section"
                phx-value-section={section.key}
                class="adm-dr-reset"
              >
                Reset
              </button>
            </div>
            <label :for={control <- section.controls} class="adm-dr-control">
              <span class="adm-dr-label">{control["label"]}</span>
              <output class="adm-dr-value">{shown(value(@recipe, control), control)}</output>
              <input
                type="range"
                name={control["id"]}
                min={control["min"]}
                max={control["max"]}
                step={control["step"]}
                value={value(@recipe, control)}
                phx-throttle="60"
                class={["adm-dr-range", elem(track(control), 0)]}
                style={elem(track(control), 1)}
              />
            </label>
          </fieldset>
        </form>
      </aside>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Darkroom">
      // The bench's keys. \ shows the print as developed while it is held,
      // Cmd/Ctrl+S saves, and leaving with unsaved edits asks first.
      export default {
        mounted() {
          this.held = false
          this.onDown = (event) => {
            const typing = event.target.closest("input[type=text], textarea")
            if (event.key === "\\" && !typing && !this.held) {
              this.held = true
              this.pushEvent("before", {on: true})
            } else if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
              event.preventDefault()
              this.pushEvent("save", {})
            }
          }
          this.onUp = (event) => {
            if (event.key === "\\" && this.held) {
              this.held = false
              this.pushEvent("before", {on: false})
            }
          }
          this.onLeave = (event) => {
            if (this.el.dataset.dirty === "true") {
              event.preventDefault()
              event.returnValue = ""
            }
          }
          window.addEventListener("keydown", this.onDown)
          window.addEventListener("keyup", this.onUp)
          window.addEventListener("beforeunload", this.onLeave)
        },
        destroyed() {
          window.removeEventListener("keydown", this.onDown)
          window.removeEventListener("keyup", this.onUp)
          window.removeEventListener("beforeunload", this.onLeave)
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CropBox">
      // The crop's box over the whole picture. The box is LightCraft's
      // rectangle in fractions of the picture ([x0, y0, x1, y1]); it is drawn
      // from the --x0..--y1 the server writes, and while it is dragged this
      // writes the same properties, so the server's next render agrees with
      // what the hand left. The new box goes to the server when it is let go.
      const MIN = 0.02
      const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v))

      export default {
        mounted() {
          this.onDown = (event) => {
            const handle = event.target.dataset.handle || (event.target.closest("[data-role=rect]") && "move")
            if (!handle) return
            event.preventDefault()
            const box = this.el.getBoundingClientRect()
            this.drag = {handle, box, x: event.clientX, y: event.clientY, start: this.rect()}
            this.el.setPointerCapture(event.pointerId)
          }
          this.onMove = (event) => {
            if (!this.drag) return
            const {handle, box, x, y, start} = this.drag
            const dx = (event.clientX - x) / box.width
            const dy = (event.clientY - y) / box.height
            let [x0, y0, x1, y1] = start
            if (handle === "move") {
              const w = x1 - x0, h = y1 - y0
              x0 = clamp(x0 + dx, 0, 1 - w); y0 = clamp(y0 + dy, 0, 1 - h)
              x1 = x0 + w; y1 = y0 + h
            } else {
              if (handle.includes("w")) x0 = clamp(x0 + dx, 0, x1 - MIN)
              if (handle.includes("e")) x1 = clamp(x1 + dx, x0 + MIN, 1)
              if (handle.includes("n")) y0 = clamp(y0 + dy, 0, y1 - MIN)
              if (handle.includes("s")) y1 = clamp(y1 + dy, y0 + MIN, 1)
            }
            this.drag.current = [x0, y0, x1, y1]
            this.write(this.drag.current)
          }
          this.onUp = (event) => {
            if (!this.drag) return
            this.drag = null
            this.el.releasePointerCapture(event.pointerId)
            this.pushEvent("crop_rect", {rect: this.rect()})
          }
          this.el.addEventListener("pointerdown", this.onDown)
          this.el.addEventListener("pointermove", this.onMove)
          this.el.addEventListener("pointerup", this.onUp)
          this.el.addEventListener("pointercancel", this.onUp)
        },
        // A picture that arrives mid-drag redraws the box from the server's
        // numbers, which are still the ones from before the drag.
        updated() {
          if (this.drag && this.drag.current) this.write(this.drag.current)
        },
        rect() {
          const style = this.el.style
          return ["--x0", "--y0", "--x1", "--y1"].map((name) => parseFloat(style.getPropertyValue(name)))
        },
        write(rect) {
          ["--x0", "--y0", "--x1", "--y1"].forEach((name, i) => this.el.style.setProperty(name, rect[i].toFixed(4)))
        }
      }
    </script>
    """
  end
end
