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
  alias Web.Darkroom.{Archive, Prior, Repair, Session, Taste}
  alias Web.Negatives
  alias Web.Negatives.RollMeta

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
          dusting: false,
          repairing: false,
          masked: Repair.mask?(dir, frame),
          repaired: Repair.repaired?(dir, frame),
          repair_unsaved: repair_unsaved?(dir, frame),
          on_print: Darkroom.edited?(dir, frame),
          mask_stamp: System.system_time(:millisecond),
          working: nil,
          error: nil,
          stamp: System.system_time(:second),
          prior: nil,
          seconds: RollMeta.exposure(dir, frame)
        )

      {:ok, if(connected?(socket), do: socket |> open(source) |> suggest(), else: socket)}
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

  # The film's suggestion (Web.Darkroom.Prior) and his taste's
  # (Web.Darkroom.Taste), worked out off the page: the first time, the
  # archive's prints are measured, which takes a minute or so.
  defp suggest(socket) do
    %{dir: dir, frame: frame, grey: grey, recipe: recipe, schema: schema} = socket.assigns
    source = Darkroom.source_path(dir, frame)
    temp = Map.get(recipe.controls, "wb.temp", 6500.0)
    color = if grey, do: "bw", else: "color"
    defaults = Map.new(schema, &{&1["id"], &1["default"]})
    start_async(socket, :prior, fn -> work_out(dir, frame, source, color, temp, defaults) end)
  end

  defp work_out(dir, frame, source, color, temp, defaults) do
    prints = Archive.prints()
    groups = Archive.groups(prints)
    model = Taste.fit(prints, groups, defaults)
    {group, _stock} = Archive.group_of(dir, color)
    taste = Taste.taste_for(model, group)
    opts = [temp: temp, groups: groups, taste: taste]

    with {:ok, prior} <- Prior.suggest(dir, frame, source, color, opts) do
      predicted = Taste.predict(model, prior.stats, group, Taste.condition(dir))
      {:ok, Map.merge(prior, %{taught: model.n, chosen: model.choices, predicted: predicted})}
    end
  end

  # Asks for the picture the bench now describes. While cropping that is the
  # whole picture, level: the browser turns it and draws the box.
  defp draw(%{assigns: %{session: nil}} = socket), do: socket

  defp draw(socket) do
    %{recipe: recipe, cropping: cropping, dusting: dusting, n: n, session: session} =
      socket.assigns

    whole? = cropping or dusting
    Session.preview(session, if(whole?, do: %{recipe | crop: nil}, else: recipe), n + 1)
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

  # ── The film ──────────────────────────────────────────────────────────

  def handle_event("exposure", %{"seconds" => text}, socket) do
    seconds =
      case Float.parse(String.trim(text)) do
        {s, _} when s > 0 -> if s == Float.round(s), do: round(s), else: s
        _ -> nil
      end

    RollMeta.put_exposure(socket.assigns.dir, socket.assigns.frame, seconds)
    {:noreply, socket |> assign(seconds: seconds) |> suggest()}
  end

  # Temp is set where the suggestion puts it and Tint moved by it; the
  # sliders his taste predicts are set to its values.
  def handle_event("apply_prior", _params, %{assigns: %{prior: %{} = prior}} = socket) do
    controls = socket.assigns.recipe.controls

    colour =
      case prior.sliders do
        %{"wb.temp" => temp, "wb.tint" => tint} ->
          %{
            "wb.temp" => Float.round(temp / 50) * 50,
            "wb.tint" => Float.round(Map.get(controls, "wb.tint", 0.0) + tint)
          }

        _ ->
          %{}
      end

    values = controls |> Map.merge(prior.predicted) |> Map.merge(colour)
    changed = Darkroom.clean_controls(values, socket.assigns.schema)
    {:noreply, socket |> put_recipe(controls: changed) |> draw() |> suggest()}
  end

  def handle_event("apply_prior", _params, socket), do: {:noreply, socket}

  # ── Crop ──────────────────────────────────────────────────────────────

  def handle_event("crop", _params, %{assigns: %{cropping: false}} = socket) do
    crop = socket.assigns.recipe.crop || %{rect: [0.0, 0.0, 1.0, 1.0], angle: 0.0}

    {:noreply,
     socket
     |> assign(cropping: true, dusting: false, repairing: false)
     |> put_recipe(crop: crop)
     |> draw()}
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

  # ── Dust ──────────────────────────────────────────────────────────────

  def handle_event("dust", _params, socket) do
    socket =
      if socket.assigns.cropping,
        do:
          socket
          |> assign(cropping: false)
          |> put_recipe(crop: Darkroom.clean_crop(crop_params(socket.assigns.recipe.crop))),
        else: socket

    {:noreply, socket |> assign(dusting: !socket.assigns.dusting, repairing: false) |> draw()}
  end

  def handle_event("find_dust", params, %{assigns: %{session: pid}} = socket) when is_pid(pid) do
    keen = params["sensitivity"] |> number_or(60) |> round() |> max(0) |> min(100)

    case Session.find_dust(pid, keen) do
      {:ok, found} ->
        spots = merge_spots(socket.assigns.recipe.spots, found)
        added = length(spots) - length(socket.assigns.recipe.spots)

        {:noreply,
         socket
         |> put_recipe(spots: spots)
         |> draw()
         |> put_flash(:info, "Found #{length(found)} specks; #{added} new.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "No dust found: #{reason}")}
    end
  end

  def handle_event("find_dust", _params, socket), do: {:noreply, socket}

  def handle_event("add_spot", %{"x" => x, "y" => y}, socket) do
    new = Darkroom.clean_spots([%{"x" => x, "y" => y, "size" => 0.005}])

    {:noreply,
     socket |> put_recipe(spots: merge_spots(socket.assigns.recipe.spots, new)) |> draw()}
  end

  def handle_event("remove_spot", %{"index" => index}, socket) do
    spots = List.delete_at(socket.assigns.recipe.spots, index |> number_or(-1) |> round())
    {:noreply, socket |> put_recipe(spots: spots) |> draw()}
  end

  def handle_event("clear_spots", _params, socket) do
    {:noreply, socket |> put_recipe(spots: []) |> draw()}
  end

  # ── Repair ────────────────────────────────────────────────────────────

  def handle_event("repair", _params, socket) do
    socket =
      if socket.assigns.cropping,
        do:
          socket
          |> assign(cropping: false)
          |> put_recipe(crop: Darkroom.clean_crop(crop_params(socket.assigns.recipe.crop))),
        else: socket

    {:noreply, socket |> assign(repairing: !socket.assigns.repairing, dusting: false) |> draw()}
  end

  def handle_event("mask", %{"png" => "data:image/png;base64," <> data}, socket) do
    %{dir: dir, frame: frame} = socket.assigns

    with {:ok, png} <- Base.decode64(data),
         :ok <- Repair.put_mask(dir, frame, png) do
      {:noreply, assign(socket, masked: Repair.mask?(dir, frame))}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "The mask was not kept: #{reason}")}

      :error ->
        {:noreply, put_flash(socket, :error, "The mask was not kept.")}
    end
  end

  def handle_event("find_lines", _params, %{assigns: %{working: nil}} = socket) do
    %{dir: dir, frame: frame} = socket.assigns

    {:noreply,
     socket
     |> assign(working: :lines)
     |> start_async(:repair, fn -> {:lines, Repair.find_lines(dir, frame)} end)}
  end

  def handle_event("clear_mask", _params, socket) do
    Repair.clear_mask(socket.assigns.dir, socket.assigns.frame)
    {:noreply, socket |> assign(masked: false) |> reload_mask()}
  end

  def handle_event("lama", _params, %{assigns: %{working: nil}} = socket) do
    %{dir: dir, frame: frame} = socket.assigns

    {:noreply,
     socket
     |> assign(working: :lama)
     |> start_async(:repair, fn -> {:lama, Repair.lama(dir, frame)} end)}
  end

  def handle_event("undo_repair", _params, socket) do
    %{dir: dir, frame: frame} = socket.assigns
    Repair.undo(dir, frame)

    {:noreply,
     socket
     |> assign(repaired: false, repair_unsaved: socket.assigns.on_print)
     |> open(Darkroom.source_path(dir, frame))}
  end

  def handle_event(event, _params, socket) when event in ["find_lines", "lama"],
    do: {:noreply, socket}

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

  def handle_async(:prior, {:ok, {:ok, prior}}, socket),
    do: {:noreply, assign(socket, prior: prior)}

  def handle_async(:prior, _result, socket), do: {:noreply, assign(socket, prior: :error)}

  def handle_async(:repair, {:ok, {:lines, {:ok, found}}}, socket) do
    masked = Repair.mask?(socket.assigns.dir, socket.assigns.frame)

    said =
      case found do
        0 -> "No scanner lines found."
        1 -> "Found a scanner line; it is marked."
        n -> "Found #{n} scanner lines; they are marked."
      end

    {:noreply,
     socket |> assign(working: nil, masked: masked) |> reload_mask() |> put_flash(:info, said)}
  end

  def handle_async(:repair, {:ok, {:lama, {:ok, %{lines: lines, places: places}}}}, socket) do
    %{dir: dir, frame: frame} = socket.assigns

    done =
      [
        lines > 0 && count(lines, "scanner line corrected", "scanner lines corrected"),
        places > 0 && count(places, "place painted", "places painted")
      ]
      |> Enum.filter(& &1)
      |> Enum.join(", ")

    {:noreply,
     socket
     |> assign(working: nil, repaired: true, repair_unsaved: true)
     |> open(Darkroom.source_path(dir, frame))
     |> put_flash(:info, "Repaired: #{done}. Save keeps it on the print.")}
  end

  def handle_async(:repair, {:ok, {_what, {:error, reason}}}, socket) do
    {:noreply, socket |> assign(working: nil) |> put_flash(:error, "Not repaired: #{reason}")}
  end

  def handle_async(:repair, {:exit, reason}, socket) do
    {:noreply,
     socket |> assign(working: nil) |> put_flash(:error, "Not repaired: #{inspect(reason)}")}
  end

  def handle_async(:print, {:ok, {what, recipe, :ok}}, socket) do
    %{dir: dir, frame: frame} = socket.assigns

    on_print = Darkroom.edited?(dir, frame)

    message =
      if what == :save and on_print,
        do: "Printed. The site shows the edited print.",
        else: "The print is back as it was developed."

    {:noreply,
     socket
     |> assign(
       working: nil,
       saved: recipe,
       recipe: recipe,
       on_print: on_print,
       repaired: Repair.repaired?(dir, frame),
       masked: Repair.mask?(dir, frame),
       repair_unsaved: false,
       stamp: System.system_time(:second)
     )
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

  # A speck found twice is healed once: a new spot within its own size of one
  # already there is the same speck.
  defp merge_spots(spots, found) do
    found
    |> Enum.reduce(spots, fn new, acc ->
      near? = fn s ->
        reach = max(s.size, new.size)
        abs(s.x - new.x) < reach and abs(s.y - new.y) < reach
      end

      if Enum.any?(acc, near?), do: acc, else: acc ++ [new]
    end)
    |> Enum.take(300)
  end

  defp number_or(value, _default) when is_number(value), do: value

  defp number_or(value, default) when is_binary(value) do
    case Float.parse(value) do
      {f, _} -> f
      :error -> default
    end
  end

  defp number_or(_value, default), do: default

  defp count(1, one, _many), do: "1 #{one}"
  defp count(n, _one, many), do: "#{n} #{many}"

  defp reload_mask(socket) do
    stamp = System.system_time(:millisecond)
    url = ~p"/admin/darkroom/mask/#{socket.assigns.roll}/#{socket.assigns.frame}?v=#{stamp}"
    socket |> assign(mask_stamp: stamp) |> push_event("mask-reload", %{url: url})
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

  # A repair is not in the recipe, so one made or undone and not yet printed
  # counts on its own.
  defp dirty?(assigns),
    do: assigns.repair_unsaved or finished(assigns.recipe) != finished(assigns.saved)

  # Opening a frame: a repair newer than the print has not been printed.
  defp repair_unsaved?(dir, frame) do
    with {:ok, %{mtime: repaired}} <- File.stat(Darkroom.repaired_path(dir, frame), time: :posix),
         {:ok, %{mtime: print}} <- File.stat(Darkroom.print_path(dir, frame), time: :posix) do
      repaired > print
    else
      _ -> false
    end
  end

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

  defp predicted_words(predicted, schema) do
    labels = Map.new(schema, &{&1["id"], {&1["label"], &1["decimals"] || 0}})

    predicted
    |> Enum.sort()
    |> Enum.map_join(", ", fn {id, value} ->
      {label, decimals} = labels[id] || {id, 1}
      "#{label} #{:erlang.float_to_binary(value * 1.0, decimals: decimals)}"
    end)
  end

  # The dust box has the picture's shape; --long is its long edge over its
  # width, so a spot's size (a fraction of the long edge) can be drawn.
  defp dust_box({w, h}) do
    "--ar: #{Float.round(w / h, 4)}; --long: #{max(w, h) / w}; aspect-ratio: #{w} / #{h}"
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
        edited: assigns.on_print,
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
        <div
          :if={@dusting}
          id="dust-box"
          class="adm-dr-frame adm-dr-frame--dust"
          style={dust_box(@size)}
          phx-hook=".DustBox"
        >
          <img
            :if={@preview}
            src={@preview}
            alt=""
            class="adm-dr-frame-picture adm-dr-frame-picture--flat"
            draggable="false"
          />
          <button
            :for={{spot, i} <- Enum.with_index(@recipe.spots)}
            type="button"
            class="adm-dr-spot"
            data-index={i}
            style={"--x: #{spot.x}; --y: #{spot.y}; --s: #{spot.size}"}
            aria-label={"Speck #{i + 1}: take it off"}
          >
          </button>
        </div>
        <div
          :if={@repairing}
          id="repair-box"
          class="adm-dr-frame adm-dr-frame--repair"
          style={dust_box(@size)}
          phx-hook=".MaskPainter"
          phx-update="ignore"
          data-w={elem(@size, 0)}
          data-h={elem(@size, 1)}
          data-mask={~p"/admin/darkroom/mask/#{@roll}/#{@frame}?v=#{@mask_stamp}"}
        >
          <img
            src={~p"/admin/darkroom/developed/#{@roll}/#{@frame}"}
            alt=""
            class="adm-dr-frame-picture adm-dr-frame-picture--flat"
            draggable="false"
          />
          <canvas class="adm-dr-mask"></canvas>
        </div>
        <img
          :if={!@cropping and !@dusting and !@repairing}
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
          <button
            type="button"
            phx-click="dust"
            class={["adm-btn adm-btn--small", @dusting && "is-on"]}
            aria-pressed={to_string(@dusting)}
          >
            {if @dusting, do: "Done", else: "Dust"}
          </button>
          <button
            type="button"
            phx-click="repair"
            class={["adm-btn adm-btn--small", @repairing && "is-on"]}
            aria-pressed={to_string(@repairing)}
          >
            {if @repairing, do: "Done", else: "Repair"}
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

        <form :if={@dusting} id="dust" phx-submit="find_dust" class="adm-dr-section">
          <div class="adm-dr-section-head">
            <h2 class="adm-dr-section-title">Dust</h2>
            <button
              :if={@recipe.spots != []}
              type="button"
              phx-click="clear_spots"
              class="adm-dr-reset"
            >
              Clear all
            </button>
          </div>
          <label class="adm-dr-control">
            <span class="adm-dr-label">How keen</span>
            <output class="adm-dr-value">{length(@recipe.spots)} healed</output>
            <input
              type="range"
              name="sensitivity"
              min="0"
              max="100"
              step="5"
              value="60"
              class="adm-dr-range adm-dr-track--plain"
            />
          </label>
          <button type="submit" class="adm-btn adm-btn--small">Find dust</button>
          <p class="adm-dr-hint">
            Finds small dark specks on smooth ground: dust on a slide, or on a black and white
            negative's print. Click a speck to heal it; click a ring to take it off. White specks on
            colour negatives are taken out when the frame is developed.
          </p>
        </form>

        <section :if={@repairing} id="repair" class="adm-dr-section">
          <div class="adm-dr-section-head">
            <h2 class="adm-dr-section-title">Repair</h2>
            <button :if={@masked} type="button" phx-click="clear_mask" class="adm-dr-reset">
              Clear the mask
            </button>
          </div>
          <div class="adm-dr-brush" id="brush-controls" phx-update="ignore">
            <label class="adm-dr-control">
              <span class="adm-dr-label">Brush</span>
              <input
                id="brush"
                type="range"
                min="3"
                max="120"
                value="18"
                class="adm-dr-range adm-dr-track--plain"
              />
            </label>
            <label class="adm-cut-check">
              <input type="radio" name="brush-mode" value="paint" checked /> Paint marks
            </label>
            <label class="adm-cut-check">
              <input type="radio" name="brush-mode" value="erase" /> Erase
            </label>
          </div>
          <button
            type="button"
            phx-click="find_lines"
            class="adm-btn adm-btn--small"
            disabled={@working != nil}
          >
            {if @working == :lines, do: "Looking…", else: "Find scanner lines"}
          </button>
          <button
            type="button"
            phx-click="lama"
            class="adm-btn adm-btn--small adm-btn--primary"
            disabled={@working != nil or !@masked}
          >
            {if @working == :lama, do: "Repairing…", else: "Repair what is marked"}
          </button>
          <button
            :if={@repaired}
            type="button"
            phx-click="undo_repair"
            class="adm-btn adm-btn--small adm-btn--quiet"
          >
            Undo the repair
          </button>
          <p class="adm-dr-hint">
            Paint over scratches, hairs and other marks on the picture as it was developed, or let
            it find the scanner's lines. A scanner line is corrected, so what was under it comes
            back as it was; anything else marked is painted by LaMa from what is around it, at the
            picture's own size, with the grain put back (about seven seconds a place). {if @repaired,
              do: "This print is repaired."}
          </p>
        </section>

        <section :if={!@cropping and !@dusting and !@repairing} id="film" class="adm-dr-section">
          <div class="adm-dr-section-head">
            <h2 class="adm-dr-section-title">Film</h2>
            <button
              :if={is_map(@prior) and (@prior.sliders != %{} or @prior.predicted != %{})}
              type="button"
              phx-click="apply_prior"
              class="adm-dr-reset"
            >
              {if @prior.taught + @prior.chosen > 0,
                do: "Start from the film and your taste",
                else: "Start from the film"}
            </button>
          </div>
          <p :if={is_nil(@prior)} class="adm-dr-hint">Reading the film…</p>
          <p :if={@prior == :error} class="adm-dr-hint">The print could not be read.</p>
          <ul :if={is_map(@prior)} class="adm-dr-film">
            <li :for={line <- @prior.lines}>{line}</li>
            <li :if={@prior.taught + @prior.chosen > 0}>
              Your taste, from {@prior.taught} edits and {@prior.chosen} choices{if @prior.predicted !=
                                                                                      %{},
                                                                                    do:
                                                                                      ": " <>
                                                                                        predicted_words(
                                                                                          @prior.predicted,
                                                                                          @schema
                                                                                        )}
            </li>
            <li :if={@prior.taught + @prior.chosen == 0}>
              Your taste is learned from what you save here and choose under Taste.
            </li>
            <li :if={@prior.sliders != %{}}>
              Suggests Temp {round(@prior.sliders["wb.temp"])}, Tint {if @prior.sliders["wb.tint"] >=
                                                                           0,
                                                                         do: "+"}{round(
                @prior.sliders["wb.tint"]
              )}
            </li>
          </ul>
          <form id="exposure" phx-change="exposure">
            <label class="adm-dr-control">
              <span class="adm-dr-label">Exposure time (s), if long</span>
              <input
                type="text"
                inputmode="decimal"
                name="seconds"
                value={@seconds}
                class="adm-input"
                phx-debounce="500"
                placeholder="e.g. 30"
              />
            </label>
          </form>
        </section>

        <form :if={!@cropping and !@dusting and !@repairing} id="adjust" phx-change="adjust">
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

    <script :type={Phoenix.LiveView.ColocatedHook} name=".MaskPainter">
      // The repair mask, painted on a canvas the picture's own size over the
      // picture as developed. Red where marked; the canvas's own opacity
      // makes it translucent, so strokes do not darken where they cross.
      // Lifting the brush sends the mask as a black and white PNG.
      export default {
        mounted() {
          this.canvas = this.el.querySelector("canvas")
          this.canvas.width = parseInt(this.el.dataset.w)
          this.canvas.height = parseInt(this.el.dataset.h)
          this.ctx = this.canvas.getContext("2d")
          this.load(this.el.dataset.mask)
          this.handleEvent("mask-reload", ({url}) => this.load(url))
          const at = (e) => {
            const r = this.canvas.getBoundingClientRect()
            return [(e.clientX - r.left) * this.canvas.width / r.width, (e.clientY - r.top) * this.canvas.height / r.height]
          }
          this.canvas.addEventListener("pointerdown", (e) => {
            e.preventDefault()
            this.canvas.setPointerCapture(e.pointerId)
            this.last = at(e)
            this.stroke(this.last, this.last)
          })
          this.canvas.addEventListener("pointermove", (e) => {
            if (!this.last) return
            const p = at(e)
            this.stroke(this.last, p)
            this.last = p
          })
          const end = () => { if (this.last) { this.last = null; this.send() } }
          this.canvas.addEventListener("pointerup", end)
          this.canvas.addEventListener("pointercancel", end)
        },
        stroke(a, b) {
          const erase = document.querySelector("input[name=brush-mode]:checked")?.value === "erase"
          const size = parseFloat(document.getElementById("brush")?.value || 18)
          const c = this.ctx
          c.globalCompositeOperation = erase ? "destination-out" : "source-over"
          c.strokeStyle = c.fillStyle = "rgb(255, 40, 40)"
          c.lineWidth = size
          c.lineCap = "round"
          c.beginPath(); c.moveTo(a[0], a[1]); c.lineTo(b[0], b[1]); c.stroke()
        },
        load(url) {
          this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)
          const img = new Image()
          img.onload = () => {
            const off = document.createElement("canvas")
            off.width = this.canvas.width; off.height = this.canvas.height
            const o = off.getContext("2d")
            o.drawImage(img, 0, 0, off.width, off.height)
            const d = o.getImageData(0, 0, off.width, off.height)
            for (let i = 0; i < d.data.length; i += 4) {
              const on = d.data[i] > 127
              d.data[i] = 255; d.data[i + 1] = 40; d.data[i + 2] = 40; d.data[i + 3] = on ? 255 : 0
            }
            this.ctx.putImageData(d, 0, 0)
          }
          img.src = url
        },
        send() {
          const off = document.createElement("canvas")
          off.width = this.canvas.width; off.height = this.canvas.height
          const o = off.getContext("2d")
          const d = this.ctx.getImageData(0, 0, off.width, off.height)
          for (let i = 0; i < d.data.length; i += 4) {
            const v = d.data[i + 3] > 0 ? 255 : 0
            d.data[i] = d.data[i + 1] = d.data[i + 2] = v; d.data[i + 3] = 255
          }
          o.putImageData(d, 0, 0)
          this.pushEvent("mask", {png: off.toDataURL("image/png")})
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".DustBox">
      // Dust on the whole picture: a click on the picture heals the speck
      // there, a click on a ring takes it off. Positions are fractions of the
      // picture, which is how LightCraft places a spot whatever the crop.
      export default {
        mounted() {
          this.el.addEventListener("click", (event) => {
            const ring = event.target.closest(".adm-dr-spot")
            if (ring) return this.pushEvent("remove_spot", {index: ring.dataset.index})
            const box = this.el.getBoundingClientRect()
            this.pushEvent("add_spot", {
              x: (event.clientX - box.left) / box.width,
              y: (event.clientY - box.top) / box.height
            })
          })
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
