defmodule WebWeb.AdminLive.Scanner do
  @moduledoc """
  The scanner studio: a roll from film on the glass to a sheet on `/negatives`.

  The order of the page is the order of the work. Name the roll; lay a strip
  in the holder and scan it, once per strip; analyse the strips and assemble
  the sheet with the same tools the `negatives` command uses; publish once
  both gates pass. Then, for frames worth it, a high-resolution rescan.

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
  alias Web.Scanner
  alias Web.Scanner.{Bed, Driver, Simulation}

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
         preview_strip: nil,
         preview_data: nil,
         positive?: true,
         published_roll: nil,
         selected_frame: 1,
         archive_rolls: Negatives.list_contact_sheets()
       )
       |> open_roll(Scanner.next_roll_number(), today(), "120", "bw")
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
      preview_data: nil
    )
    |> reload_roll()
  end

  # What is on disk for the roll, read again after anything that changes it.
  defp reload_roll(socket) do
    %{roll_dir: dir, sheet_path: sheet} = socket.assigns

    assign(socket,
      strips: Scanner.list_strips(dir),
      analysed?: File.regular?(Path.join(dir, "frames.json")),
      conformance: File.regular?(sheet) && Scanner.verify_conformance(dir, sheet),
      keeper_frames: keeper_frames(dir)
    )
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

    {:ok, _dir} = Scanner.prepare_roll(roll_num, date, format, color)
    {:noreply, socket |> assign(roll_initialized: true) |> reload_roll()}
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

  def handle_event("scan_bed_preview", _params, socket) do
    target =
      Path.join(System.tmp_dir!(), "scanner_preview_#{System.unique_integer([:positive])}.png")

    {:noreply, start_scan(socket, %{kind: :preview, target: target})}
  end

  def handle_event("scan_next_strip", _params, socket) do
    %{roll_dir: dir} = socket.assigns
    target = Path.join(dir, Scanner.next_strip_name(dir))

    {:noreply, start_scan(socket, %{kind: :strip, target: target})}
  end

  def handle_event("select_rescan_frame", %{"frame" => frame}, socket) do
    case Integer.parse(frame) do
      {n, ""} when n in 1..99 -> {:noreply, assign(socket, :selected_frame, n)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("execute_frame_rescan", _params, socket) do
    %{roll_dir: dir, selected_frame: frame} = socket.assigns

    if Scanner.frame_region(dir, frame) do
      target = Scanner.keeper_raw_path(dir, frame)
      {:noreply, start_scan(socket, %{kind: :keeper, target: target, meta: %{frame: frame}})}
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         "The roll's analysis has no frame #{frame}. Analyse the roll first."
       )}
    end
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

    {:noreply, socket |> assign(preview_strip: nil, preview_data: nil) |> reload_roll()}
  end

  def handle_event("rotate_strip", %{"file" => file}, socket) do
    with {:ok, path} <- strip_path(socket, file),
         :ok <- Scanner.rotate_strip(path, 180) do
      {:noreply, socket |> reload_roll() |> show_strip(file)}
    else
      _ -> {:noreply, put_flash(socket, :error, "Couldn't rotate #{file}.")}
    end
  end

  def handle_event("delete_strip", %{"file" => file}, socket) do
    with {:ok, _path} <- strip_path(socket, file) do
      Scanner.delete_strip(socket.assigns.roll_dir, file)
    end

    {:noreply, socket |> assign(preview_strip: nil, preview_data: nil) |> reload_roll()}
  end

  def handle_event("select_strip_preview", %{"file" => file}, socket) do
    {:noreply, show_strip(socket, file)}
  end

  def handle_event("toggle_positive", _params, socket) do
    {:noreply, update(socket, :positive?, &(!&1))}
  end

  # --- Events: analysis, sheet, publishing --------------------------------------

  def handle_event("run_analysis", _params, socket) do
    %{roll_dir: dir, roll_format: format, roll_color: color} = socket.assigns

    {:noreply,
     socket
     |> assign(working: :analysis)
     |> start_async(:tool, fn ->
       {:analysis, Scanner.generate_frames_analysis(dir, format, color)}
     end)}
  end

  def handle_event("assemble_sheet", _params, socket) do
    %{roll_dir: dir, roll_num: roll_num, roll_date: date, roll_format: format, roll_color: color} =
      socket.assigns

    {:noreply,
     socket
     |> assign(working: :sheet)
     |> start_async(:tool, fn ->
       {:sheet, Scanner.assemble_contact_sheet(dir, roll_num, date, format, color)}
     end)}
  end

  def handle_event("publish_to_site", _params, socket) do
    %{roll_num: roll_num, roll_date: date, roll_format: format, roll_color: color} =
      socket.assigns

    case Scanner.publish_roll(roll_num, date, format, color) do
      {:ok, published} ->
        {:noreply,
         socket
         |> assign(published_roll: published, archive_rolls: Negatives.list_contact_sheets())
         |> put_flash(:info, "Roll #{published} is on /negatives.")}

      {:error, :not_conforming} ->
        {:noreply,
         socket
         |> reload_roll()
         |> put_flash(:error, "Not published: the roll doesn't pass both gates.")}
    end
  end

  # --- Scans ------------------------------------------------------------------

  defp start_scan(socket, job) do
    %{scanner: scanner, simulation?: simulation?} = socket.assigns

    cond do
      scanner ->
        case Bed.scan(job, scan_args(socket, scanner.id, job)) do
          :ok ->
            socket

          {:error, :busy} ->
            put_flash(socket, :error, "The scanner is already scanning.")

          {:error, reason} ->
            put_flash(socket, :error, "Couldn't start the scan: #{reason}")
        end

      simulation? ->
        case simulate(socket, job) do
          {:ok, _path} -> scan_done(socket, job)
          {:error, reason} -> put_flash(socket, :error, "Simulated scan failed: #{reason}")
        end

      true ->
        put_flash(socket, :error, "No scanner is connected.")
    end
  end

  defp scan_args(socket, device, %{kind: kind, target: target} = job) do
    %{roll_format: format, roll_color: color, roll_dir: dir} = socket.assigns
    output = Bed.partial(target)

    case kind do
      :preview ->
        Driver.preview_args(device, output)

      :strip ->
        Driver.strip_args(device, format, color, output)

      :keeper ->
        region = Scanner.frame_region(dir, job.meta.frame)
        Driver.keeper_args(device, format, color, region, output)
    end
  end

  defp simulate(socket, %{kind: kind, target: target} = job) do
    %{roll_format: format, roll_color: color, strips: strips} = socket.assigns

    case kind do
      :preview -> Simulation.preview(target, format, color)
      :strip -> Simulation.strip(target, length(strips) + 1, format, color)
      :keeper -> Simulation.keeper(target, job.meta.frame, color)
    end
  end

  defp scan_done(socket, %{kind: :preview, target: target}) do
    data = thumbnail(target)
    File.rm(target)
    assign(socket, bed_preview: data)
  end

  defp scan_done(socket, %{kind: :strip, target: target}) do
    socket |> reload_roll() |> show_strip(Path.basename(target))
  end

  defp scan_done(socket, %{kind: :keeper, meta: %{frame: frame}}) do
    dir = socket.assigns.roll_dir

    socket
    |> assign(working: :develop)
    |> start_async(:tool, fn -> {:develop, frame, Scanner.develop_keeper(dir, frame)} end)
  end

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
    {:noreply, socket |> assign(job: nil) |> scan_done(job)}
  end

  def handle_info({:scanner, :failed, _job, reason}, socket) do
    {:noreply, socket |> assign(job: nil) |> put_flash(:error, "Scan failed: #{reason}")}
  end

  # --- The slow tools ---------------------------------------------------------

  @impl true
  def handle_async(:tool, {:ok, result}, socket) do
    socket = socket |> assign(working: nil) |> reload_roll()

    case result do
      {:analysis, {:ok, _path}} ->
        {:noreply, put_flash(socket, :info, "Analysed: frames.json written.")}

      {:sheet, {:ok, _path}} ->
        {:noreply, put_flash(socket, :info, "Contact sheet assembled.")}

      {:develop, frame, {:ok, _print}} ->
        {:noreply, put_flash(socket, :info, "Frame #{frame} developed into frames/.")}

      {:analysis, {:error, reason}} ->
        {:noreply, put_flash(socket, :error, "Analysis failed: #{reason}")}

      {:sheet, {:error, reason}} ->
        {:noreply, put_flash(socket, :error, "Contact sheet failed: #{reason}")}

      {:develop, frame, {:error, reason}} ->
        {:noreply,
         put_flash(socket, :error, "Frame #{frame} was scanned but not developed: #{reason}")}
    end
  end

  def handle_async(:tool, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(working: nil)
     |> reload_roll()
     |> put_flash(:error, "That step crashed: #{inspect(reason)}")}
  end

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
      {:ok, path} -> assign(socket, preview_strip: file, preview_data: thumbnail(path))
      :error -> socket
    end
  end

  # The prints a roll has, by frame number.
  defp keeper_frames(roll_dir) do
    case File.ls(Path.join(roll_dir, "frames")) do
      {:ok, files} ->
        files
        |> Enum.flat_map(fn file ->
          case Regex.run(~r/\A(\d+)\.png\z/, file) do
            [_, digits] -> [String.to_integer(digits)]
            _ -> []
          end
        end)
        |> Enum.sort()

      _ ->
        []
    end
  end

  # A browser can't show a TIFF, so a strip is looked at through a small
  # WebP made on the spot.
  defp thumbnail(path) do
    tmp = Path.join(System.tmp_dir!(), "scanner_thumb_#{System.unique_integer([:positive])}.webp")

    try do
      case System.cmd(
             Negatives.magick_bin(),
             [path <> "[0]", "-resize", "1200x1200>", "-quality", "80", tmp],
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

  defp scanning?(assigns), do: assigns.job != nil
  defp can_scan?(assigns), do: assigns.scanner != nil or assigns.simulation?

  defp busy?(assigns), do: scanning?(assigns) or assigns.working != nil

  defp conforming?(%{conforming?: true}), do: true
  defp conforming?(_conformance), do: false

  defp gate(conformance, key) do
    case conformance && Map.get(conformance, key) do
      {:ok, _} -> {"live", "Pass", "is-pass"}
      nil -> {"held", "Pending", "is-pending"}
      false -> {"held", "Pending", "is-pending"}
      _ -> {"fail", "Fail", "is-fail"}
    end
  end

  defp job_line(%{kind: :preview}), do: "Scanning the bed preview"
  defp job_line(%{kind: :strip, target: target}), do: "Scanning #{Path.basename(target)}"
  defp job_line(%{kind: :keeper, meta: %{frame: frame}}), do: "Scanning frame #{frame}"
  defp job_line(_job), do: "Scanning"

  defp working_line(:analysis), do: "Analysing the strips…"
  defp working_line(:sheet), do: "Assembling the contact sheet…"
  defp working_line(:develop), do: "Developing the frame…"

  defp area_line(format) do
    case Driver.area(format) do
      {l, t, x, y} -> "#{x} × #{y} mm at #{l}, #{t}"
      nil -> nil
    end
  end

  defp slots(format), do: if(format == "35mm", do: 6, else: 4)

  # --- Template ---------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns = assign(assigns, formats: @formats, colors: @colors)

    ~H"""
    <.page_head slug="Darkroom / Scanner" title="Scanner">
      <:lede>
        One strip in the holder at a time: scan, assemble the sheet, publish the roll.
      </:lede>
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
    assigns =
      assign(assigns,
        scanning?: scanning?(assigns),
        can_scan?: can_scan?(assigns),
        busy?: busy?(assigns),
        gate_1: gate(assigns.conformance, :gate_1),
        gate_2: gate(assigns.conformance, :gate_2),
        area: area_line(assigns.roll_format)
      )

    ~H"""
    <div class="adm-scan-grid">
      <div>
        <.panel title="1. The roll" id="roll-config">
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
                <option
                  :for={{value, label} <- @formats}
                  value={value}
                  selected={@roll_format == value}
                >
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
              :if={!@roll_initialized}
              type="button"
              class="adm-btn adm-btn--primary"
              phx-click="initialize_roll"
            >
              <.icon name="hero-plus" class="size-4" /> Create the folder
            </button>
          </div>
        </.panel>

        <.panel title="2. Strips" id="hardware-scan" count={length(@strips)}>
          <div class="adm-form-actions adm-scan-actions">
            <button
              type="button"
              class="adm-btn adm-btn--quiet"
              phx-click="scan_bed_preview"
              disabled={@busy? or not @can_scan?}
            >
              <.icon name="hero-eye" class="size-4" /> Bed preview
            </button>
            <button
              type="button"
              class="adm-btn adm-btn--primary"
              phx-click="scan_next_strip"
              disabled={@busy? or not @can_scan? or not @roll_initialized}
            >
              <.icon name="hero-film" class="size-4" /> Scan strip {length(@strips) + 1}
            </button>
          </div>

          <p :if={!@can_scan? and @devices} class="adm-help">
            No scanner is connected, so nothing can be scanned. Strips scanned elsewhere can
            still be dropped below.
          </p>
          <p :if={@scanner && !@area} class="adm-help">
            No holder rectangle is set for {@roll_format}: a strip scan covers the whole
            transparency area. See Setup.
          </p>

          <div :if={@job} class="adm-scan-job" role="status">
            <span>{job_line(@job)} — {@job.percent}%</span>
            <progress max="100" value={@job.percent}></progress>
          </div>

          <img :if={@bed_preview} src={@bed_preview} alt="Bed preview" class="adm-scan-bed" />

          <.drop_zone
            upload={@uploads.strip_scans}
            title="Or drop strip scans here"
            hint="Each becomes the roll's next strip, kept exactly as it was scanned."
            error_message={fn error -> "Upload refused: #{inspect(error)}" end}
          />

          <.empty :if={@strips == []}>No strips yet.</.empty>

          <ol :if={@strips != []} class="adm-scan-strips">
            <li :for={strip <- @strips} class="adm-scan-strip">
              <div class="adm-scan-strip-name">
                <strong>{strip.file}</strong>
                <span>{strip.dimensions} · {div(strip.size, 1024)} KB</span>
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
        </.panel>

        <.panel :if={@preview_strip} title={"Looking at #{@preview_strip}"} id="strip-preview">
          <:actions>
            <button
              type="button"
              class="adm-btn adm-btn--quiet adm-btn--small"
              phx-click="toggle_positive"
            >
              {if @positive?, do: "Show the negative", else: "Show it inverted"}
            </button>
          </:actions>
          <div class="adm-scan-look">
            <img
              :if={@preview_data}
              src={@preview_data}
              alt={"Strip #{@preview_strip}"}
              class={@positive? && "is-inverted"}
            />
            <p :if={!@preview_data} class="adm-help">This scan couldn't be read for a preview.</p>
          </div>
          <p class="adm-help">
            A plain inversion, to check the strip is the right way round. The real
            development happens when the sheet is assembled.
          </p>
        </.panel>
      </div>

      <div>
        <.panel title="The sheet" id="virtual-canvas">
          <div class={[
            "adm-scan-sheet",
            if(@roll_format == "35mm", do: "is-rows", else: "is-columns")
          ]}>
            <div
              :for={slot <- 1..slots(@roll_format)}
              class={["adm-scan-slot", Enum.at(@strips, slot - 1) && "has-strip"]}
            >
              {if strip = Enum.at(@strips, slot - 1), do: strip.file, else: slot}
            </div>
          </div>
        </.panel>

        <.panel title="3. Assemble and publish" id="conformance-publish">
          <div class="adm-form-actions adm-scan-actions">
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
              phx-click="assemble_sheet"
              disabled={not @analysed? or @busy?}
            >
              Assemble sheet
            </button>
          </div>

          <p :if={@working} class="adm-scan-job" role="status">{working_line(@working)}</p>

          <div class="adm-scan-gates">
            <div class={["adm-scan-gate", elem(@gate_1, 2)]} id="gate-1">
              <div>
                <strong>Gate 1 — strips</strong>
                <.pill tone={elem(@gate_1, 0)}>{elem(@gate_1, 1)}</.pill>
              </div>
              <p>The strip files in the folder are the ones <code>frames.json</code> describes.</p>
            </div>
            <div class={["adm-scan-gate", elem(@gate_2, 2)]} id="gate-2">
              <div>
                <strong>Gate 2 — paper</strong>
                <.pill tone={elem(@gate_2, 0)}>{elem(@gate_2, 1)}</.pill>
              </div>
              <p>The sheet is exactly the size those strips compose to.</p>
            </div>
          </div>

          <div class="adm-form-actions">
            <button
              type="button"
              class="adm-btn adm-btn--primary"
              phx-click="publish_to_site"
              disabled={not conforming?(@conformance) or @busy?}
            >
              <.icon name="hero-cloud-arrow-up" class="size-4" /> Publish the roll
            </button>
            <.link
              :if={@published_roll}
              href={~p"/negatives/roll/#{@published_roll}"}
              class="adm-link"
            >
              Roll {@published_roll} on /negatives →
            </.link>
            <span :if={!@published_roll} class="adm-help">
              Adds the roll to catalog.csv. Both gates must pass.
            </span>
          </div>
        </.panel>

        <.panel title="4. Rescan a frame" id="keeper-rescan">
          <p class="adm-help">
            Put the frame's strip back in the holder as it was scanned. The frame is scanned at {Driver.keeper_dpi()} dpi
            and developed into <code>frames/</code>, which is what gives it a page of its own.
          </p>
          <form phx-change="select_rescan_frame" class="adm-form-actions">
            <label class="adm-field adm-scan-frame">
              <span class="adm-label">Frame</span>
              <input
                type="number"
                name="frame"
                min="1"
                max="99"
                value={@selected_frame}
                class="adm-input"
              />
            </label>
            <button
              type="button"
              class="adm-btn adm-btn--quiet"
              phx-click="execute_frame_rescan"
              disabled={not @analysed? or not @can_scan? or @busy?}
            >
              Rescan frame {@selected_frame}
            </button>
          </form>
          <p :if={@keeper_frames != []} class="adm-help">
            Printed: {Enum.join(@keeper_frames, ", ")}
          </p>
        </.panel>
      </div>
    </div>
    """
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
        the transparency unit as negative film; strips at {Driver.strip_dpi()} dpi, frames at {Driver.keeper_dpi()}.
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
