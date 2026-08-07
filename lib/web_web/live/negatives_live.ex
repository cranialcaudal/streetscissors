defmodule WebWeb.NegativesLive do
  use WebWeb, :live_view

  alias Web.Negatives
  import WebWeb.Navigation, only: [return_context: 1]

  @impl true
  def mount(params, _session, socket) do
    sheets = Negatives.list_contact_sheets("all", "all")
    sheets = Enum.sort_by(sheets, & &1.date, :desc)
    # Deterministic start (most recent roll): mount/3 runs for both the static
    # render and the connected socket, so a random pick loads two different
    # multi-MB images per visit and defeats browser caching.
    sheet = List.first(sheets)

    {return_to, return_label} = return_context(params["from"])

    socket =
      socket
      |> assign(:page_title, "Analog Contact Sheets")
      |> assign(:sheets, sheets)
      |> assign(:sheet, sheet)
      |> assign(:view_mode, :single)
      |> assign(:frame, nil)
      |> assign(:prev_frame, nil)
      |> assign(:next_frame, nil)
      |> assign(:sort_by, :date)
      |> assign(:sort_dir, :desc)
      |> assign(:return_to, return_to)
      |> assign(:return_label, return_label)
      |> assign_frames()

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    if socket.assigns.live_action == :frame do
      show_frame(socket, params)
    else
      sheets = socket.assigns.sheets
      mode = if params["mode"] == "index", do: :index, else: :single

      sheet =
        if slug = params["slug"] do
          Enum.find(sheets, &(&1.slug == slug)) || socket.assigns[:sheet] || List.first(sheets)
        else
          socket.assigns[:sheet] || List.first(sheets)
        end

      {:noreply,
       socket
       |> assign(view_mode: mode, sheet: sheet, frame: nil)
       |> assign(sort_by: parse_sort(params["sort"]), sort_dir: parse_dir(params["dir"]))
       |> assign_frames()}
    end
  end

  # A single frame, addressable on its own. The roll resolves to the sheet the
  # frame was cut from, which is the whole point of the URL: a photograph
  # published anywhere still carries its provenance. Anything that doesn't
  # resolve goes back to the archive rather than crashing — list_frames/1
  # already answers [] for rolls it cannot find.
  defp show_frame(socket, %{"roll" => roll, "frame" => frame}) do
    frames = Negatives.list_frames(roll)
    number = String.to_integer(frame_digits(frame) || "0")
    current = Enum.find(frames, &(&1.frame == number))
    sheet = Enum.find(socket.assigns.sheets, &(roll_number(&1.roll) == roll_number(roll)))

    if current && sheet do
      index = Enum.find_index(frames, &(&1.frame == number))

      {:noreply,
       assign(socket,
         view_mode: :frame,
         sheet: sheet,
         frames: frames,
         frame: current,
         prev_frame: index > 0 && Enum.at(frames, index - 1),
         next_frame: Enum.at(frames, index + 1),
         page_title: "Roll ##{sheet.roll} · frame #{number}"
       )}
    else
      {:noreply, push_navigate(socket, to: ~p"/negatives")}
    end
  end

  defp frame_digits(token) do
    case Regex.run(~r/\A0*(\d{1,4})\z/, to_string(token)) do
      [_, digits] -> digits
      _ -> nil
    end
  end

  defp roll_number(token) do
    case Regex.run(~r/\A(?:roll)?0*(\d{1,4})\z/i, to_string(token)) do
      [_, digits] -> String.to_integer(digits)
      _ -> -1
    end
  end

  defp parse_sort("format"), do: :format
  defp parse_sort(_), do: :date

  defp parse_dir("asc"), do: :asc
  defp parse_dir(_), do: :desc

  # Individual frames belonging to the sheet on screen. Loaded per sheet rather
  # than for the whole archive: this touches the filesystem, and only the sheet
  # being looked at needs it.
  defp assign_frames(socket) do
    frames =
      case socket.assigns[:sheet] do
        %{roll: roll} -> Negatives.list_frames(roll)
        _ -> []
      end

    assign(socket, :frames, frames)
  end

  @doc """
  Index rows ordered by the chosen column. Scan date is the natural order of
  the archive, so a format sort falls back to it within each film type.
  """
  def sort_sheets(sheets, :format, dir),
    do: Enum.sort_by(sheets, &{&1.format, &1.date}, sorter(dir))

  def sort_sheets(sheets, _date, dir), do: Enum.sort_by(sheets, & &1.date, sorter(dir))

  defp sorter(:asc), do: :asc
  defp sorter(:desc), do: :desc

  @impl true
  def handle_event("toggle_mode", _, socket) do
    new_mode = if socket.assigns.view_mode == :single, do: :index, else: :single
    {:noreply, assign(socket, :view_mode, new_mode)}
  end

  def handle_event("next", _, socket) do
    sheets = socket.assigns.sheets
    current = socket.assigns.sheet

    sheet =
      if sheets != [] and current != nil do
        idx = Enum.find_index(sheets, &(&1.slug == current.slug)) || 0
        next_idx = rem(idx + 1, length(sheets))
        Enum.at(sheets, next_idx)
      else
        if sheets != [], do: hd(sheets), else: nil
      end

    # assign_frames/1 must follow every sheet change, or the strip keeps
    # showing the frames of whichever roll was loaded at mount.
    {:noreply, socket |> assign(:sheet, sheet) |> assign_frames()}
  end

  def handle_event("prev", _, socket) do
    sheets = socket.assigns.sheets
    current = socket.assigns.sheet

    sheet =
      if sheets != [] and current != nil do
        idx = Enum.find_index(sheets, &(&1.slug == current.slug)) || 0
        prev_idx = if idx - 1 < 0, do: length(sheets) - 1, else: idx - 1
        Enum.at(sheets, prev_idx)
      else
        if sheets != [], do: hd(sheets), else: nil
      end

    # assign_frames/1 must follow every sheet change, or the strip keeps
    # showing the frames of whichever roll was loaded at mount.
    {:noreply, socket |> assign(:sheet, sheet) |> assign_frames()}
  end

  def handle_event("select_sheet", %{"slug" => slug}, socket) do
    sheets = socket.assigns.sheets
    sheet = Enum.find(sheets, &(&1.slug == slug)) || socket.assigns.sheet
    {:noreply, socket |> assign(sheet: sheet, view_mode: :single) |> assign_frames()}
  end

  # Clicking the active column flips direction; a new column starts descending.
  # Patched into the URL rather than held only in assigns, so a sorted index can
  # be linked to and survives a reload — handle_params/3 stays the single place
  # that sets the state.
  def handle_event("sort", %{"by" => by}, socket) do
    by = parse_sort(by)

    dir =
      cond do
        socket.assigns.sort_by != by -> :desc
        socket.assigns.sort_dir == :desc -> :asc
        true -> :desc
      end

    {:noreply, push_patch(socket, to: ~p"/negatives?mode=index&sort=#{by}&dir=#{dir}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- The frame view shares the sheet view's stage, so it takes the same
          sizing class — both are "one image, controls beneath". --%>
    <div class={[
      "minimal-viewer-container darkroom",
      @view_mode in [:single, :frame] && "single-mode-active"
    ]}>
      <%!-- The same treatment the homepage card advertises, arrived at:
            stretched, cropped, half-opacity orange. Geometry measured off
            Bebas Neue — see WebWeb.CoreComponents.baker_wordmark/1. --%>
      <WebWeb.CoreComponents.baker_wordmark
        class="darkroom-masthead"
        viewbox="0 31.52 1000 66.96"
        label="Contact Sheets"
        lines={[%{text: "Contact Sheets", x: "-5.95", y: "100", length: "1010.32"}]}
      />
      <%= if @view_mode == :frame do %>
        <main class="single-presentation-viewport">
          <div class="presentation-stage">
            <div class="stage-image-wrapper">
              <img
                src={@frame.url}
                alt={"Roll ##{@sheet.roll}, frame #{@frame.frame}"}
                class="stage-image"
              />
            </div>

            <div class="header-flanked-controls">
              <.link
                :if={@prev_frame}
                patch={~p"/negatives/roll/#{@sheet.roll}/frame/#{@prev_frame.frame}"}
                class="nav-pill-btn prev-btn"
              >
                <.icon name="hero-arrow-left" class="size-5 inline mr-1" /> PREVIOUS
              </.link>

              <div class="flanked-title">
                <span class="title-main">Frame {@frame.frame}</span>
                <%!-- The provenance the URL exists to carry: wherever this
                      photograph is linked from, it names the roll it was cut
                      from and links back to that sheet. --%>
                <.link navigate={~p"/negatives?slug=#{@sheet.slug}"} class="title-sub frame-origin">
                  From Roll #{@sheet.roll} • {@sheet.date} • {@sheet.format} Film
                </.link>
              </div>

              <.link
                :if={@next_frame}
                patch={~p"/negatives/roll/#{@sheet.roll}/frame/#{@next_frame.frame}"}
                class="nav-pill-btn next-btn"
              >
                NEXT <.icon name="hero-arrow-right" class="size-5 inline ml-1" />
              </.link>

              <a href={@frame.url} download class="download-icon-btn" title="Download frame">
                <.icon name="hero-arrow-down-tray" class="size-5 inline" />
              </a>
            </div>

            <footer class="stage-footer">
              <.link navigate={~p"/negatives?slug=#{@sheet.slug}"} class="index-toggle-btn">
                <.icon name="hero-photo" class="size-5 inline mr-1" /> Back to the contact sheet
              </.link>
            </footer>
          </div>
        </main>
      <% else %>
        <%= if @view_mode == :single do %>
          <main class="single-presentation-viewport">
            <%= if @sheet do %>
              <div class="presentation-stage">
                <%!-- Metadata above, subtly: what the roll is, not what the
                    file is called. The filename lives in the index and in the
                    download attribute, where it is actually useful. --%>
                <p class="sheet-meta">
                  Roll #{@sheet.roll} <span class="sheet-meta-dot">•</span> {@sheet.date}
                  <span class="sheet-meta-dot">•</span> {@sheet.format} Film
                </p>

                <%!-- A lightbox, not a page with a control bar: the arrows and the
                    download sit on the sheet itself, so nothing below it competes
                    with the photograph for the screen. The same buttons collapse
                    into a bottom bar on phones (see negatives.css). --%>
                <div class="stage-image-wrapper">
                  <img src={@sheet.preview_url} alt={@sheet.filename} class="stage-image" />

                  <button
                    phx-click="prev"
                    class="stage-arrow stage-arrow--prev prev-btn"
                    aria-label="Previous sheet"
                  >
                    <.icon name="hero-chevron-left" class="size-10" />
                  </button>

                  <button
                    phx-click="next"
                    class="stage-arrow stage-arrow--next next-btn"
                    aria-label="Next sheet"
                  >
                    <.icon name="hero-chevron-right" class="size-10" />
                  </button>

                  <a
                    href={@sheet.image_url}
                    download={@sheet.filename}
                    class="stage-download"
                    title="Download high-res PNG"
                    aria-label="Download high-res PNG"
                  >
                    <.icon name="hero-arrow-down-tray" class="size-5" />
                  </a>
                </div>

                <%!-- Frames from this roll. The page is built to split here: the
                    sheet above, the individual photographs it was cut from
                    below, each one reached through the sheet it came from.
                    Renders only once frames are actually published. --%>
                <section :if={@frames != []} class="frame-strip">
                  <h2 class="frame-strip-title">Frames from this roll</h2>
                  <div class="frame-strip-rail">
                    <a
                      :for={frame <- @frames}
                      href={frame.url}
                      class="frame-thumb"
                      title={"Roll ##{@sheet.roll} · frame #{frame.frame}"}
                    >
                      <img src={frame.url} alt={"Frame #{frame.frame}"} loading="lazy" />
                      <span class="frame-thumb-num">{frame.frame}</span>
                    </a>
                  </div>
                </section>

                <footer class="stage-footer">
                  <button phx-click="toggle_mode" class="index-toggle-btn">
                    <.icon name="hero-list-bullet" class="size-5 inline mr-1" />
                    Full Index by Scan Date
                  </button>
                </footer>
              </div>
            <% else %>
              <div class="empty-state-minimal">
                <.icon name="hero-photo" class="size-16 opacity-30 mx-auto mb-3" />
                <p>No contact sheets found in archive.</p>
              </div>
            <% end %>
          </main>
        <% else %>
          <main class="index-viewport">
            <div class="index-header-row">
              <h2>Contact Sheets Index</h2>
              <button phx-click="toggle_mode" class="index-toggle-btn">
                <.icon name="hero-photo" class="size-5 inline mr-1" /> View Single Image
              </button>
              <span class="index-count">
                {length(@sheets)} rolls by {if @sort_by == :format, do: "film type", else: "scan date"}, {if @sort_dir ==
                                                                                                               :asc,
                                                                                                             do:
                                                                                                               "oldest first",
                                                                                                             else:
                                                                                                               "newest first"}
              </span>
            </div>

            <div class="index-table-container">
              <table class="minimal-index-table">
                <thead>
                  <tr>
                    <%!-- Scan date and film type are the two axes the archive is
                        actually browsed along, so they sort; the rest label. --%>
                    <th
                      phx-click="sort"
                      phx-value-by="date"
                      class={["sortable-th", @sort_by == :date && "is-sorted"]}
                    >
                      Scan Date
                      <span :if={@sort_by == :date} class="sort-caret">
                        {if @sort_dir == :asc, do: "▲", else: "▼"}
                      </span>
                    </th>
                    <th>Roll #</th>
                    <th>Image Name</th>
                    <th
                      phx-click="sort"
                      phx-value-by="format"
                      class={["sortable-th", @sort_by == :format && "is-sorted"]}
                    >
                      Format
                      <span :if={@sort_by == :format} class="sort-caret">
                        {if @sort_dir == :asc, do: "▲", else: "▼"}
                      </span>
                    </th>
                    <th>Color</th>
                    <th>Frames</th>
                    <th class="text-right">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={sheet <- sort_sheets(@sheets, @sort_by, @sort_dir)} class="index-row">
                    <td class="font-mono text-orange-400">{sheet.date}</td>
                    <td class="font-bold">ROLL #{sheet.roll}</td>
                    <td class="font-mono">{sheet.filename}</td>
                    <td><span class="format-pill">{sheet.format}</span></td>
                    <td><span class="color-pill">{String.upcase(sheet.color)}</span></td>
                    <td>{sheet.frames}</td>
                    <td class="text-right actions-cell">
                      <button
                        phx-click="select_sheet"
                        phx-value-slug={sheet.slug}
                        class="view-sheet-btn"
                      >
                        <.icon name="hero-eye" class="size-4 inline mr-1" /> View
                      </button>
                      <a
                        href={sheet.image_url}
                        download={sheet.filename}
                        class="download-sheet-btn"
                        title="Download"
                      >
                        <.icon name="hero-arrow-down-tray" class="size-4 inline" />
                      </a>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </main>
        <% end %>
      <% end %>
    </div>
    """
  end
end
