defmodule WebWeb.NegativesLive do
  use WebWeb, :live_view

  alias Web.Negatives
  alias Web.Negatives.Sheet
  alias WebWeb.NegativesLive.Format
  import WebWeb.Navigation, only: [return_context: 1]

  @impl true
  def mount(params, _session, socket) do
    sheets = Negatives.list_contact_sheets("all", "all")
    sheets = Enum.sort_by(sheets, & &1.date, :desc)

    {return_to, return_label} = return_context(params["from"])

    socket =
      socket
      |> assign(:page_title, "Analog Contact Sheets")
      |> assign(:sheets, sheets)
      |> assign(:from, params["from"])
      |> assign(:return_to, return_to)
      |> assign(:return_label, return_label)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # The URL is the whole of the view state: which roll, which mode, which
    # column. handle_params/3 is therefore the only place that sets it, and
    # every control on the page is a link that names a destination here. That
    # is what makes the browser's own Back button walk the archive.
    socket =
      socket
      |> assign(:sort_by, parse_sort(params["sort"]))
      |> assign(:sort_dir, parse_dir(params["dir"]))
      |> assign(:view_mode, if(params["mode"] == "index", do: :index, else: :single))

    case socket.assigns.live_action do
      :frame -> show_frame(socket, params)
      :sheet -> show_sheet(socket, params)
      _ -> show_archive(socket, params)
    end
  end

  # The archive's front door, which opens on the most recent roll. It keeps its
  # own address rather than redirecting to that roll's: what is newest changes,
  # and a link to "the archive" should keep meaning that.
  defp show_archive(socket, params) do
    case params["slug"] do
      nil ->
        {:noreply,
         socket
         |> assign(:sheet, List.first(socket.assigns.sheets))
         |> assign(:canonical_path, ~p"/negatives")
         |> assign_sheet()}

      slug ->
        # The old query-string form. Patched to the roll's real address rather
        # than served under it, so there is one URL per sheet; `replace` keeps
        # the redirect from becoming a step of its own in the reader's history.
        case Enum.find(socket.assigns.sheets, &(&1.slug == slug)) do
          nil -> {:noreply, push_patch(socket, to: archive_path(socket), replace: true)}
          sheet -> {:noreply, push_patch(socket, to: sheet_path(socket, sheet), replace: true)}
        end
    end
  end

  # One roll, addressable. Tokens arrive as 13, 013 or roll013 and all resolve;
  # the canonical assign settles on the padded spelling so a search engine is
  # not offered three URLs for one photograph set.
  defp show_sheet(socket, %{"roll" => roll}) do
    case find_sheet(socket.assigns.sheets, roll) do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/negatives")}

      sheet ->
        {:noreply,
         socket
         |> assign(:sheet, sheet)
         |> assign(:page_title, "Roll ##{sheet.roll} · contact sheet")
         |> assign(
           :meta_description,
           "Roll ##{sheet.roll} — #{sheet.format} #{sheet.color}, scanned #{sheet.date}."
         )
         |> assign(:og_image, sheet.preview_url)
         |> assign(:canonical_path, ~p"/negatives/roll/#{Format.pad(sheet.roll)}")
         |> assign_sheet()}
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
    sheet = find_sheet(socket.assigns.sheets, roll)

    if current && sheet do
      index = Enum.find_index(frames, &(&1.frame == number))

      {:noreply,
       socket
       |> assign(:sheet, sheet)
       |> assign_sheet()
       |> assign(
         view_mode: :frame,
         frame: current,
         # `if` without an else arm, so an absent neighbour is nil rather than
         # false — the template tests these for truthiness either way, but a
         # stray false in an assign is a trap for the next reader.
         prev_frame: if(index > 0, do: Enum.at(frames, index - 1)),
         next_frame: Enum.at(frames, index + 1),
         page_title: "Roll ##{sheet.roll} · frame #{number}",
         # Its own social card and canonical URL — otherwise every shared
         # photo link fell back to the site-wide default logo/description.
         og_image: current.url,
         og_description:
           "Roll ##{sheet.roll}, frame #{number} — #{sheet.format} #{sheet.color}, #{sheet.date}.",
         meta_description:
           "Roll ##{sheet.roll}, frame #{number} — #{sheet.format} #{sheet.color}, #{sheet.date}.",
         canonical_path: ~p"/negatives/roll/#{Format.pad(sheet.roll)}/frame/#{number}"
       )}
    else
      {:noreply, push_navigate(socket, to: ~p"/negatives")}
    end
  end

  defp find_sheet(sheets, roll) do
    Enum.find(sheets, &(roll_number(&1.roll) == roll_number(roll)))
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

  # Everything that depends on which sheet is on screen: the prints from its
  # roll, where those prints sit on the sheet, the sheet's own proportions, and
  # where it falls in the order being browsed.
  #
  # These move together on purpose. They used to not: prev/next assigned :sheet
  # on its own, and the strip below kept showing whichever roll was loaded at
  # mount.
  defp assign_sheet(socket) do
    sheet = socket.assigns[:sheet]
    frames = if sheet, do: Negatives.list_frames(sheet.roll), else: []

    # The arrows walk the same order the rail lists, so sorting the archive
    # re-sequences the walk rather than leaving the two disagreeing.
    ordered = sort_sheets(socket.assigns.sheets, socket.assigns.sort_by, socket.assigns.sort_dir)
    position = sheet && Enum.find_index(ordered, &(&1.slug == sheet.slug))

    socket
    |> assign(:ordered, ordered)
    |> assign(:frames, frames)
    |> assign(:marks, if(sheet, do: Sheet.marks(sheet, Enum.map(frames, & &1.frame)), else: []))
    |> assign(:sheet_ar, sheet && Sheet.aspect_ratio(sheet))
    |> assign(:position, position && position + 1)
    |> assign(:prev_sheet, if(position && position > 0, do: Enum.at(ordered, position - 1)))
    |> assign(:next_sheet, position && Enum.at(ordered, position + 1))
    |> assign(:frame, nil)
    |> assign(:prev_frame, nil)
    |> assign(:next_frame, nil)
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

  # --- Destinations -------------------------------------------------------
  #
  # Every control on the page is a link, so these are what the controls point
  # at. Each one carries the rest of the view state forward, which is why they
  # all go through the one helper: changing the sort must not lose the roll,
  # and stepping to the next roll must not drop the index you opened it from.

  defp view_opts(socket_or_assigns, overrides) do
    a = assigns_of(socket_or_assigns)

    [mode: a[:view_mode], sort: a[:sort_by], dir: a[:sort_dir], from: a[:from]]
    |> Keyword.merge(overrides)
  end

  defp assigns_of(%Phoenix.LiveView.Socket{assigns: assigns}), do: assigns
  defp assigns_of(assigns), do: assigns

  defp sheet_path(socket_or_assigns, sheet, overrides \\ []),
    do: Format.sheet_path(sheet.roll, view_opts(socket_or_assigns, overrides))

  defp archive_path(socket_or_assigns, overrides \\ []),
    do: Format.archive_path(view_opts(socket_or_assigns, overrides))

  # Clicking the sorted column flips its direction; a new column starts
  # descending. The destination keeps the roll you were on, which the old
  # hardcoded `/negatives?mode=index&...` dropped — sorting the index used to
  # lose your place, and from /archive it silently rewrote the path too.
  defp sort_path(assigns, column) do
    dir =
      cond do
        assigns[:sort_by] != column -> :desc
        assigns[:sort_dir] == :desc -> :asc
        true -> :desc
      end

    overrides = [mode: assigns[:view_mode], sort: column, dir: dir]

    # Sorting from a roll's own page keeps you on that roll; sorting from the
    # archive's front door sorts the archive. The sheet on screen there is
    # whatever happens to be newest, not a place the reader chose.
    case {assigns[:live_action], assigns[:sheet]} do
      {:sheet, sheet} when not is_nil(sheet) -> sheet_path(assigns, sheet, overrides)
      _ -> archive_path(assigns, overrides)
    end
  end

  @impl true
  def handle_event("key_prev", _, socket), do: {:noreply, step(socket, :prev)}
  def handle_event("key_next", _, socket), do: {:noreply, step(socket, :next)}

  def handle_event("key_escape", _, socket) do
    # Only the frame view has somewhere to escape to.
    if socket.assigns.view_mode == :frame and socket.assigns.sheet do
      {:noreply, push_patch(socket, to: sheet_path(socket, socket.assigns.sheet, mode: :single))}
    else
      {:noreply, socket}
    end
  end

  # The keyboard is the one control that cannot be a link, so it is the one
  # place left that pushes a patch of its own. It aims at the same destinations
  # the arrows do, including stopping at the ends rather than wrapping.
  defp step(socket, direction) do
    case {socket.assigns.view_mode, direction} do
      {:frame, :prev} -> frame_step(socket, socket.assigns.prev_frame)
      {:frame, :next} -> frame_step(socket, socket.assigns.next_frame)
      {_, :prev} -> sheet_step(socket, socket.assigns[:prev_sheet])
      {_, :next} -> sheet_step(socket, socket.assigns[:next_sheet])
    end
  end

  defp sheet_step(socket, nil), do: socket
  defp sheet_step(socket, sheet), do: push_patch(socket, to: sheet_path(socket, sheet))

  defp frame_step(socket, nil), do: socket

  defp frame_step(socket, frame) do
    push_patch(socket,
      to:
        Format.frame_path(
          socket.assigns.sheet.roll,
          frame.frame,
          view_opts(socket, mode: :single)
        )
    )
  end

  @doc """
  One grease pencil ring, placed over the frame it circles.

  The ring's geometry is generated per frame and never repeats — see
  `Web.Negatives.GreasePencil`. The stroke is deliberately drawn with
  `non-scaling-stroke`: one pencil marked this sheet, so a 35mm frame and a 6x6
  frame are circled by the same width of wax however differently sized they are
  on the paper.
  """
  attr :mark, :map, required: true
  attr :roll, :string, required: true
  attr :path, :string, required: true

  def grease_mark(assigns) do
    ~H"""
    <.link
      patch={@path}
      class="sheet-mark"
      style={"--x: #{@mark.left}%; --y: #{@mark.top}%; --w: #{@mark.width}%; --h: #{@mark.height}%"}
      aria-label={"View frame #{@mark.frame} of roll ##{@roll}"}
    >
      <svg class="sheet-mark-ring" viewBox={@mark.ring.viewbox} aria-hidden="true" focusable="false">
        <path
          :for={stroke <- @mark.ring.strokes}
          d={stroke.d}
          pathLength={@mark.ring.path_length}
          stroke-width={stroke.width}
          stroke-opacity={stroke.opacity}
          stroke-dasharray={stroke.dash}
        />
      </svg>
      <span class="sheet-mark-num">{@mark.frame}</span>
    </.link>
    """
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
      <%!-- Arrow keys walk the archive the way the arrows on the sheet do, and
            Escape leaves a photograph for the sheet it was cut from. One
            element per key: a bare phx-window-keydown would send the server
            every keystroke on the page. --%>
      <div class="sr-keys" aria-hidden="true">
        <span phx-window-keydown="key_prev" phx-key="ArrowLeft"></span>
        <span phx-window-keydown="key_next" phx-key="ArrowRight"></span>
        <span phx-window-keydown="key_escape" phx-key="Escape"></span>
      </div>

      <%!-- Stepping to the next roll costs a fresh ~300KB fetch, and nothing
            was warming it. Only the two neighbours: the whole archive is
            7.9MB, and these are cached for a day once asked for. --%>
      <link :if={@prev_sheet} rel="prefetch" as="image" href={@prev_sheet.preview_url} />
      <link :if={@next_sheet} rel="prefetch" as="image" href={@next_sheet.preview_url} />

      <%!-- The same treatment the homepage card advertises, arrived at:
            stretched, cropped, half-opacity orange. Geometry measured off
            Bebas Neue — see WebWeb.CoreComponents.baker_wordmark/1. --%>
      <WebWeb.CoreComponents.baker_wordmark
        class="darkroom-masthead"
        viewbox="0 31.52 1000 66.96"
        label="Contact Sheets"
        lines={[%{text: "Contact Sheets", x: "-5.95", y: "100", length: "1010.32"}]}
      />

      <%= if @view_mode == :index do %>
        <main class="index-viewport">
          <div class="index-header-row">
            <h2>Contact Sheets Index</h2>
            <.link
              :if={@sheet}
              patch={sheet_path(assigns, @sheet, mode: :single)}
              class="index-toggle-btn"
            >
              <.icon name="hero-photo" class="size-5" /> View Single Image
            </.link>
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
                      actually browsed along, so they sort; the rest label.
                      Links rather than click handlers, so a sorted index can be
                      opened in a new tab like anything else. --%>
                  <th class={["sortable-th", @sort_by == :date && "is-sorted"]}>
                    <.link patch={sort_path(assigns, :date)}>
                      Scan Date
                      <span :if={@sort_by == :date} class="sort-caret">
                        {if @sort_dir == :asc, do: "▲", else: "▼"}
                      </span>
                    </.link>
                  </th>
                  <th>Roll #</th>
                  <th>Image Name</th>
                  <th class={["sortable-th", @sort_by == :format && "is-sorted"]}>
                    <.link patch={sort_path(assigns, :format)}>
                      Format
                      <span :if={@sort_by == :format} class="sort-caret">
                        {if @sort_dir == :asc, do: "▲", else: "▼"}
                      </span>
                    </.link>
                  </th>
                  <th>Color</th>
                  <th>Frames</th>
                  <th class="actions-cell">Sheet</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={sheet <- @ordered} class="index-row">
                  <td class="index-date">{sheet.date}</td>
                  <%!-- The roll number is the row's link, stretched over the
                        whole row by negatives.css, so anywhere on the row opens
                        it — but it stays one focusable target, not seven. --%>
                  <td class="index-roll">
                    <.link patch={sheet_path(assigns, sheet, mode: :single)} class="index-row-link">
                      ROLL #{sheet.roll}
                    </.link>
                  </td>
                  <td class="index-file">{sheet.filename}</td>
                  <td><span class="format-pill">{sheet.format}</span></td>
                  <td><span class="color-pill">{String.upcase(sheet.color)}</span></td>
                  <td>{Sheet.frame_count(sheet) || "?"}</td>
                  <td class="actions-cell">
                    <a
                      href={sheet.image_url}
                      download={sheet.filename}
                      class="download-sheet-btn"
                      title="Download the full-resolution sheet"
                      aria-label={"Download roll ##{sheet.roll} at full resolution"}
                    >
                      <.icon name="hero-arrow-down-tray" class="size-4" />
                    </a>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </main>
      <% else %>
        <%!-- The archive's contents beside the sheet, whenever the screen can
              hold both. It folds away under 1200px, where the sheet needs every
              pixel and the full index takes over instead. --%>
        <div class="negatives-layout">
          <nav
            :if={@sheets != []}
            class="roll-rail"
            aria-label="Contact sheets"
            id="roll-rail"
            phx-hook=".RailScroll"
          >
            <p class="roll-rail-head">
              {length(@sheets)} rolls
              <.link
                patch={sort_path(assigns, if(@sort_by == :format, do: :date, else: :format))}
                class="roll-rail-sort"
              >
                by {if @sort_by == :format, do: "film type", else: "scan date"}
              </.link>
            </p>

            <ol class="roll-rail-list">
              <li :for={s <- @ordered}>
                <.link
                  patch={sheet_path(assigns, s, mode: :single)}
                  class={["roll-rail-item", @sheet && s.slug == @sheet.slug && "is-current"]}
                  aria-current={@sheet && s.slug == @sheet.slug && "true"}
                >
                  <span class="roll-rail-num">{s.roll}</span>
                  <span class="roll-rail-date">{s.date}</span>
                  <span class="roll-rail-format">{s.format}</span>
                </.link>
              </li>
            </ol>
          </nav>

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
                    patch={
                      Format.frame_path(
                        @sheet.roll,
                        @prev_frame.frame,
                        view_opts(assigns, mode: :single)
                      )
                    }
                    class="nav-pill-btn prev-btn"
                  >
                    <.icon name="hero-arrow-left" class="size-5" /> PREVIOUS
                  </.link>

                  <div class="flanked-title">
                    <span class="title-main">Frame {@frame.frame}</span>
                    <%!-- The provenance the URL exists to carry: wherever this
                          photograph is linked from, it names the roll it was cut
                          from and links back to that sheet. --%>
                    <.link
                      patch={sheet_path(assigns, @sheet, mode: :single)}
                      class="title-sub frame-origin"
                    >
                      From Roll #{@sheet.roll} • {@sheet.date} • {@sheet.format} Film
                    </.link>
                  </div>

                  <.link
                    :if={@next_frame}
                    patch={
                      Format.frame_path(
                        @sheet.roll,
                        @next_frame.frame,
                        view_opts(assigns, mode: :single)
                      )
                    }
                    class="nav-pill-btn next-btn"
                  >
                    NEXT <.icon name="hero-arrow-right" class="size-5" />
                  </.link>

                  <a
                    href={@frame.original_url}
                    download
                    class="download-icon-btn"
                    title="Download the full-resolution print"
                  >
                    <.icon name="hero-arrow-down-tray" class="size-5" />
                  </a>
                </div>

                <footer class="stage-footer">
                  <.link patch={sheet_path(assigns, @sheet, mode: :single)} class="index-toggle-btn">
                    <.icon name="hero-photo" class="size-5" /> Back to the contact sheet
                  </.link>
                </footer>
              </div>
            </main>
          <% else %>
            <main class="single-presentation-viewport">
              <%= if @sheet do %>
                <div class="presentation-stage">
                  <%!-- Metadata above, subtly: what the roll is, not what the
                      file is called. The filename lives in the index and in the
                      download attribute, where it is actually useful. The
                      position is here because a corridor wants its doors
                      numbered — stepping through 31 rolls without one is
                      walking with your eyes shut. --%>
                  <p class="sheet-meta">
                    Roll #{@sheet.roll} <span class="sheet-meta-dot">•</span> {@sheet.date}
                    <span class="sheet-meta-dot">•</span> {@sheet.format} Film
                    <span :if={@position} class="sheet-position">
                      {@position} of {length(@ordered)}
                    </span>
                  </p>

                  <%!-- A lightbox, not a page with a control bar: the arrows and the
                      download sit on the sheet itself, so nothing below it competes
                      with the photograph for the screen. The same controls collapse
                      into a bottom bar on phones (see negatives.css). --%>
                  <div class="stage-image-wrapper stage-image-wrapper--sheet">
                    <%!-- The plate is the photograph's own box: it carries the
                          sheet's exact proportions, which is the only way an
                          overlay can be positioned as a fraction of it and land
                          on the right frame. Without a measurement it falls back
                          to letting the image size itself, as it always did. --%>
                    <div
                      class={["sheet-plate", is_nil(@sheet_ar) && "sheet-plate--unmeasured"]}
                      style={@sheet_ar && "--sheet-ar: #{Float.round(@sheet_ar, 6)}"}
                    >
                      <img src={@sheet.preview_url} alt={@sheet.filename} class="stage-image" />

                      <%!-- Selects, marked the way selects are marked: a grease
                            pencil ring round the frames worth printing. Only
                            frames that have actually been printed are circled,
                            and circling one is how you ask to see it — so a roll
                            with nothing printed carries no marks at all. --%>
                      <nav
                        :if={@marks != []}
                        class="sheet-marks"
                        aria-label={"Photographs available from roll ##{@sheet.roll}"}
                      >
                        <.grease_mark
                          :for={mark <- @marks}
                          mark={mark}
                          roll={@sheet.roll}
                          path={
                            Format.frame_path(
                              @sheet.roll,
                              mark.frame,
                              view_opts(assigns, mode: :single)
                            )
                          }
                        />
                      </nav>
                    </div>

                    <%!-- The archive is a list, not a loop: at either end the
                          arrow stops being a control rather than carrying you
                          round to the other end, which would make "13 of 31"
                          a lie and Back ambiguous. --%>
                    <.link
                      :if={@prev_sheet}
                      patch={sheet_path(assigns, @prev_sheet)}
                      class="stage-arrow stage-arrow--prev prev-btn"
                      aria-label={"Previous sheet: roll ##{@prev_sheet.roll}"}
                    >
                      <.icon name="hero-chevron-left" class="size-10" />
                    </.link>
                    <span
                      :if={!@prev_sheet}
                      class="stage-arrow stage-arrow--prev is-spent"
                      aria-hidden="true"
                    >
                      <.icon name="hero-chevron-left" class="size-10" />
                    </span>

                    <.link
                      :if={@next_sheet}
                      patch={sheet_path(assigns, @next_sheet)}
                      class="stage-arrow stage-arrow--next next-btn"
                      aria-label={"Next sheet: roll ##{@next_sheet.roll}"}
                    >
                      <.icon name="hero-chevron-right" class="size-10" />
                    </.link>
                    <span
                      :if={!@next_sheet}
                      class="stage-arrow stage-arrow--next is-spent"
                      aria-hidden="true"
                    >
                      <.icon name="hero-chevron-right" class="size-10" />
                    </span>

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
                    <h2 class="frame-strip-title">Printed from this roll</h2>
                    <div class="frame-strip-rail">
                      <%!-- These used to point at the image bytes, which dead-ended
                            on a bare file instead of the frame's own page. They
                            are also the way in on a phone, where a ring on the
                            sheet is smaller than a thumb. --%>
                      <.link
                        :for={frame <- @frames}
                        patch={
                          Format.frame_path(
                            @sheet.roll,
                            frame.frame,
                            view_opts(assigns, mode: :single)
                          )
                        }
                        class="frame-thumb"
                        aria-label={"View frame #{frame.frame} of roll ##{@sheet.roll}"}
                      >
                        <img src={frame.url} alt={"Frame #{frame.frame}"} loading="lazy" />
                        <span class="frame-thumb-num">{frame.frame}</span>
                      </.link>
                    </div>
                  </section>

                  <%!-- Only reachable below 1200px, where the rail has folded
                        away and the full table is the only index there is. --%>
                  <footer class="stage-footer stage-footer--index">
                    <.link patch={sheet_path(assigns, @sheet, mode: :index)} class="index-toggle-btn">
                      <.icon name="hero-list-bullet" class="size-5" /> Full Index by Scan Date
                    </.link>
                  </footer>
                </div>
              <% else %>
                <div class="empty-state-minimal">
                  <.icon name="hero-photo" class="empty-state-icon" />
                  <p>No contact sheets found in archive.</p>
                </div>
              <% end %>
            </main>
          <% end %>
        </div>
      <% end %>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".RailScroll">
      // Keeps the roll you are looking at visible in the rail. The rail is its
      // own scroll container — 31 rolls is far taller than a screen — so after
      // a patch the current row is often above or below the fold even though
      // the page itself never scrolled.
      export default {
        mounted() { this.reveal(true) },
        updated() { this.reveal(false) },
        reveal(immediate) {
          const current = this.el.querySelector("[aria-current]")
          if (!current) return

          const rail = this.el.getBoundingClientRect()
          const item = current.getBoundingClientRect()
          if (item.top >= rail.top && item.bottom <= rail.bottom) return

          current.scrollIntoView({
            block: "nearest",
            behavior: immediate ? "auto" : "smooth"
          })
        }
      }
    </script>
    """
  end
end
