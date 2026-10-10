defmodule WebWeb.AdminLive.Scanner do
  @moduledoc """
  The scanner studio: a roll from film on the glass to a sheet on `/negatives`.

  The page follows one loop, once per load of the holder, and shows one
  thing to do at a time (`stage/1`):

    * **Load.** Film goes in the holder; the button is Preview.
    * **Select.** The look at the holder (`Driver.pass_args/2`) has read the
      film's format and whether it is colour (`Web.Scanner.Detect`), named
      the roll and made its folder if it had none, added every strip on the
      glass and found their frames. The frames of **this load only** are
      shown as positives, the well exposed ones ticked. The button is Scan.
    * **Scan.** The ticked frames are scanned at print resolution in bands
      and developed. This is the wait. When it ends the page is back at
      Load, for the next strips.

  A load is *pending* from its look until its singles are scanned: another
  Preview before then replaces its strips, since it is the same film looked
  at again. What has been scanned is shown as the roll's collection, the
  prints `/negatives` will serve, and Publish is one press that assembles
  the sheet, checks it and lists the roll.

  The ticks judge the negative, not the picture, so what was proposed and
  what was chosen are both written to the roll's `selects.json`.

  **Nothing after a scan holds the bench.** Singles are developed off the
  page's process, several at once, while the scanner is already on its next
  band; when the last band is in, the page is back at Load whether or not
  the developing has finished. In a batch, a roll that has reached its
  number of strips is finished and published the same way, in the
  background, and the next roll is on the bench at once.

  The run of scans is this page's: closing it stops the run after the scan
  under way.

  The scanner belongs to `Web.Scanner.Bed`, not to this page: a scan is
  started here and its progress arrives over PubSub, so the page stays
  responsive during one and finds it still running after a reload. The slow
  tools run under `start_async` for the same reason.

  With no scanner connected the page says so and scans nothing — strips can
  still be uploaded. (`Web.Scanner.Simulation` stands in for the hardware in
  dev and test only.)
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Negatives
  alias Web.Negatives.RollMeta
  alias Web.Scanner
  alias Web.Scanner.{Bed, Detect, Driver, Simulation}

  @formats [{"120", "120"}, {"35mm", "35mm"}, {"620", "620"}, {"110", "110"}]
  @colors [{"bw", "Black & white"}, {"color", "Colour (C-41)"}]

  @impl true
  def mount(_params, session, socket) do
    if session["admin_user"] do
      status =
        if connected?(socket) do
          Bed.subscribe()
          Bed.refresh()
          Bed.status()
        else
          %{devices: nil, job: nil}
        end

      {:ok,
       socket
       |> assign(
         page_title: "Scanner | Admin",
         simulation?: Simulation.enabled?(),
         devices: status.devices,
         scanner: status.devices && Driver.pick(status.devices),
         job: status.job,
         working: nil,
         bed_preview: nil,
         drawer: nil,
         preview_strip: nil,
         preview_data: nil,
         positive?: true,
         published_roll: nil,
         frames: [],
         frame_thumbs: %{},
         ticked: MapSet.new(),
         load_strips: [],
         singles: %{},
         run: [],
         stopped?: false,
         publish_error: nil,
         developing: %{},
         closing: %{},
         roll_end: nil,
         waiting_rolls: [],
         then_publish?: false,
         batch: batch_setting(),
         meta: RollMeta.read(""),
         meta_error: nil,
         queue: [],
         archive_rolls: Negatives.list_contact_sheets()
       )
       |> open_roll_on_the_bench()
       |> allow_upload(:strip_scans,
         accept: ~w(.tif .tiff .png .jpg .jpeg),
         max_entries: 8,
         max_file_size: 300_000_000,
         auto_upload: true,
         progress: &handle_upload_progress/3
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab =
      case params["tab"] do
        "archive" -> :archive
        "setup" -> :setup
        _ -> :studio
      end

    {:noreply, assign(socket, :tab, tab)}
  end

  defp today, do: Date.to_iso8601(Web.Clock.local_today())

  # The roll already begun and not yet published, so a reload carries on with
  # it; else the next free number.
  defp open_roll_on_the_bench(socket) do
    case Scanner.roll_in_progress() do
      {roll_num, date, format, color} -> open_roll(socket, roll_num, date, format, color)
      nil -> open_new_roll(socket)
    end
  end

  defp open_new_roll(socket) do
    open_roll(socket, Scanner.next_roll_number(), today(), "120", "bw")
  end

  # Everything that follows from which roll is on the bench.
  defp open_roll(socket, roll_num, date, format, color) do
    dir = Scanner.roll_dir(roll_num, date, format, color)
    slug = Scanner.roll_folder_name(roll_num, date, format, color)

    socket
    |> assign(
      roll_num: roll_num,
      roll_date: date,
      roll_format: format,
      roll_color: color,
      roll_dir: dir,
      roll_slug: slug,
      sheet_path: Path.join(Negatives.contact_sheets_path(), "#{slug}.png"),
      roll_initialized: File.dir?(dir),
      preview_strip: nil,
      preview_data: nil,
      frame_thumbs: %{},
      ticked: MapSet.new(),
      load_strips: [],
      singles: %{},
      run: [],
      stopped?: false,
      publish_error: nil,
      then_publish?: false,
      meta: RollMeta.read(dir),
      meta_error: nil,
      queue: []
    )
    |> reload_roll()
    |> propose(Scanner.pending_load(dir))
    |> resume_owed()
    |> load_thumbs()
    |> refresh_singles()
  end

  # A run that was cut short left singles chosen and not made. If their
  # strips have not moved, they are put back up, ticked, so one press
  # finishes them. Nothing is scanned without that press.
  defp resume_owed(socket) do
    owed = Enum.filter(Scanner.owed_singles(socket.assigns.roll_dir), & &1.on_glass?)

    if socket.assigns.load_strips == [] and owed != [] and socket.assigns.published_roll == nil do
      socket
      |> assign(
        load_strips: owed |> Enum.map(& &1.strip) |> Enum.uniq(),
        ticked: MapSet.new(owed, & &1.frame)
      )
    else
      socket
    end
  end

  # Strips found on the glass again are put up to choose from. Nothing is
  # proposed: what the roll already has, it has, and more is the author's
  # to pick. Only singles chosen before and never made come back ticked.
  defp offer_found(socket, files) do
    owed =
      for single <- Scanner.owed_singles(socket.assigns.roll_dir),
          single.strip in files,
          do: single.frame

    socket |> propose(files) |> assign(ticked: MapSet.new(owed))
  end

  # What is on disk for the roll, read again after anything that changes it.
  defp reload_roll(socket) do
    %{roll_dir: dir} = socket.assigns

    frames = Scanner.frames(dir)
    known = MapSet.new(frames, & &1.frame)

    socket
    |> assign(
      strips: Scanner.list_strips(dir),
      analysed?: File.regular?(Path.join(dir, "frames.json")),
      keeper_frames: Scanner.printed_frames(dir),
      frames: frames
    )
    |> update(:ticked, &MapSet.intersection(&1, known))
    |> update(:load_strips, fn strips ->
      Enum.filter(strips, fn strip -> Enum.any?(frames, &(&1.strip == strip)) end)
    end)
  end

  # Puts some strips up for choosing from, with the proposal ticked: the
  # strips given, else the ones already up. No strips is no choosing.
  defp propose(socket, strips \\ nil) do
    frames = socket.assigns.frames
    with_frames = frames |> Enum.map(& &1.strip) |> Enum.uniq()
    shown = Enum.filter(strips || socket.assigns.load_strips, &(&1 in with_frames))

    ticked =
      for frame <- frames, frame.strip in shown, Scanner.suggested?(frame), do: frame.frame

    assign(socket, load_strips: shown, ticked: MapSet.new(ticked))
  end

  # Where the loop is. Derived, so a reload or a second tab cannot disagree
  # with the scanner or the disk about it.
  defp stage(assigns) do
    cond do
      match?(%{kind: kind} when kind in [:pass, :find], assigns.job) or assigns.working == :pass ->
        :looking

      assigns.job != nil or assigns.working == :develop or assigns.queue != [] ->
        :scanning

      assigns.working == :finish ->
        :publishing

      assigns.published_roll != nil ->
        :published

      assigns.load_strips != [] ->
        :select

      true ->
        :load
    end
  end

  # The load is done with: its strips are the roll's, and the bench is clear
  # for the next film. In a batch, a roll that now has its number of strips
  # is closed and the next one begun.
  # Settles the load on the glass: what is ticked is written down, then scanned.
  defp scan_singles(socket) do
    %{roll_dir: dir, ticked: ticked} = socket.assigns
    offered = shown_frames(socket.assigns)
    chosen = for frame <- offered, MapSet.member?(ticked, frame.frame), do: frame.frame

    cond do
      offered == [] ->
        socket

      busy?(socket.assigns) or socket.assigns.queue != [] ->
        put_flash(socket, :error, "The scanner is busy.")

      true ->
        Scanner.confirm_load(dir)
        Scanner.record_selects(dir, offered, chosen)

        if chosen == [] do
          finish_load(
            socket,
            "No singles from this load. Load the next strips and press Preview."
          )
        else
          socket
          |> assign(queue: scans_for(socket, chosen), run: [], stopped?: false)
          |> scan_next_keeper()
        end
    end
  end

  defp finish_load(socket, said) do
    Scanner.confirm_load(socket.assigns.roll_dir)

    socket
    |> assign(load_strips: [], ticked: MapSet.new(), bed_preview: nil, run: [], stopped?: false)
    |> refresh_singles()
    |> put_flash(:info, said)
    |> settle_roll()
  end

  @batch_setting "scanner_strips_per_roll"

  # How many strips make a roll in a batch, or nil when rolls are closed by hand.
  defp batch_setting do
    case Integer.parse(to_string(Web.SiteSettings.get_setting(@batch_setting, "7"))) do
      {count, _} when count in 1..40 -> count
      _ -> nil
    end
  end

  # The strip chosen to begin the next roll is put last, if it is not: with
  # one strip over, that is the roll's last two changing places.
  defp swap_to_last(dir, files, chosen, batch) do
    if length(files) == batch + 1 and chosen == Enum.at(files, batch - 1) do
      {kept, [a, b]} = Enum.split(files, batch - 1)
      Scanner.reorder_strips(dir, kept ++ [b, a])
      Scanner.generate_frames_analysis_for(dir)
      :ok
    else
      :ok
    end
  end

  # What a settled load leaves the roll owing. Nothing is published here: a
  # roll past a sleeve's count is asked where it ends (`roll_end`), and one
  # that is complete waits on the bench's list until Publish is pressed.
  # Only "Publish" pressed with frames still ticked publishes by itself, since
  # that is what was asked for.
  defp settle_roll(socket) do
    a = socket.assigns
    listed? = Enum.any?(a.archive_rolls, &(&1.roll == a.roll_num))

    cond do
      a.then_publish? and a.published_roll == nil ->
        publish_and_move_on(socket)

      a.batch && not listed? && a.published_roll == nil && length(a.strips) > a.batch ->
        assign(socket, roll_end: roll_end(a.strips, a.batch)) |> assign_waiting()

      true ->
        assign(socket, roll_end: nil) |> assign_waiting()
    end
  end

  # The strips the next roll may begin with. One strip over, and it came onto
  # the glass with the roll's last: either may be the one that belongs to the
  # next roll, and only the author knows which. More than one over, and the
  # roll simply ends at the sleeve's count.
  defp roll_end(strips, batch) do
    files = Enum.map(strips, & &1.file)

    options =
      if length(files) == batch + 1,
        do: Enum.slice(files, batch - 1, 2),
        else: [Enum.at(files, batch)]

    %{options: options, chosen: Enum.at(files, batch), next: Scanner.next_roll_number()}
  end

  # A roll with exactly a sleeve's worth, settled and not yet published.
  defp roll_full?(a) do
    a.batch != nil and a.roll_end == nil and a.load_strips == [] and a.published_roll == nil and
      length(a.strips) == a.batch and not Enum.any?(a.archive_rolls, &(&1.roll == a.roll_num))
  end

  # Rolls that are complete on disk and wait for Publish: every roll not yet
  # in the catalog but the one on the bench.
  defp assign_waiting(socket) do
    assign(socket, waiting_rolls: Scanner.unpublished_rolls(except: socket.assigns.roll_num))
  end

  defp publish_and_move_on(socket) do
    a = socket.assigns
    roll = {a.roll_num, a.roll_date, a.roll_format, a.roll_color}
    begun = Scanner.roll_in_progress(except: a.roll_num)
    socket = update(socket, :closing, &Map.put(&1, a.roll_dir, {:waiting, roll}))
    why = "Roll #{a.roll_num} has its singles and is being published. "

    socket =
      case begun do
        {roll_num, date, format, color} ->
          socket
          |> open_roll(roll_num, date, format, color)
          |> put_flash(:info, why <> "Roll #{roll_num} is on the bench.")

        nil ->
          socket
          |> open_new_roll()
          |> put_flash(
            :info,
            why <>
              "Roll #{Scanner.next_roll_number()} is on the bench: load it and press Preview."
          )
      end

    publish_closed(socket, a.roll_dir)
  end

  # A closed roll is published once the last of its singles is developed.
  defp publish_closed(socket, dir) do
    waiting = Map.get(socket.assigns.developing, dir, MapSet.new())

    case socket.assigns.closing[dir] do
      {:waiting, {roll_num, date, format, color} = roll} ->
        if MapSet.size(waiting) == 0 do
          socket
          |> update(:closing, &Map.put(&1, dir, {:publishing, roll}))
          |> start_async({:finish, dir}, fn ->
            Scanner.finish_roll(roll_num, date, format, color)
          end)
        else
          socket
        end

      _ ->
        socket
    end
  end

  # --- Events: the roll -------------------------------------------------------

  @impl true
  def handle_event("update_roll_config", params, socket) do
    a = socket.assigns

    roll_num = valid(params["roll_num"], ~r/\A\d{1,4}\z/, a.roll_num)
    date = valid(params["date"], ~r/\A\d{4}-\d{2}-\d{2}\z/, a.roll_date)
    format = one_of(params["format"], @formats, a.roll_format)
    color = one_of(params["color"], @colors, a.roll_color)

    {:noreply, socket |> assign(published_roll: nil) |> open_roll(roll_num, date, format, color)}
  end

  def handle_event("initialize_roll", _params, socket) do
    %{roll_num: roll_num, roll_date: date, roll_format: format, roll_color: color} =
      socket.assigns

    {:ok, dir} = Scanner.prepare_roll(roll_num, date, format, color)
    RollMeta.write(dir, socket.assigns.meta)
    {:noreply, socket |> assign(roll_initialized: true) |> reload_roll()}
  end

  # What the author knows of the roll. Said before the roll has a folder, it
  # is held here and written when the first preview (or the button) makes one.
  def handle_event("update_roll_meta", params, socket) do
    case RollMeta.cast(params) do
      {:ok, meta} ->
        RollMeta.write(socket.assigns.roll_dir, meta)
        {:noreply, assign(socket, meta: meta, meta_error: nil)}

      {:error, said} ->
        {:noreply, assign(socket, meta_error: said)}
    end
  end

  # The roll's settings and its strips are each a drawer under the bar, one
  # open at a time, so the frames keep the screen.
  def handle_event("drawer", %{"name" => name}, socket) do
    drawer =
      case name do
        "roll" -> :roll
        "strips" -> :strips
        _ -> nil
      end

    {:noreply, update(socket, :drawer, &if(&1 == drawer, do: nil, else: drawer))}
  end

  def handle_event("new_roll", _params, socket) do
    {:noreply, socket |> assign(published_roll: nil, bed_preview: nil) |> open_new_roll()}
  end

  # From a roll reopened for more singles, back to where new film goes.
  def handle_event("back_to_bench", _params, socket) do
    {:noreply,
     socket |> assign(published_roll: nil, bed_preview: nil) |> open_roll_on_the_bench()}
  end

  def handle_event("load_archive_roll", %{"roll" => roll_num}, socket) do
    case Enum.find(socket.assigns.archive_rolls, &(&1.roll == roll_num)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Roll #{roll_num} is not in the archive.")}

      roll ->
        {:noreply,
         socket
         |> open_roll(roll.roll, roll.date, roll.format, roll.color)
         |> push_patch(to: ~p"/admin/scanner")}
    end
  end

  # --- Events: the scanner ----------------------------------------------------

  def handle_event("refresh_devices", _params, socket) do
    Bed.refresh()
    {:noreply, assign(socket, devices: nil, scanner: nil)}
  end

  def handle_event("preview", _params, socket) do
    a = socket.assigns

    cond do
      a.roll_end != nil ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Roll #{a.roll_num} has more strips than a sleeve holds. Say which begins roll #{a.roll_end.next} first."
         )}

      true ->
        # A roll with its sleeve's worth takes no more: the next look begins
        # the next roll, and this one waits on the list to be published.
        socket = if roll_full?(a), do: socket |> open_new_roll() |> assign_waiting(), else: socket

        target =
          Path.join(System.tmp_dir!(), "scanner_pass_#{System.unique_integer([:positive])}.tiff")

        {:noreply, start_scan(socket, %{kind: :pass, target: target})}
    end
  end

  def handle_event("choose_roll_end", %{"file" => file}, socket) do
    case socket.assigns.roll_end do
      %{options: options} = roll_end ->
        chosen = if file in options, do: file, else: roll_end.chosen
        {:noreply, assign(socket, roll_end: %{roll_end | chosen: chosen})}

      nil ->
        {:noreply, socket}
    end
  end

  # The author says which strip begins the next roll. If it is not the last
  # on this one it changes places with the last first, its singles going
  # with it, and then the roll is cut there.
  def handle_event("end_roll", _params, socket) do
    a = socket.assigns

    with %{chosen: chosen} <- a.roll_end,
         false <- busy?(a) or a.queue != [] or developing?(a),
         files = Enum.map(a.strips, & &1.file),
         :ok <- swap_to_last(a.roll_dir, files, chosen, a.batch),
         from = Enum.at(Enum.map(Scanner.list_strips(a.roll_dir), & &1.file), a.batch),
         {:ok, {number, date, format, color}} <- Scanner.split_roll(a.roll_dir, from) do
      {:noreply,
       socket
       |> assign(roll_end: nil, preview_strip: nil, preview_data: nil, bed_preview: nil)
       |> open_roll(number, date, format, color)
       |> assign_waiting()
       |> put_flash(
         :info,
         "Roll #{a.roll_num} keeps #{a.batch} strips and waits to be published. " <>
           "Roll #{number} is on the bench with its first strip."
       )}
    else
      nil ->
        {:noreply, socket}

      true ->
        {:noreply,
         put_flash(socket, :error, "Wait for the scanner and the developing to finish.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Not split: #{reason}")}
    end
  end

  def handle_event("publish_waiting", %{"roll" => number}, socket) do
    case Enum.find(socket.assigns.waiting_rolls, &(elem(&1, 0) == number)) do
      {roll_num, date, format, color} = roll ->
        dir = Scanner.roll_dir(roll_num, date, format, color)

        {:noreply,
         socket
         |> update(:closing, &Map.put(&1, dir, {:waiting, roll}))
         |> publish_closed(dir)
         |> assign_waiting()}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("open_waiting", %{"roll" => number}, socket) do
    case Enum.find(socket.assigns.waiting_rolls, &(elem(&1, 0) == number)) do
      {roll_num, date, format, color} ->
        {:noreply,
         socket
         |> assign(published_roll: nil, bed_preview: nil, roll_end: nil)
         |> open_roll(roll_num, date, format, color)
         |> assign_waiting()}

      nil ->
        {:noreply, socket}
    end
  end

  # --- Events: prints -----------------------------------------------------------

  # Film that was scanned before has been laid back in the holder: look at
  # the glass and find which of this roll's strips it is, and where.
  def handle_event("find_on_glass", _params, socket) do
    target =
      Path.join(System.tmp_dir!(), "scanner_pass_#{System.unique_integer([:positive])}.tiff")

    {:noreply, start_scan(socket, %{kind: :find, target: target})}
  end

  # The same, without saying which roll: the film is matched against every
  # roll there is, and the roll it belongs to is opened.
  def handle_event("add_singles", _params, socket) do
    cond do
      busy?(socket.assigns) or socket.assigns.queue != [] ->
        {:noreply, put_flash(socket, :error, "The scanner is busy.")}

      Scanner.pending_load(socket.assigns.roll_dir) != [] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Roll #{socket.assigns.roll_num} has a load still to settle. Scan or discard it first."
         )}

      true ->
        target =
          Path.join(System.tmp_dir!(), "scanner_pass_#{System.unique_integer([:positive])}.tiff")

        {:noreply,
         socket
         |> push_patch(to: ~p"/admin/scanner")
         |> start_scan(%{kind: :find, target: target, meta: %{whose: true}})}
    end
  end

  # The strips of the last load, while the film is still where it was.
  def handle_event("reselect", _params, socket) do
    strips = socket.assigns.roll_dir |> Scanner.holder() |> Map.keys() |> Enum.sort()
    {:noreply, propose(socket, strips)}
  end

  # One strip put back in the holder by hand, or dropped onto the page.
  def handle_event("pick_singles", %{"file" => file}, socket) do
    case strip_path(socket, file) do
      {:ok, _path} -> {:noreply, socket |> assign(drawer: nil) |> propose([file])}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("toggle_frame", %{"frame" => frame}, socket) do
    with {number, ""} <- Integer.parse(frame),
         %{} <- Enum.find(shown_frames(socket.assigns), &(&1.frame == number)) do
      toggle = fn ticked ->
        if MapSet.member?(ticked, number),
          do: MapSet.delete(ticked, number),
          else: MapSet.put(ticked, number)
      end

      {:noreply, update(socket, :ticked, toggle)}
    else
      _ -> {:noreply, socket}
    end
  end

  # The end of choosing: the load's strips are the roll's from here, and the
  # scanner goes back for the ticked frames at print resolution, in as few
  # crossings of the glass as cover them. With nothing ticked the load is
  # simply done.
  def handle_event("scan_singles", _params, socket), do: {:noreply, scan_singles(socket)}

  # The load on the glass is not wanted after all: its strips come back out.
  def handle_event("discard_load", _params, socket) do
    if busy?(socket.assigns) or socket.assigns.queue != [] do
      {:noreply, socket}
    else
      Scanner.discard_load(socket.assigns.roll_dir)

      {:noreply,
       socket
       |> assign(load_strips: [], ticked: MapSet.new(), bed_preview: nil)
       |> reload_roll()
       |> analyse_again()
       |> put_flash(:info, "That load was taken back out of the roll.")}
    end
  end

  def handle_event("update_batch", %{"strips" => strips}, socket) do
    value =
      case Integer.parse(String.trim(strips)) do
        {count, ""} when count in 1..40 -> Integer.to_string(count)
        # A setting cannot be saved empty, so blank is a word: left blank,
        # the old number stayed and the count was never turned off.
        _ -> "off"
      end

    Web.SiteSettings.put_setting(@batch_setting, value)
    {:noreply, assign(socket, batch: batch_setting())}
  end

  def handle_event("remove_single", %{"frame" => frame}, socket) do
    with {number, ""} <- Integer.parse(frame),
         true <- number in socket.assigns.keeper_frames,
         false <- busy?(socket.assigns) do
      Scanner.remove_print(socket.assigns.roll_dir, number)
      {:noreply, socket |> reload_roll() |> refresh_singles()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("stop_queue", _params, socket) do
    {:noreply, assign(socket, queue: [], stopped?: true, then_publish?: false)}
  end

  # --- Events: strips ---------------------------------------------------------

  def handle_event("move_strip", %{"index" => index, "by" => by}, socket) do
    names = Enum.map(socket.assigns.strips, & &1.file)
    from = String.to_integer(index) - 1
    to = from + if(by == "up", do: -1, else: 1)

    if from in 0..(length(names) - 1)//1 and to in 0..(length(names) - 1)//1 do
      {moved, rest} = List.pop_at(names, from)
      Scanner.reorder_strips(socket.assigns.roll_dir, List.insert_at(rest, to, moved))
    end

    {:noreply,
     socket |> assign(preview_strip: nil, preview_data: nil) |> reload_roll() |> analyse_again()}
  end

  def handle_event("rotate_strip", %{"file" => file}, socket) do
    with {:ok, path} <- strip_path(socket, file),
         :ok <- Scanner.rotate_strip(path, 180) do
      {:noreply, socket |> reload_roll() |> show_strip(file) |> analyse_again()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Couldn't rotate #{file}.")}
    end
  end

  def handle_event("delete_strip", %{"file" => file}, socket) do
    with {:ok, _path} <- strip_path(socket, file) do
      Scanner.delete_strip(socket.assigns.roll_dir, file)
    end

    {:noreply,
     socket |> assign(preview_strip: nil, preview_data: nil) |> reload_roll() |> analyse_again()}
  end

  # The author says where one roll ends and the next begins.
  def handle_event("split_roll", %{"file" => file}, socket) do
    with {:ok, _path} <- strip_path(socket, file),
         false <-
           busy?(socket.assigns) or socket.assigns.queue != [] or developing?(socket.assigns),
         {:ok, {number, _date, _format, _color}} <-
           Scanner.split_roll(socket.assigns.roll_dir, file) do
      socket =
        socket
        |> assign(preview_strip: nil, preview_data: nil)
        |> reload_roll()
        |> propose(Scanner.pending_load(socket.assigns.roll_dir))
        |> load_thumbs()
        |> refresh_singles()
        |> put_flash(
          :info,
          "#{file} and what followed it began roll #{number}. Finish this roll and that one opens."
        )

      # A roll cut back to nothing left to settle may now be full, or done.
      {:noreply, if(socket.assigns.load_strips == [], do: settle_roll(socket), else: socket)}
    else
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Not split: #{reason}")}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Wait for the scanner and the developing to finish.")}
    end
  end

  def handle_event("select_strip_preview", %{"file" => file}, socket) do
    {:noreply, socket |> assign(drawer: :strips) |> show_strip(file)}
  end

  # --- Events: which way up ---------------------------------------------------

  # The picture of the last scan and of a strip are only looked at, so turning
  # one turns the picture and nothing on disk.
  def handle_event("turn_glass", _params, socket) do
    {:noreply, update(socket, :bed_preview, &turned/1)}
  end

  def handle_event("turn_look", _params, socket) do
    {:noreply, update(socket, :preview_data, &turned/1)}
  end

  # A frame's turn is kept, and is the way its print is made.
  def handle_event("turn_frame", %{"frame" => frame}, socket) do
    with {number, ""} <- Integer.parse(frame),
         %{} <- Enum.find(socket.assigns.frames, &(&1.frame == number)),
         false <- busy?(socket.assigns) do
      Scanner.turn_frame(socket.assigns.roll_dir, number)
      socket = refresh_singles(socket)

      {:noreply,
       update(socket, :frame_thumbs, &Map.replace_lazy(&1, number, fn data -> turned(data) end))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_positive", _params, socket) do
    {:noreply, update(socket, :positive?, &(!&1))}
  end

  # --- Events: analysis, sheet, publishing --------------------------------------

  def handle_event("run_analysis", _params, socket) do
    {:noreply, analyse(socket)}
  end

  # Sheet, checks and catalog in one go, off the page's process.
  def handle_event("publish", _params, socket) do
    %{roll_num: roll_num, roll_date: date, roll_format: format, roll_color: color} =
      socket.assigns

    cond do
      busy?(socket.assigns) or socket.assigns.queue != [] or developing?(socket.assigns) ->
        {:noreply,
         put_flash(socket, :error, "Wait for the scanner and the developing to finish.")}

      # A load is up with frames ticked. Publishing used to drop them: the
      # roll went out and what had been chosen was neither scanned nor written
      # down (roll 033's last load, 2026-10-07). The singles come first, and
      # the roll is published when they are in.
      socket.assigns.load_strips != [] and MapSet.size(socket.assigns.ticked) > 0 ->
        {:noreply, socket |> assign(then_publish?: true) |> scan_singles()}

      true ->
        publish_now(socket, roll_num, date, format, color)
    end
  end

  defp publish_now(socket, roll_num, date, format, color) do
    {:noreply,
     socket
     |> assign(working: :finish, publish_error: nil)
     |> start_async(:tool, fn ->
       {:finish, Scanner.finish_roll(roll_num, date, format, color)}
     end)}
  end

  # Moving, turning or deleting a strip throws the analysis away, and with it
  # the frames to pick from, so it is made again at once.
  defp analyse_again(%{assigns: %{strips: []}} = socket), do: socket
  defp analyse_again(socket), do: analyse(socket)

  # Analyses the roll and reads back a small picture of each frame found.
  defp analyse(socket) do
    %{roll_dir: dir, roll_format: format, roll_color: color, roll_slug: slug} = socket.assigns

    socket
    |> assign(working: :analysis)
    |> start_async(:tool, fn ->
      export = fresh_thumbs_dir(slug)
      result = Scanner.generate_frames_analysis(dir, format, color, export: export)
      {:analysis, result, frame_thumbs(export, dir)}
    end)
  end

  defp fresh_thumbs_dir(slug) do
    export = thumbs_dir(slug)
    File.rm_rf(export)
    File.mkdir_p!(export)
    File.chmod(export, 0o700)
    export
  end

  # Everything one pass over the holder gives, off the page's own process:
  # what the film is, the strips, their frames. `{:pass, result, picture}`.
  defp take_pass(socket, target, dpi) do
    roll =
      Map.take(
        socket.assigns,
        ~w(roll_num roll_date roll_format roll_color roll_initialized roll_dir batch)a
      )

    socket
    |> assign(working: :pass)
    |> start_async(:tool, fn ->
      picture = thumbnail(target, "1200x1200>", :landscape)

      result =
        case Detect.read(target, dpi) do
          {:ok, read} -> file_pass(roll, target, dpi, read)
          :none -> :none
        end

      File.rm(target)
      {:pass, result, picture}
    end)
  end

  defp file_pass(roll, target, dpi, read) do
    # A load looked at and not yet settled is the same film looked at again:
    # its strips come back out before these go in. If that leaves the roll
    # with nothing in it, the roll is not begun, and this look names it.
    Scanner.discard_load(roll.roll_dir)

    roll =
      if roll.roll_initialized and Scanner.list_strips(roll.roll_dir) == [] and
           Scanner.printed_frames(roll.roll_dir) == [] do
        File.rm(Path.join(roll.roll_dir, "selects.json"))
        File.rmdir(Path.join(roll.roll_dir, "frames"))
        File.rmdir(roll.roll_dir)
        %{roll | roll_initialized: File.dir?(roll.roll_dir)}
      else
        roll
      end

    # 620 is 120 film and measures the same, so it stays as it was set. Once
    # the roll has a folder its name is on disk: the film's colour is then the
    # roll's (the reading of it has the narrower margin), and only a strip of
    # another width, which cannot be this roll's, is refused.
    format = if read.format == "120" and roll.roll_format == "620", do: "620", else: read.format
    color = if roll.roll_initialized, do: roll.roll_color, else: read.color

    if roll.roll_initialized and format != roll.roll_format do
      {:mismatch, format, read.color}
    else
      {:ok, dir} = Scanner.prepare_roll(roll.roll_num, roll.roll_date, format, color)

      rows =
        case Driver.area(format) do
          {_left, top, _width, tall} -> {top, tall}
          nil -> nil
        end

      # A load is never divided before it is worked. The holder is loaded
      # two at a time, so the strip that fills a roll often shares the glass
      # with the first strip of the next; both join this roll, their singles
      # are chosen and scanned together, and where the roll ends is asked
      # once the load is settled (`settle_roll/1`). It used to be decided
      # here, by which slot a strip lay in, before anything had been seen.
      strips = Enum.sort_by(read.strips, & &1.left_mm)
      spilled = nil

      with {:ok, names} <- add_strips(dir, target, dpi, strips, color, rows) do
        slug = Scanner.roll_folder_name(roll.roll_num, roll.roll_date, format, color)
        export = fresh_thumbs_dir(slug)
        analysis = Scanner.generate_frames_analysis(dir, format, color, export: export)
        {:ok, format, color, names, analysis, frame_thumbs(export, dir), spilled}
      end
    end
  end

  defp add_strips(_dir, _target, _dpi, [], _color, _rows), do: {:ok, []}

  defp add_strips(dir, target, dpi, strips, color, rows),
    do: Scanner.add_pass(dir, target, dpi, strips, color, rows)

  # --- Scans ------------------------------------------------------------------

  defp start_scan(socket, job) do
    case try_scan(socket, job) do
      {:ok, socket} -> socket
      {:error, socket} -> socket
    end
  end

  # `:error` when nothing was started, which is what ends a run of frames.
  defp try_scan(socket, job) do
    %{scanner: scanner, simulation?: simulation?} = socket.assigns
    # Every open studio hears the scanner. Only the one that asked acts on
    # the result, or two tabs would each cut the same scan into the roll.
    job = Map.put(job, :owner, self())

    cond do
      scanner ->
        case Bed.scan(job, scan_args(socket, scanner.id, job)) do
          :ok ->
            {:ok, socket}

          {:error, :busy} ->
            {:error, put_flash(socket, :error, "The scanner is already scanning.")}

          {:error, reason} ->
            {:error, put_flash(socket, :error, "Couldn't start the scan: #{reason}")}
        end

      simulation? ->
        case simulate(socket, job) do
          {:ok, _path} ->
            {:ok, scan_done(socket, job)}

          {:error, reason} ->
            {:error, put_flash(socket, :error, "Simulated scan failed: #{reason}")}
        end

      true ->
        {:error, put_flash(socket, :error, "No scanner is connected.")}
    end
  end

  # What the scanner has to do for the chosen frames. A frame whose strip is
  # where the last pass left it is found on the glass and shares a band with
  # its neighbours; one whose strip was put back by hand is scanned alone,
  # with room around it. (The simulation draws frames, not a holder, so there
  # every frame is scanned alone.)
  defp scans_for(socket, frames) do
    %{roll_dir: dir, scanner: scanner} = socket.assigns
    margin = Driver.keeper_margin(:in_place)

    {placed, loose} =
      frames
      |> Enum.map(&{&1, scanner && Scanner.glass_rect(dir, &1, margin)})
      |> Enum.split_with(fn {_frame, rect} -> rect end)

    Enum.map(Driver.bands(placed), &{:band, &1}) ++
      Enum.map(loose, fn {frame, _} -> {:frame, frame} end)
  end

  # The next scan of the run, if there is one.
  defp scan_next_keeper(%{assigns: %{queue: []}} = socket), do: socket

  defp scan_next_keeper(%{assigns: %{queue: [item | rest]}} = socket) do
    dir = socket.assigns.roll_dir

    job =
      case item do
        {:band, band} ->
          target =
            Path.join(
              System.tmp_dir!(),
              "scanner_band_#{System.unique_integer([:positive])}.tiff"
            )

          %{kind: :band, target: target, meta: %{band: band}}

        {:frame, frame} ->
          %{
            kind: :keeper,
            target: Scanner.keeper_raw_path(dir, frame),
            meta: %{frame: frame, margin: Driver.keeper_margin(:put_back)}
          }
      end

    case try_scan(assign(socket, queue: rest), job) do
      {:ok, socket} -> socket
      {:error, socket} -> assign(socket, queue: [], then_publish?: false)
    end
  end

  defp scan_args(socket, device, %{kind: kind, target: target} = job) do
    %{roll_format: format, roll_color: color, roll_dir: dir} = socket.assigns
    output = Bed.partial(target)

    case kind do
      kind when kind in [:pass, :find] ->
        Driver.pass_args(device, output)

      :band ->
        Driver.band_args(device, color, job.meta.band.rect, output, deep: Scanner.slide?(dir))

      :keeper ->
        region = Scanner.frame_region(dir, job.meta.frame)
        margin = Map.get(job.meta, :margin, Driver.keeper_margin(:put_back))

        Driver.keeper_args(device, format, color, region, output, margin,
          deep: Scanner.slide?(dir)
        )
    end
  end

  defp simulate(socket, %{kind: kind, target: target} = job) do
    %{roll_format: format, roll_color: color} = socket.assigns

    case kind do
      kind when kind in [:pass, :find] -> Simulation.preview(target, format, color)
      :keeper -> Simulation.keeper(target, job.meta.frame, color)
    end
  end

  # The simulation draws its holder 600 px across the 68.6 mm of the real one.
  @simulated_dpi 222

  # A look that adds nothing, over film that could be any roll's: every roll
  # of that width of film is asked whether these are its strips.
  defp scan_done(socket, %{kind: :find, target: target, meta: %{whose: true}}) do
    dpi = if socket.assigns.scanner, do: Driver.pass_dpi(), else: @simulated_dpi
    a = socket.assigns

    # The roll on the bench may not be listed yet, and is asked too.
    bench = %{roll: a.roll_num, date: a.roll_date, format: a.roll_format, color: a.roll_color}

    rolls =
      [bench | Enum.reject(a.archive_rolls, &(&1.roll == a.roll_num))]
      |> Enum.map(fn roll ->
        %{
          roll: roll.roll,
          date: roll.date,
          format: roll.format,
          color: roll.color,
          dir: Scanner.roll_dir(roll.roll, roll.date, roll.format, roll.color)
        }
      end)

    socket
    |> assign(working: :pass)
    |> start_async(:tool, fn ->
      picture = thumbnail(target, "1200x1200>", :landscape)

      rows = fn roll ->
        case Driver.area(roll.format) do
          {_left, top, _width, tall} -> {top, tall}
          nil -> nil
        end
      end

      result =
        case Detect.read(target, dpi) do
          {:ok, read} ->
            # 120 and 620 are one width of film; 35mm is the other.
            same_width = Enum.filter(rolls, &(&1.format == "35mm" == (read.format == "35mm")))
            Scanner.identify(same_width, target, dpi, read.strips, rows)

          :none ->
            :no_film
        end

      File.rm(target)
      {:whose, result, picture}
    end)
  end

  # A look that adds nothing: it finds strips the roll already has.
  defp scan_done(socket, %{kind: :find, target: target}) do
    dpi = if socket.assigns.scanner, do: Driver.pass_dpi(), else: @simulated_dpi
    %{roll_dir: dir, roll_format: format} = socket.assigns

    socket
    |> assign(working: :pass)
    |> start_async(:tool, fn ->
      picture = thumbnail(target, "1200x1200>", :landscape)

      rows =
        case Driver.area(format) do
          {_left, top, _width, tall} -> {top, tall}
          nil -> nil
        end

      result =
        case Detect.read(target, dpi) do
          {:ok, read} -> Scanner.relocate(dir, target, dpi, read.strips, rows)
          :none -> :none
        end

      File.rm(target)
      {:found, result, picture}
    end)
  end

  defp scan_done(socket, %{kind: :pass, target: target}) do
    dpi = if socket.assigns.scanner, do: Driver.pass_dpi(), else: @simulated_dpi
    take_pass(socket, target, dpi)
  end

  # Every frame the band covers is cut out of it and developed, off the
  # page's process and a few at a time, so the scanner goes straight on to
  # the next band and the bench is free when the last one is in.
  defp scan_done(socket, %{kind: :band, target: target, meta: %{band: band}}) do
    dir = socket.assigns.roll_dir
    dpi = Driver.keeper_dpi()
    frames = Enum.map(band.frames, &elem(&1, 0))

    socket
    |> update(:developing, fn rolls ->
      Map.update(rolls, dir, MapSet.new(frames), &MapSet.union(&1, MapSet.new(frames)))
    end)
    |> update(:ticked, &MapSet.difference(&1, MapSet.new(frames)))
    |> update(:run, &(&1 ++ frames))
    |> start_async({:develop, System.unique_integer([:positive])}, fn ->
      results =
        band.frames
        |> Task.async_stream(
          fn {frame, rect} ->
            with :ok <- Scanner.cut_from_band(dir, frame, target, band.rect, rect, dpi),
                 {:ok, print} <- Scanner.develop_keeper(dir, frame) do
              {frame, {:ok, print}}
            else
              {:error, reason} -> {frame, {:error, reason}}
            end
          end,
          max_concurrency: 3,
          timeout: 180_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      File.rm(target)
      {dir, results}
    end)
    |> scanned()
  end

  defp scan_done(socket, %{kind: :keeper, meta: %{frame: frame}}) do
    dir = socket.assigns.roll_dir

    socket
    |> assign(working: :develop)
    |> start_async(:tool, fn -> {:develop, frame, Scanner.develop_keeper(dir, frame)} end)
  end

  defp film_line(format, "color"), do: "#{format}, colour"
  defp film_line(format, _bw), do: "#{format}, black and white"

  @impl true
  def handle_info({:scanner, :devices, devices}, socket) do
    {:noreply, assign(socket, devices: devices, scanner: Driver.pick(devices))}
  end

  def handle_info({:scanner, :started, job}, socket) do
    {:noreply, assign(socket, job: Map.put(job, :percent, 0))}
  end

  def handle_info({:scanner, :progress, percent}, socket) do
    {:noreply, update(socket, :job, &(&1 && Map.put(&1, :percent, percent)))}
  end

  def handle_info({:scanner, :done, job}, socket) do
    if Map.get(job, :owner, self()) == self() do
      {:noreply, socket |> assign(job: nil) |> scan_done(job)}
    else
      {:noreply, socket |> assign(job: nil) |> reload_roll()}
    end
  end

  # The Epson backend now and then refuses to start with "Invalid argument"
  # when asked straight after another scan; asked again a moment later it
  # goes. One more try, by the page that asked, before it is called a failure.
  def handle_info({:scanner, :failed, job, reason}, socket) do
    mine? = Map.get(job, :owner, self()) == self()

    if mine? and reason =~ "Invalid argument" and not Map.get(job, :retried, false) do
      Process.send_after(self(), {:retry_scan, Map.put(job, :retried, true)}, 2_500)
      {:noreply, assign(socket, job: nil)}
    else
      {:noreply,
       socket
       |> assign(job: nil, queue: [], then_publish?: false)
       |> put_flash(:error, "Scan failed: #{reason}")}
    end
  end

  def handle_info({:retry_scan, job}, socket) do
    case try_scan(socket, job) do
      {:ok, socket} -> {:noreply, socket}
      {:error, socket} -> {:noreply, assign(socket, queue: [], then_publish?: false)}
    end
  end

  # --- The slow tools ---------------------------------------------------------

  @impl true
  def handle_async(:tool, {:ok, result}, socket) do
    socket = socket |> assign(working: nil) |> reload_roll()

    case result do
      {:analysis, {:ok, _path}, thumbs} ->
        socket = socket |> assign(frame_thumbs: thumbs) |> propose()

        {:noreply,
         put_flash(socket, :info, "Analysed: frames.json written. #{found_line(socket)}")}

      {:found, {:ok, [_ | _] = files}, picture} ->
        socket = socket |> assign(bed_preview: picture) |> offer_found(files)

        {:noreply,
         put_flash(
           socket,
           :info,
           "Found #{Enum.join(files, " and ")} on the glass. #{found_line(socket)}"
         )}

      {:whose, {:ok, {roll, files}}, picture} ->
        socket =
          if roll.roll == socket.assigns.roll_num,
            do: socket,
            else: open_roll(socket, roll.roll, roll.date, roll.format, roll.color)

        socket = socket |> assign(bed_preview: picture) |> offer_found(files)

        {:noreply,
         put_flash(
           socket,
           :info,
           "This is roll #{roll.roll}: #{Enum.join(files, " and ")}. Tick the frames to add and scan. " <>
             "They go straight onto the roll's page."
         )}

      {:whose, :no_film, picture} ->
        {:noreply,
         socket
         |> assign(bed_preview: picture)
         |> put_flash(:error, "No film could be read on the glass.")}

      {:whose, _none, picture} ->
        {:noreply,
         socket
         |> assign(bed_preview: picture)
         |> put_flash(
           :error,
           "The film on the glass is not from any roll in the archive. If it is new film, press Preview. " <>
             "If it is an old roll, open that roll from the Archive tab and try Find there."
         )}

      {:found, _none, picture} ->
        {:noreply,
         socket
         |> assign(bed_preview: picture)
         |> put_flash(
           :error,
           "The film on the glass is not one of roll #{socket.assigns.roll_num}'s strips, or there is none there."
         )}

      {:pass, :none, picture} ->
        {:noreply,
         socket
         |> assign(bed_preview: picture)
         |> put_flash(:error, "No film could be read on the glass, so nothing was added.")}

      {:pass, {:mismatch, format, color}, picture} ->
        a = socket.assigns

        {:noreply,
         socket
         |> assign(bed_preview: picture)
         |> put_flash(
           :error,
           "The film on the glass reads as #{film_line(format, color)}, but this roll is " <>
             "#{film_line(a.roll_format, a.roll_color)}. Nothing was added."
         )}

      {:pass, {:error, reason}, picture} ->
        {:noreply, socket |> assign(bed_preview: picture) |> put_flash(:error, reason)}

      {:pass, {:ok, format, color, names, analysis, thumbs, spilled}, picture} ->
        a = socket.assigns

        socket =
          if {format, color} == {a.roll_format, a.roll_color},
            do: socket,
            else: open_roll(socket, a.roll_num, a.roll_date, format, color)

        # What was said of the roll before it had a folder goes into the one
        # this look made, under the name this look gave it.
        socket =
          if RollMeta.empty?(a.meta) or not RollMeta.empty?(socket.assigns.meta) do
            socket
          else
            RollMeta.write(socket.assigns.roll_dir, a.meta)
            assign(socket, meta: a.meta)
          end

        socket =
          socket
          |> assign(
            roll_initialized: true,
            bed_preview: picture,
            frame_thumbs: thumbs
          )
          |> reload_roll()
          |> propose(names)

        added = if names == [], do: "", else: " Added #{Enum.join(names, " and ")}."

        went_on =
          case spilled do
            {next, over} ->
              " Roll #{a.roll_num} is full at #{a.batch} strips, so " <>
                "#{count_line(length(over), "strip")} began roll #{next}: settle this load " <>
                "and that roll opens with it."

            nil ->
              ""
          end

        said = "Read off the glass: #{film_line(format, color)}.#{added}#{went_on}"

        case analysis do
          {:ok, _path} when names == [] ->
            {:noreply, finish_load(socket, said)}

          {:ok, _path} ->
            {:noreply,
             put_flash(
               socket,
               :info,
               "#{said} #{found_line(socket)}#{seen_before_line(socket, names)}"
             )}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "#{said} Analysis failed: #{reason}")}
        end

      {:develop, frame, {:ok, _print}} ->
        {:noreply,
         socket
         |> update(:ticked, &MapSet.delete(&1, frame))
         |> update(:run, &(&1 ++ [frame]))
         |> scanned()}

      {:finish, {:ok, published}} ->
        {:noreply,
         socket
         |> assign(
           published_roll: published,
           archive_rolls: Negatives.list_contact_sheets(),
           load_strips: [],
           bed_preview: nil
         )
         |> put_flash(:info, "Roll #{published} is on /negatives.")}

      {:finish, {:error, step, reason}} ->
        said = "Not published. #{step_line(step)}: #{reason}"
        {:noreply, socket |> assign(publish_error: said) |> put_flash(:error, said)}

      {:analysis, {:error, reason}, _thumbs} ->
        {:noreply, put_flash(socket, :error, "Analysis failed: #{reason}")}

      {:develop, frame, {:error, reason}} ->
        {:noreply,
         socket
         |> assign(queue: [], then_publish?: false)
         |> put_flash(:error, "Frame #{frame} was scanned but not developed: #{reason}")}
    end
  end

  def handle_async(:tool, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(working: nil, queue: [], then_publish?: false)
     |> reload_roll()
     |> put_flash(:error, "That step crashed: #{inspect(reason)}")}
  end

  # A band's singles are developed. Its roll may no longer be the one on the
  # bench: a batch moves on while the last of a roll is still developing.
  def handle_async({:develop, _id}, {:ok, {dir, results}}, socket) do
    done = MapSet.new(results, &elem(&1, 0))
    failed = for {frame, {:error, reason}} <- results, do: "frame #{frame}: #{inspect(reason)}"

    socket =
      update(socket, :developing, fn rolls ->
        left = MapSet.difference(Map.get(rolls, dir, MapSet.new()), done)
        if MapSet.size(left) == 0, do: Map.delete(rolls, dir), else: Map.put(rolls, dir, left)
      end)

    socket =
      if dir == socket.assigns.roll_dir,
        do: socket |> reload_roll() |> refresh_singles(),
        else: socket

    socket =
      if failed == [],
        do: socket,
        else: put_flash(socket, :error, "Not developed: #{Enum.join(failed, "; ")}")

    {:noreply, publish_closed(socket, dir)}
  end

  def handle_async({:develop, _id}, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(developing: %{})
     |> put_flash(:error, "Developing crashed: #{inspect(reason)}")}
  end

  # A closed roll has been through sheet, checks and catalog.
  def handle_async({:finish, dir}, {:ok, result}, socket) do
    {_, {roll_num, _, _, _}} = Map.get(socket.assigns.closing, dir, {nil, {"?", nil, nil, nil}})
    socket = update(socket, :closing, &Map.delete(&1, dir))

    case result do
      {:ok, published} ->
        {:noreply,
         socket
         |> assign(archive_rolls: Negatives.list_contact_sheets())
         |> put_flash(:info, "Roll #{published} is on /negatives.")}

      {:error, step, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Roll #{roll_num} was not published. #{step_line(step)}: #{reason} " <>
             "It is still on disk: set the roll number under Roll to go back to it."
         )}
    end
  end

  def handle_async({:finish, dir}, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> update(:closing, &Map.delete(&1, dir))
     |> put_flash(:error, "Publishing crashed: #{inspect(reason)}")}
  end

  def handle_async(:singles, {:ok, singles}, socket) do
    {:noreply, assign(socket, singles: singles)}
  end

  def handle_async(:singles, {:exit, _reason}, socket), do: {:noreply, socket}

  def handle_async(:thumbs, {:ok, thumbs}, socket) do
    {:noreply, assign(socket, frame_thumbs: thumbs)}
  end

  def handle_async(:thumbs, {:exit, _reason}, socket), do: {:noreply, socket}

  # --- Uploads ----------------------------------------------------------------

  defp handle_upload_progress(:strip_scans, entry, socket) do
    if entry.done? do
      dir = socket.assigns.roll_dir

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, Scanner.add_strip(dir, path, entry.client_name)}
        end)

      socket = socket |> assign(roll_initialized: File.dir?(dir)) |> reload_roll()

      case result do
        {:ok, _name} -> {:noreply, socket}
        {:error, reason} -> {:noreply, put_flash(socket, :error, reason)}
      end
    else
      {:noreply, socket}
    end
  end

  # --- Helpers ----------------------------------------------------------------

  defp valid(value, pattern, fallback) when is_binary(value) do
    if value =~ pattern, do: value, else: fallback
  end

  defp valid(_value, _pattern, fallback), do: fallback

  defp one_of(value, options, fallback) do
    if List.keymember?(options, value, 0), do: value, else: fallback
  end

  # A strip named by the browser, checked against the roll's own listing so a
  # crafted name can't reach outside the folder.
  defp strip_path(socket, file) do
    case Enum.find(socket.assigns.strips, &(&1.file == file)) do
      nil -> :error
      strip -> {:ok, strip.path}
    end
  end

  defp show_strip(socket, file) do
    case strip_path(socket, file) do
      {:ok, path} ->
        assign(socket,
          preview_strip: file,
          preview_data: thumbnail(path, "1200x1200>", :landscape)
        )

      :error ->
        socket
    end
  end

  # A scan of the run has come back good. More to do, or the load is done; a
  # run that was stopped stays where it is, with what is left still ticked.
  defp scanned(socket) do
    %{queue: queue, run: run, stopped?: stopped?} = socket.assigns

    cond do
      queue != [] ->
        socket
        |> refresh_singles()
        |> put_flash(:info, "Scanned #{frames_line(run)}. #{length(queue)} more to scan.")
        |> scan_next_keeper()

      stopped? ->
        socket
        |> assign(stopped?: false)
        |> refresh_singles()
        |> put_flash(:info, "Stopped after #{frames_line(run)}.")

      true ->
        finish_load(
          socket,
          if(listed?(socket.assigns),
            do:
              "Scanned #{frames_line(run)}. They are on roll #{socket.assigns.roll_num}'s page " <>
                "as soon as they are developed. Lay the next strips and press Add singles.",
            else: "Scanned #{frames_line(run)}. Load the next strips and press Preview."
          )
        )
    end
  end

  # On /negatives already: singles scanned now go onto a page that is public.
  defp listed?(assigns), do: Enum.any?(assigns.archive_rolls, &(&1.roll == assigns.roll_num))

  defp developing?(assigns), do: Map.has_key?(assigns.developing, assigns.roll_dir)

  defp step_line(:strips), do: "Strips"
  defp step_line(:analysis), do: "Finding the frames"
  defp step_line(:sheet), do: "The contact sheet"
  defp step_line(:gates), do: "The checks"

  # The collection: a small picture of every print the roll has, by frame.
  # A print already pictured is not made again unless its file has changed.
  defp refresh_singles(socket) do
    if connected?(socket) do
      %{roll_dir: dir, singles: known} = socket.assigns
      start_async(socket, :singles, fn -> singles(dir, known) end)
    else
      socket
    end
  end

  defp singles(roll_dir, known) do
    for frame <- Scanner.printed_frames(roll_dir), into: %{} do
      path = Path.join([roll_dir, "frames", String.pad_leading("#{frame}", 2, "0") <> ".png"])

      mtime =
        case File.stat(path) do
          {:ok, stat} -> stat.mtime
          _ -> nil
        end

      case known[frame] do
        %{mtime: ^mtime} = pictured -> {frame, pictured}
        _ -> {frame, %{mtime: mtime, data: thumbnail(path, "420x420>", 0)}}
      end
    end
  end

  # The frames of the load being chosen from.
  defp shown_frames(%{frames: frames, load_strips: strips}) do
    Enum.filter(frames, &(&1.strip in strips))
  end

  defp found_line(socket) do
    case shown_frames(socket.assigns) do
      [] ->
        ""

      frames ->
        "#{length(frames)} frames found, #{MapSet.size(socket.assigns.ticked)} ticked."
    end
  end

  # The same film looked at twice reads the same, frame for frame. Said, not
  # acted on: only the author knows whether it is.
  defp seen_before_line(socket, names) do
    by_strip =
      socket.assigns.frames
      |> Enum.group_by(& &1.strip, &(&1.quality && Float.round(&1.quality / 1, 2)))

    twin =
      Enum.find_value(names, fn name ->
        reading = by_strip[name]

        length(reading || []) >= 3 &&
          Enum.find(Map.keys(by_strip) -- names, &(by_strip[&1] == reading))
      end)

    if twin,
      do:
        " This reads the same as #{twin}, already on the roll: if it is the same film, press Discard this load.",
      else: ""
  end

  defp frames_line([frame]), do: "frame #{frame}"
  defp frames_line(frames), do: "frames #{Enum.join(frames, ", ")}"

  # Where the analysis leaves a small developed crop of each frame. Outside
  # the archive, since it is only this page's view of it, and the owner's alone.
  defp thumbs_dir(slug), do: Path.join(System.tmp_dir!(), "scanner_frames_#{slug}")

  # After a reload the crops of the last analysis are still there.
  defp load_thumbs(socket) do
    if connected?(socket) and socket.assigns.frames != [] do
      dir = thumbs_dir(socket.assigns.roll_slug)
      roll_dir = socket.assigns.roll_dir
      start_async(socket, :thumbs, fn -> frame_thumbs(dir, roll_dir) end)
    else
      socket
    end
  end

  # `%{frame number => data URI}` for the crops in `dir`.
  defp frame_thumbs(dir, roll_dir) do
    case File.ls(dir) do
      {:ok, files} ->
        for file <- files,
            [_, digits] <- [Regex.run(~r/\Aframe-(\d+)\.png\z/, file)],
            frame = String.to_integer(digits),
            data = thumbnail(Path.join(dir, file), "420x420>", Scanner.rotation(roll_dir, frame)),
            into: %{} do
          {frame, data}
        end

      _ ->
        %{}
    end
  end

  # A browser can't show a TIFF, so a strip is looked at through a small
  # WebP made on the spot.
  # `turn` is degrees clockwise, or `:landscape`: a quarter anticlockwise when
  # the picture is taller than it is wide (ImageMagick's `<`), else as it is.
  defp thumbnail(path, size, turn) do
    tmp = Path.join(System.tmp_dir!(), "scanner_thumb_#{System.unique_integer([:positive])}.webp")

    rotate =
      case turn do
        :landscape -> ["-rotate", "-90<"]
        0 -> []
        degrees -> ["-rotate", "#{degrees}"]
      end

    try do
      case System.cmd(
             Negatives.magick_bin(),
             [path <> "[0]"] ++ rotate ++ ["-resize", size, "-quality", "80", tmp],
             stderr_to_stdout: true
           ) do
        {_, 0} -> "data:image/webp;base64," <> Base.encode64(File.read!(tmp))
        _ -> nil
      end
    rescue
      _ -> nil
    after
      File.rm(tmp)
    end
  end

  # A picture already on the page, a quarter turn clockwise.
  defp turned("data:image/webp;base64," <> encoded = data) do
    source =
      Path.join(System.tmp_dir!(), "scanner_turn_#{System.unique_integer([:positive])}.webp")

    try do
      File.write!(source, Base.decode64!(encoded))
      thumbnail(source, "1200x1200>", 90) || data
    rescue
      _ -> data
    after
      File.rm(source)
    end
  end

  defp turned(other), do: other

  defp scanning?(assigns), do: assigns.job != nil
  defp can_scan?(assigns), do: assigns.scanner != nil or assigns.simulation?

  defp busy?(assigns), do: scanning?(assigns) or assigns.working != nil

  defp job_line(%{kind: kind}) when kind in [:pass, :find], do: "Looking at the holder"

  defp job_line(%{kind: :band, meta: %{band: %{frames: frames}}}),
    do: "Scanning #{frames_line(Enum.map(frames, &elem(&1, 0)))}"

  defp job_line(%{kind: :keeper, meta: %{frame: frame}}), do: "Scanning frame #{frame}"
  defp job_line(_job), do: "Scanning"

  defp quality_line(%{quality: quality}) when is_number(quality),
    do: "quality #{:erlang.float_to_binary(quality / 1, decimals: 2)}"

  defp quality_line(_frame), do: "not read"

  defp working_line(:finish), do: "Assembling the sheet, checking it, publishing…"

  defp area_line(format) do
    case Driver.area(format) do
      {l, t, x, y} -> "#{x} × #{y} mm at #{l}, #{t}"
      nil -> nil
    end
  end

  # --- Template ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, formats: @formats, colors: @colors)

    ~H"""
    <.page_head slug="Darkroom / Scanner" title="Scanner">
      <:actions>
        <.pill :if={@scanner} tone="live">{@scanner.name}</.pill>
        <.pill :if={is_nil(@devices)} tone="quiet">Looking for a scanner…</.pill>
        <.pill :if={@devices && !@scanner} tone="held">
          {if @simulation?, do: "No scanner — simulating", else: "No scanner connected"}
        </.pill>
        <button
          type="button"
          class="adm-btn adm-btn--quiet"
          phx-click="refresh_devices"
          disabled={is_nil(@devices)}
        >
          <.icon name="hero-arrow-path" class="size-4" /> Look again
        </button>
      </:actions>
    </.page_head>

    <.tabs label="Scanner views">
      <:tab patch={~p"/admin/scanner"} active={@tab == :studio}>Studio</:tab>
      <:tab
        patch={~p"/admin/scanner?tab=archive"}
        active={@tab == :archive}
        count={length(@archive_rolls)}
      >
        Archive
      </:tab>
      <:tab patch={~p"/admin/scanner?tab=setup"} active={@tab == :setup}>Setup</:tab>
    </.tabs>

    <.studio :if={@tab == :studio} {assigns} />
    <.archive :if={@tab == :archive} archive_rolls={@archive_rolls} />
    <.setup :if={@tab == :setup} devices={@devices} scanner={@scanner} simulation?={@simulation?} />
    """
  end

  defp studio(assigns) do
    stage = stage(assigns)
    shown = shown_frames(assigns)
    # Singles chosen and never made: a run cut short leaves them behind.
    owed = if stage in [:load, :select], do: Scanner.owed_singles(assigns.roll_dir), else: []

    assigns =
      assign(assigns,
        stage: stage,
        can_scan?: can_scan?(assigns),
        busy?: busy?(assigns),
        area: area_line(assigns.roll_format),
        shown_frames: shown,
        locked?: stage != :select,
        developing?: developing?(assigns),
        owed_here: for(o <- owed, o.on_glass?, do: o.frame),
        owed_away: Enum.reject(owed, & &1.on_glass?),
        developing_here:
          Map.get(assigns.developing, assigns.roll_dir, MapSet.new()) |> Enum.sort(),
        ticked_count: MapSet.size(assigns.ticked),
        listed?: listed?(assigns),
        on_glass: assigns.roll_dir |> Scanner.holder() |> Map.keys(),
        step: Enum.find_index([:load, :looking, :select, :scanning], &(&1 == stage))
      )

    ~H"""
    <div class="adm-scan-bench">
      <%!-- The roll, and the one thing to press now. --%>
      <div class="adm-scan-bar" id="hardware-scan">
        <div class="adm-scan-roll">
          <strong>Roll {@roll_num}</strong>
          <span :if={@roll_initialized}>
            {film_line(@roll_format, @roll_color)} · {@roll_date} · {count_line(
              length(@strips),
              "strip"
            )}{if @batch, do: " of #{@batch}"} · {count_line(length(@keeper_frames), "single")}{if @meta.shot,
              do: " · shot #{RollMeta.shot_line(@meta)}"}
          </span>
          <span :if={!@roll_initialized}>
            not begun: the first preview reads the film and names it
          </span>
        </div>

        <div class="adm-scan-bar-actions">
          <button
            type="button"
            class="adm-btn adm-btn--quiet"
            phx-click="drawer"
            phx-value-name="roll"
            aria-expanded={to_string(@drawer == :roll)}
            aria-controls="roll-config"
          >
            Roll
          </button>
          <button
            type="button"
            class="adm-btn adm-btn--quiet"
            phx-click="drawer"
            phx-value-name="strips"
            aria-expanded={to_string(@drawer == :strips)}
            aria-controls="strips"
          >
            Strips<span class="adm-count">{length(@strips)}</span>
          </button>
          <button
            :if={@stage != :published}
            type="button"
            class="adm-btn adm-btn--quiet"
            phx-click="publish"
            disabled={@strips == [] or @developing? or @stage in [:looking, :scanning, :publishing]}
            data-confirm={
              if @stage == :select and @ticked_count > 0,
                do:
                  "Scan the #{count_line(@ticked_count, "single")} ticked, then publish roll #{@roll_num} to /negatives? It becomes public.",
                else: "Publish roll #{@roll_num} to /negatives? It becomes public."
            }
          >
            <.icon name="hero-cloud-arrow-up" class="size-4" /> Publish roll
          </button>

          <button
            :if={@stage == :load}
            type="button"
            class="adm-btn adm-btn--primary adm-scan-go"
            phx-click="preview"
            disabled={@busy? or not @can_scan?}
          >
            <.icon name="hero-eye" class="size-4" /> Preview
          </button>
          <button
            :if={@stage == :load}
            type="button"
            class={["adm-btn", if(@listed?, do: "adm-btn--primary", else: "adm-btn--quiet")]}
            phx-click="add_singles"
            disabled={@busy? or not @can_scan?}
            title="Lay strips of any roll scanned before back in the holder. The page works out which roll they are."
          >
            <.icon name="hero-plus" class="size-4" />
            {if @listed?, do: "Add singles", else: "Add singles to an old roll"}
          </button>
          <button
            :if={@stage == :load and @listed?}
            type="button"
            class="adm-btn adm-btn--quiet"
            phx-click="back_to_bench"
            disabled={@busy?}
          >
            Back to new film
          </button>
          <button
            :if={@stage == :looking}
            type="button"
            class="adm-btn adm-btn--primary adm-scan-go"
            disabled
          >
            Looking…
          </button>
          <button
            :if={@stage == :select}
            type="button"
            class="adm-btn adm-btn--primary adm-scan-go"
            phx-click="scan_singles"
            disabled={@busy? or (@ticked_count > 0 and not @can_scan?)}
          >
            <.icon name="hero-film" class="size-4" />
            {if @ticked_count == 0,
              do: "No singles, next load",
              else: "Scan #{count_line(@ticked_count, "single")}"}
          </button>
          <button
            :if={@stage == :scanning}
            type="button"
            class="adm-btn adm-btn--primary adm-scan-go"
            disabled
          >
            Scanning…
          </button>
          <button
            :if={@stage == :publishing}
            type="button"
            class="adm-btn adm-btn--primary adm-scan-go"
            disabled
          >
            Publishing…
          </button>
          <button
            :if={@stage == :published}
            type="button"
            class="adm-btn adm-btn--primary adm-scan-go"
            phx-click="new_roll"
          >
            <.icon name="hero-plus" class="size-4" /> Start the next roll
          </button>
        </div>

        <%!-- Where the loop is, and what it wants. --%>
        <ol :if={@step} class="adm-scan-steps" aria-label="The loop for each load">
          <li class={@step in [0, 1] && "is-current"}>Preview</li>
          <li class={@step == 2 && "is-current"}>Select</li>
          <li class={@step == 3 && "is-current"}>Scan</li>
        </ol>
        <p class="adm-scan-now" role="status">
          {now_line(@stage, assigns)}
          <button
            :if={@stage == :scanning and @queue != []}
            type="button"
            class="adm-btn adm-btn--quiet adm-btn--small"
            phx-click="stop_queue"
          >
            Stop after this scan
          </button>
        </p>
        <progress :if={@job} class="adm-scan-progress" max="100" value={@job.percent}></progress>
        <p
          :for={{_dir, {_state, {roll_num, _, _, _}}} <- @closing}
          class="adm-scan-bar-note adm-help"
          role="status"
        >
          Roll {roll_num} is being finished and published in the background.
        </p>
      </div>

      <section
        :if={@roll_end}
        id="roll-end"
        class="adm-scan-end"
        role="group"
        aria-label="Where this roll ends"
      >
        <p class="adm-scan-end-ask">
          Roll {@roll_num} has {length(@strips)} strips; a sleeve holds {@batch}.
          <span :if={length(@roll_end.options) > 1}>Which strip begins roll {@roll_end.next}?</span>
          <span :if={length(@roll_end.options) == 1}>
            Roll {@roll_end.next} begins at {strip_label(@strips, hd(@roll_end.options))}.
          </span>
        </p>
        <div :if={length(@roll_end.options) > 1} class="adm-scan-end-options">
          <button
            :for={file <- @roll_end.options}
            type="button"
            class={["adm-scan-end-option", file == @roll_end.chosen && "is-chosen"]}
            phx-click="choose_roll_end"
            phx-value-file={file}
            aria-pressed={to_string(file == @roll_end.chosen)}
          >
            {strip_label(@strips, file)}
          </button>
        </div>
        <button type="button" class="adm-btn adm-btn--primary" phx-click="end_roll" id="end-roll">
          Start roll {@roll_end.next} with it
        </button>
      </section>

      <section :if={@waiting_rolls != []} id="waiting-rolls" class="adm-scan-waiting">
        <p :for={{roll_num, _date, format, color} <- @waiting_rolls} class="adm-scan-waiting-row">
          <span>Roll {roll_num} ({format}, {color}) is not published yet.</span>
          <button
            type="button"
            class="adm-btn adm-btn--small"
            phx-click="publish_waiting"
            phx-value-roll={roll_num}
          >
            Publish
          </button>
          <button
            type="button"
            class="adm-btn adm-btn--quiet adm-btn--small"
            phx-click="open_waiting"
            phx-value-roll={roll_num}
          >
            Open
          </button>
        </p>
      </section>

      <section id="roll-config" class="adm-scan-drawer" hidden={@drawer != :roll}>
        <form phx-change="update_roll_config" class="adm-form-row">
          <label class="adm-field">
            <span class="adm-label">Roll number</span>
            <input
              type="text"
              name="roll_num"
              value={@roll_num}
              class="adm-input"
              inputmode="numeric"
            />
          </label>
          <label class="adm-field">
            <span class="adm-label">Scan date</span>
            <input type="date" name="date" value={@roll_date} class="adm-input" />
          </label>
          <label class="adm-field">
            <span class="adm-label">Format</span>
            <select name="format" class="adm-input">
              <option :for={{value, label} <- @formats} value={value} selected={@roll_format == value}>
                {label}
              </option>
            </select>
          </label>
          <label class="adm-field">
            <span class="adm-label">Film</span>
            <select name="color" class="adm-input">
              <option :for={{value, label} <- @colors} value={value} selected={@roll_color == value}>
                {label}
              </option>
            </select>
          </label>
        </form>

        <div class="adm-form-actions">
          <code class="adm-scan-path">
            {Scanner.format_dir_name(@roll_format)}/{@roll_slug}
          </code>
          <.pill :if={@roll_initialized} tone="live">Folder exists</.pill>
          <button
            :if={@roll_initialized}
            type="button"
            class="adm-btn adm-btn--quiet"
            phx-click="new_roll"
            disabled={@busy?}
          >
            <.icon name="hero-plus" class="size-4" /> Start a new roll
          </button>
          <button
            :if={!@roll_initialized}
            type="button"
            class="adm-btn adm-btn--quiet"
            phx-click="initialize_roll"
          >
            <.icon name="hero-plus" class="size-4" /> Create the folder
          </button>
        </div>
        <p class="adm-help">
          The first preview reads format and film off the glass and names the roll. Set them
          here only to overrule it. 620 reads as 120, so set that one by hand first.
        </p>

        <form phx-change="update_batch" id="roll-batch" class="adm-scan-meta">
          <h2 class="adm-panel-title">Batch</h2>
          <label class="adm-field adm-scan-frame">
            <span class="adm-label">Strips per roll</span>
            <input
              type="text"
              name="strips"
              value={@batch}
              class="adm-input"
              inputmode="numeric"
              phx-debounce="600"
            />
          </label>
          <p class="adm-help">
            When a roll reaches this many strips, and its singles are scanned, it is published
            without asking and the next roll is put on the bench. Leave blank to finish rolls
            by hand with Publish roll.
          </p>
        </form>

        <form phx-change="update_roll_meta" id="roll-meta" class="adm-scan-meta">
          <h2 class="adm-panel-title">About this roll</h2>
          <div class="adm-form-row">
            <label class="adm-field">
              <span class="adm-label">Shot</span>
              <input
                type="text"
                name="shot"
                value={@meta.shot}
                class="adm-input"
                placeholder="2023, 2023-06 or 2023-06-14"
                phx-debounce="600"
              />
            </label>
            <label class="adm-field">
              <span class="adm-label">Camera</span>
              <input
                type="text"
                name="camera"
                value={@meta.camera}
                class="adm-input"
                phx-debounce="600"
              />
            </label>
            <label class="adm-field">
              <span class="adm-label">Film stock</span>
              <input type="text" name="film" value={@meta.film} class="adm-input" phx-debounce="600" />
            </label>
            <label class="adm-field">
              <span class="adm-label">Place</span>
              <input
                type="text"
                name="place"
                value={@meta.place}
                class="adm-input"
                phx-debounce="600"
              />
            </label>
          </div>
          <label class="adm-field">
            <span class="adm-label">Notes</span>
            <textarea name="notes" class="adm-input" rows="2" phx-debounce="600">{@meta.notes}</textarea>
          </label>
          <p :if={@meta_error} class="adm-scan-fault" role="alert">{@meta_error}</p>
          <p class="adm-help">
            Saved as you type, with the roll, and shown on its page on /negatives. Shot is as
            exact as you know it: a year, a month or a day. The roll is still filed by the day
            it was scanned.
          </p>
        </form>
      </section>

      <section id="strips" class="adm-scan-drawer" hidden={@drawer != :strips}>
        <.empty :if={@strips == []}>No strips yet.</.empty>

        <ol :if={@strips != []} class="adm-scan-strips">
          <li :for={strip <- @strips} class="adm-scan-strip">
            <div class="adm-scan-strip-name">
              <strong>{strip.file}</strong>
              <span>
                {strip.dimensions} · {div(strip.size, 1024)} KB{if strip.file in @on_glass,
                  do: " · on the glass"}
              </span>
            </div>
            <div class="adm-scan-strip-actions">
              <button
                type="button"
                class="adm-btn adm-btn--quiet adm-btn--small"
                phx-click="move_strip"
                phx-value-index={strip.index}
                phx-value-by="up"
                aria-label={"Move #{strip.file} earlier"}
                disabled={strip.index == 1 or @busy?}
              >
                ↑
              </button>
              <button
                type="button"
                class="adm-btn adm-btn--quiet adm-btn--small"
                phx-click="move_strip"
                phx-value-index={strip.index}
                phx-value-by="down"
                aria-label={"Move #{strip.file} later"}
                disabled={strip.index == length(@strips) or @busy?}
              >
                ↓
              </button>
              <button
                type="button"
                class="adm-btn adm-btn--quiet adm-btn--small"
                phx-click="rotate_strip"
                phx-value-file={strip.file}
                disabled={@busy?}
              >
                Turn 180°
              </button>
              <button
                type="button"
                class="adm-btn adm-btn--quiet adm-btn--small"
                phx-click="select_strip_preview"
                phx-value-file={strip.file}
              >
                Look
              </button>
              <button
                type="button"
                class="adm-btn adm-btn--quiet adm-btn--small"
                phx-click="pick_singles"
                phx-value-file={strip.file}
                disabled={@busy? or @queue != [] or not @analysed?}
              >
                Pick singles
              </button>
              <button
                :if={strip.index > 1}
                type="button"
                class="adm-btn adm-btn--quiet adm-btn--small"
                phx-click="split_roll"
                phx-value-file={strip.file}
                data-confirm={"Begin a new roll at #{strip.file}? It and every strip after it leave roll #{@roll_num}, with their singles."}
                disabled={@busy? or @queue != [] or @developing?}
              >
                New roll from here
              </button>
              <button
                type="button"
                class="adm-btn adm-btn--danger adm-btn--small"
                phx-click="delete_strip"
                phx-value-file={strip.file}
                data-confirm={"Delete #{strip.file} from the roll folder?"}
                disabled={@busy?}
              >
                Delete
              </button>
            </div>
          </li>
        </ol>

        <div :if={@preview_strip} class="adm-scan-look-wrap" id="strip-preview">
          <div class="adm-form-actions">
            <strong>{@preview_strip}</strong>
            <button
              type="button"
              class="adm-btn adm-btn--quiet adm-btn--small"
              phx-click="toggle_positive"
            >
              {if @positive?, do: "Show the negative", else: "Show it inverted"}
            </button>
            <button
              type="button"
              class="adm-btn adm-btn--quiet adm-btn--small"
              phx-click="turn_look"
              aria-label="Turn the picture of the strip a quarter clockwise"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Turn
            </button>
          </div>
          <div class="adm-scan-look">
            <img
              :if={@preview_data}
              src={@preview_data}
              alt={"Strip #{@preview_strip}"}
              class={@positive? && "is-inverted"}
            />
            <p :if={!@preview_data} class="adm-help">This scan couldn't be read for a preview.</p>
          </div>
        </div>

        <div class="adm-form-actions">
          <button
            type="button"
            class="adm-btn adm-btn--quiet"
            phx-click="run_analysis"
            disabled={@strips == [] or @busy?}
          >
            Analyse strips
          </button>
          <button
            type="button"
            class="adm-btn adm-btn--quiet"
            phx-click="find_on_glass"
            disabled={@strips == [] or @busy? or not @can_scan? or @queue != []}
          >
            <.icon name="hero-eye" class="size-4" /> Find this roll's strips on the glass
          </button>
          <span class="adm-help">
            To scan singles from a strip scanned earlier, lay it back in the holder (either slot,
            either way up) and press Find: the page matches it to its strip here and works out
            where it now lies.
          </span>
          <span :if={@scanner && !@area} class="adm-help">
            No holder rectangle is set for {@roll_format}: a strip is cut the whole length of the
            transparency area. See Setup.
          </span>
        </div>

        <.drop_zone
          upload={@uploads.strip_scans}
          title="Or drop strip scans here"
          hint="Each becomes the roll's next strip, kept exactly as it was scanned."
          error_message={fn error -> "Upload refused: #{inspect(error)}" end}
        />
      </section>

      <%!-- This load: what is on the glass now. --%>
      <section id="keeper-rescan" class="adm-scan-stage">
        <div :if={@shown_frames == []} class="adm-scan-blank">
          <p :if={@stage == :published}>
            Roll {@published_roll} is published.
            <.link href={~p"/negatives/roll/#{@published_roll}"} class="adm-link">
              See it on /negatives →
            </.link>
          </p>
          <p :if={@stage == :looking}>Looking at the holder…</p>
          <p :if={@stage == :publishing}>Publishing roll {@roll_num}…</p>
          <p :if={@stage == :load}>
            {if @strips == [],
              do: "Load the holder and press Preview.",
              else: "Load the next strips and press Preview."}
          </p>
          <p :if={@stage == :load} class="adm-help">
            Both slots of the 35mm holder can be filled. {if @strips != [],
              do: "When the roll is all in, press Publish roll."}
          </p>
          <button
            :if={@stage == :load and @on_glass != []}
            type="button"
            class="adm-btn adm-btn--quiet adm-btn--small"
            phx-click="reselect"
          >
            Pick more singles from the strips still in the holder
          </button>
          <p :if={!@can_scan? and @devices != nil and @stage == :load} class="adm-help">
            No scanner is connected. Strips scanned elsewhere can be dropped under Strips.
          </p>
        </div>

        <div :if={@shown_frames != []} class="adm-scan-stage-head">
          <h2 class="adm-panel-title">
            On the glass<span class="adm-count">{length(@shown_frames)}</span>
          </h2>
          <span class="adm-help">{Enum.join(@load_strips, ", ")}</span>
          <button
            :if={@stage == :select and Scanner.pending_load(@roll_dir) != []}
            type="button"
            class="adm-btn adm-btn--quiet adm-btn--small"
            phx-click="discard_load"
            data-confirm="Take this load's strips back out of the roll?"
          >
            Discard this load
          </button>
        </div>

        <p :if={@owed_here != [] and @stage == :select} class="adm-scan-fault" role="status">
          Chosen but not yet scanned: {frames_line(@owed_here)}. The scan was cut short. They
          are ticked again: press Scan to finish.
        </p>

        <p :if={Enum.any?(@shown_frames, & &1.mis_split?)} class="adm-help">
          A strip here holds a different number of frames from the rest of the roll, so it could
          not be cut into frames and nothing on it is proposed.
        </p>

        <div class={["adm-scan-load", @bed_preview && @shown_frames != [] && "has-glass"]}>
          <ul :if={@shown_frames != []} class="adm-scan-frames">
            <li :for={frame <- @shown_frames}>
              <label class={["adm-scan-pick", frame.printed? && "is-printed"]}>
                <span class="adm-scan-pick-picture">
                  <img
                    :if={@frame_thumbs[frame.frame]}
                    src={@frame_thumbs[frame.frame]}
                    alt={"Frame #{frame.frame}"}
                  />
                </span>
                <span class="adm-scan-pick-name">
                  <input
                    type="checkbox"
                    phx-click="toggle_frame"
                    phx-value-frame={frame.frame}
                    checked={MapSet.member?(@ticked, frame.frame)}
                    disabled={@locked?}
                  />
                  <strong>{frame.frame}</strong>
                  <span class="adm-scan-pick-note">
                    {quality_line(frame)}{if frame.printed?, do: " · scanned"}
                  </span>
                  <button
                    type="button"
                    class="adm-btn adm-btn--quiet adm-btn--small adm-scan-pick-turn"
                    phx-click="turn_frame"
                    phx-value-frame={frame.frame}
                    aria-label={"Turn frame #{frame.frame} a quarter clockwise"}
                    disabled={@locked?}
                  >
                    <.icon name="hero-arrow-path" class="size-4" />
                  </button>
                </span>
              </label>
            </li>
          </ul>

          <div :if={@bed_preview && @shown_frames != []} class="adm-scan-glass">
            <img src={@bed_preview} alt="The holder as previewed" class="adm-scan-bed" />
            <button
              type="button"
              class="adm-btn adm-btn--quiet adm-btn--small"
              phx-click="turn_glass"
              aria-label="Turn the picture of the holder a quarter clockwise"
            >
              <.icon name="hero-arrow-path" class="size-4" /> Turn
            </button>
          </div>
        </div>
      </section>

      <%!-- The roll so far: what will be on the site. --%>
      <section id="collection" class="adm-scan-collection">
        <div class="adm-scan-stage-head">
          <h2 class="adm-panel-title">
            Singles in roll {@roll_num}<span class="adm-count">{length(@keeper_frames)}</span>
          </h2>
          <span class="adm-help">
            Each gets a page of its own when the roll is published, with the contact sheet of {count_line(
              length(@strips),
              "strip"
            )}.
          </span>
        </div>

        <p :if={@developing_here != []} class="adm-help" role="status">
          Developing {frames_line(@developing_here)}. The scanner is free: carry on.
        </p>

        <.empty :if={@keeper_frames == [] and @developing_here == []}>
          No singles yet. The ones you scan appear here.
        </.empty>

        <p :if={@publish_error} class="adm-scan-fault" role="alert">{@publish_error}</p>

        <div :if={@owed_away != []} class="adm-scan-fault" role="status">
          <p>
            Chosen but never scanned: {frames_line(Enum.map(@owed_away, & &1.frame))}, on {@owed_away
            |> Enum.map(& &1.strip)
            |> Enum.uniq()
            |> Enum.join(", ")}. That film is no longer on the glass. Lay the strip back in the
            holder, either slot and either way up, and the page will find it.
          </p>
          <button
            type="button"
            class="adm-btn adm-btn--quiet adm-btn--small"
            phx-click="find_on_glass"
            disabled={@busy? or not @can_scan? or @queue != []}
          >
            <.icon name="hero-eye" class="size-4" /> It is back on the glass: find it
          </button>
        </div>

        <ul :if={@keeper_frames != []} class="adm-scan-singles">
          <li :for={frame <- @keeper_frames} class="adm-scan-single">
            <span class="adm-scan-pick-picture">
              <img :if={@singles[frame]} src={@singles[frame].data} alt={"Single, frame #{frame}"} />
            </span>
            <span class="adm-scan-single-caption">
              <strong>Frame {frame}</strong>
              <span class="adm-scan-single-tools">
                <button
                  type="button"
                  class="adm-scan-tool"
                  phx-click="turn_frame"
                  phx-value-frame={frame}
                  aria-label={"Turn single #{frame} a quarter clockwise"}
                  title="Turn"
                  disabled={@busy? or @queue != []}
                >
                  <.icon name="hero-arrow-path" class="size-4" />
                </button>
                <button
                  type="button"
                  class="adm-scan-tool adm-scan-tool--remove"
                  phx-click="remove_single"
                  phx-value-frame={frame}
                  aria-label={"Remove single #{frame}"}
                  title="Remove"
                  data-confirm={"Remove the single of frame #{frame}? The frame stays on its strip."}
                  disabled={@busy? or @queue != []}
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </span>
            </span>
          </li>
        </ul>
      </section>
    </div>
    """
  end

  defp count_line(1, word), do: "1 #{word}"
  defp count_line(count, word), do: "#{count} #{word}s"

  # The one line that says what the loop wants now.
  defp now_line(:load, %{strips: []}), do: "Load the holder, then press Preview."

  defp now_line(:load, %{listed?: true, roll_num: roll_num}),
    do:
      "Roll #{roll_num} is on /negatives. To add singles, lay its strips back in the holder " <>
        "(any roll's, either slot, either way up) and press Add singles."

  defp now_line(:load, _assigns),
    do: "Load the next strips, then press Preview. Publish when the roll is all in."

  defp now_line(:looking, %{job: %{percent: percent}}), do: "Looking at the holder — #{percent}%"
  defp now_line(:looking, _assigns), do: "Reading the film and finding the frames…"

  defp now_line(:select, %{ticked: ticked}) do
    if MapSet.size(ticked) == 0,
      do: "Tick the frames to keep as singles, or go on with none.",
      else:
        "Tick the singles, turn any that are the wrong way up, then scan. Preview again replaces this load."
  end

  defp now_line(:scanning, %{job: %{percent: percent} = job, queue: queue}) do
    more = if queue == [], do: "", else: ", #{length(queue)} more to scan"
    "#{job_line(job)} — #{percent}%#{more}. Leave the film where it is."
  end

  defp now_line(:scanning, _assigns), do: "Developing the singles. Leave the film where it is."
  defp now_line(:publishing, _assigns), do: working_line(:finish)
  defp now_line(:published, %{published_roll: roll}), do: "Roll #{roll} is on /negatives."

  # "strip 7", by where the file stands on the roll.
  defp strip_label(strips, file) do
    case Enum.find_index(strips, &(&1.file == file)) do
      nil -> file
      index -> "strip #{index + 1}"
    end
  end

  attr :archive_rolls, :list, required: true

  defp archive(assigns) do
    ~H"""
    <.panel title="Rolls on /negatives" count={length(@archive_rolls)} id="archive-table">
      <.rows id="rolls-list" rows={@archive_rolls} row_id={&"roll-row-#{&1.roll}"}>
        <:col :let={roll} label="Roll" class="adm-cell-title">{roll.roll}</:col>
        <:col :let={roll} label="Scanned">{roll.date}</:col>
        <:col :let={roll} label="Format">{roll.format}</:col>
        <:col :let={roll} label="Film">{roll.color}</:col>
        <:action :let={roll}>
          <button
            type="button"
            class="adm-btn adm-btn--quiet adm-btn--small"
            phx-click="load_archive_roll"
            phx-value-roll={roll.roll}
          >
            Open in the studio
          </button>
          <.link href={~p"/negatives/roll/#{roll.roll}"} class="adm-link">View</.link>
        </:action>
        <:empty>No rolls in the archive yet.</:empty>
      </.rows>
    </.panel>
    """
  end

  attr :devices, :any, required: true
  attr :scanner, :any, required: true
  attr :simulation?, :boolean, required: true

  defp setup(assigns) do
    ~H"""
    <.panel title="Scanner" id="setup-scanner">
      <ul class="adm-status">
        <li>
          <span class={["adm-status-dot", @scanner && "adm-status-dot--ok"]} aria-hidden="true">
          </span>
          <span class="adm-status-name">In use</span>
          <span class="adm-status-detail">
            {if @scanner, do: "#{@scanner.name} (#{@scanner.id})", else: "none"}
          </span>
        </li>
        <li :for={device <- @devices || []}>
          <span class="adm-status-dot" aria-hidden="true"></span>
          <span class="adm-status-name">{device.type}</span>
          <span class="adm-status-detail">{device.name} ({device.id})</span>
        </li>
        <li>
          <span class={["adm-status-dot", @simulation? && "adm-status-dot--warn"]} aria-hidden="true">
          </span>
          <span class="adm-status-name">Simulation</span>
          <span class="adm-status-detail">
            {if @simulation?,
              do: "On — with no scanner, scans are invented. Development only.",
              else: "Off — with no scanner, nothing is scanned."}
          </span>
        </li>
      </ul>
    </.panel>

    <.panel title="Holder rectangles" id="setup-areas">
      <p class="adm-help">
        Where one strip sits on the glass, in millimetres from the top-left of the transparency
        area. Set as <code>SCANNER_AREA_35MM</code>
        and <code>SCANNER_AREA_120</code>
        (<code>left,top,width,height</code>); 620 uses the 120 rectangle. Every scan is made through
        the transparency unit, unconverted; strips at {Driver.strip_dpi()} dpi, frames at {Driver.keeper_dpi()}.
      </p>
      <ul class="adm-status">
        <li :for={format <- ~w(35mm 120)}>
          <span
            class={[
              "adm-status-dot",
              if(area_line(format), do: "adm-status-dot--ok", else: "adm-status-dot--warn")
            ]}
            aria-hidden="true"
          >
          </span>
          <span class="adm-status-name">{format}</span>
          <span class="adm-status-detail">
            {area_line(format) || "not set — scans cover the whole transparency area"}
          </span>
        </li>
      </ul>
    </.panel>
    """
  end
end
