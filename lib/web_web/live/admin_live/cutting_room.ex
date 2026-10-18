defmodule WebWeb.AdminLive.CuttingRoom do
  @moduledoc """
  One cut on the bench (`/admin/cuts/:id`): the bin on the left (takes and
  sounds, uploaded or recorded here, and prints from the archive), the program
  in the middle, the inspector on the right, and the timeline under them, in
  the manner of Premiere.

  **The server holds the edit; the browser plays it.** Every change is an
  event that `Web.Cuts.Timeline` makes and `Web.Cuts.save_timeline/2` holds to
  its ranges before it is kept, so what is on screen is always a timeline
  that renders. The `.Cutting` hook only plays and handles the hand: it plays
  the program from the bin's proxies (two `<video>`s taking turns, so the next
  take is ready before the cut reaches it), moves the camera over a print and
  shows the titles as the render will, and turns drags and trims on the
  timeline into events. The program it plays is `data-program`, which the
  server rewrites after every change.

  What the program shows is close to the render, not the render: a print's
  move is a CSS transform, a title is set in the browser's copy of the same
  face, and ducking is a lowered volume. The render is ffmpeg's
  (`Web.Cuts.Render`).

  Keys: space plays and stops, S cuts the clip under the playhead in two,
  Delete takes the selected item out, ← → step a frame (with shift, a
  second), Home and End go to either end.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Audio.Log
  alias Web.Cuts
  alias Web.Cuts.Timeline
  alias Web.Negatives

  # Only extensions MIME knows: LiveView refuses any other in `accept`.
  @accept ~w(.mp4 .mov .webm .m4a .mp3 .wav .aac .ogg)

  def mount(%{"id" => id}, session, socket) do
    with true <- !!session["admin_user"] || :not_admin,
         {id, ""} <- Integer.parse(id),
         %{} = cut <- Cuts.get_cut(id) do
      if connected?(socket), do: Cuts.subscribe(cut.id)

      {:ok,
       socket
       |> assign(
         page_title: "#{cut.name} | Cutting room",
         selected: nil,
         pps: 40,
         progress: nil,
         rolls: rolls(),
         roll: nil,
         prints: []
       )
       |> put_cut(cut)
       |> allow_upload(:media,
         accept: @accept,
         max_entries: 8,
         max_file_size: 8_000_000_000,
         auto_upload: true,
         progress: &handle_progress/3
       )}
    else
      :not_admin ->
        {:ok, push_navigate(socket, to: "/")}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "There is no such cut.")
         |> push_navigate(to: ~p"/admin/cuts")}
    end
  end

  defp rolls do
    for sheet <- Enum.sort_by(Negatives.list_contact_sheets(), & &1.roll_num, :desc),
        do: sheet.roll
  end

  defp put_cut(socket, cut) do
    assign(socket, cut: cut, plan: Timeline.layout(cut.timeline), media: Cuts.media_by_id(cut))
  end

  defp save(socket, timeline) do
    case Cuts.save_timeline(socket.assigns.cut, timeline) do
      {:ok, cut} ->
        selected = socket.assigns.selected
        socket = put_cut(socket, cut)

        if selected && !Timeline.find(cut.timeline, selected),
          do: assign(socket, selected: nil),
          else: socket

      {:error, _} ->
        put_flash(socket, :error, "That change could not be kept.")
    end
  end

  defp reload(socket), do: put_cut(socket, Cuts.get_cut(socket.assigns.cut.id))

  # ── The bin ───────────────────────────────────────────────────────────

  def handle_event("upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media, ref)}
  end

  def handle_event("add_take", %{"id" => id}, socket) do
    case socket.assigns.media[String.to_integer(id)] do
      %{status: "ready", kind: "video"} = take ->
        {:noreply, save(socket, Timeline.add_take(socket.assigns.cut.timeline, take))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("add_sound", %{"id" => id} = params, socket) do
    case socket.assigns.media[String.to_integer(id)] do
      %{status: "ready"} = file ->
        at = ms(params["at"])
        {:noreply, save(socket, Timeline.add_sound(socket.assigns.cut.timeline, file, at))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("remove_media", %{"id" => id}, socket) do
    with %{} = media <- socket.assigns.media[String.to_integer(id)],
         {:ok, cut} <- Cuts.remove_media(socket.assigns.cut, media) do
      {:noreply, socket |> put_cut(cut) |> assign(selected: nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("pick_roll", %{"roll" => ""}, socket),
    do: {:noreply, assign(socket, roll: nil, prints: [])}

  def handle_event("pick_roll", %{"roll" => roll}, socket) do
    {:noreply, assign(socket, roll: roll, prints: Negatives.list_frames(roll))}
  end

  def handle_event("add_still", %{"frame" => frame}, socket) do
    {:noreply, save(socket, Timeline.add_still(socket.assigns.cut.timeline, frame))}
  end

  # ── The timeline ──────────────────────────────────────────────────────

  def handle_event("add_title", params, socket) do
    timeline = Timeline.add_title(socket.assigns.cut.timeline, ms(params["at"]))
    socket = save(socket, timeline)
    {:noreply, assign(socket, selected: List.last(socket.assigns.cut.timeline["titles"])["id"])}
  end

  def handle_event("select", %{"id" => id}, socket) do
    {:noreply,
     assign(socket, selected: if(Timeline.find(socket.assigns.cut.timeline, id), do: id))}
  end

  def handle_event("deselect", _params, socket), do: {:noreply, assign(socket, selected: nil)}

  def handle_event("move", %{"id" => id, "index" => index}, socket) do
    {:noreply, save(socket, Timeline.move(socket.assigns.cut.timeline, id, int(index)))}
  end

  def handle_event("place", %{"id" => id, "at" => at}, socket) do
    {:noreply,
     save(socket, Timeline.update(socket.assigns.cut.timeline, id, %{"at" => max(int(at), 0)}))}
  end

  def handle_event("trim", %{"id" => id, "edge" => edge, "delta" => delta}, socket) do
    timeline = socket.assigns.cut.timeline

    case Timeline.find(timeline, id) do
      nil ->
        {:noreply, socket}

      item ->
        {:noreply, save(socket, Timeline.update(timeline, id, trimmed(item, edge, int(delta))))}
    end
  end

  def handle_event("split", %{"at" => at}, socket) do
    {:noreply, save(socket, Timeline.split(socket.assigns.cut.timeline, int(at)))}
  end

  def handle_event("delete", params, socket) do
    case params["id"] || socket.assigns.selected do
      nil ->
        {:noreply, socket}

      id ->
        {:noreply,
         socket |> save(Timeline.remove(socket.assigns.cut.timeline, id)) |> assign(selected: nil)}
    end
  end

  def handle_event("zoom", %{"pps" => pps}, socket) do
    {:noreply, assign(socket, pps: int(pps) |> max(5) |> min(200))}
  end

  # ── The inspector ─────────────────────────────────────────────────────

  def handle_event("inspect", params, %{assigns: %{selected: id}} = socket) when is_binary(id) do
    attrs =
      for {key, kind} <- [
            {"in", :seconds},
            {"out", :seconds},
            {"duration", :seconds},
            {"at", :seconds},
            {"fade_in", :seconds},
            {"fade_out", :seconds},
            {"gain", :number},
            {"move", :text},
            {"text", :text},
            {"style", :text}
          ],
          Map.has_key?(params, key),
          into: %{} do
        {key, field(params[key], kind)}
      end

    attrs =
      if Map.has_key?(params, "duck_shown"),
        do: Map.put(attrs, "duck", params["duck"] == "true"),
        else: attrs

    {:noreply, save(socket, Timeline.update(socket.assigns.cut.timeline, id, attrs))}
  end

  def handle_event("inspect", _params, socket), do: {:noreply, socket}

  def handle_event("rename", %{"name" => name}, socket) do
    case Cuts.rename(socket.assigns.cut, name) do
      {:ok, cut} ->
        {:noreply, socket |> put_cut(cut) |> assign(page_title: "#{cut.name} | Cutting room")}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  def handle_event("publish", params, socket) do
    case Cuts.publish(socket.assigns.cut, Map.take(params, ["recorded_on", "caption"])) do
      {:ok, _cut} -> {:noreply, socket |> assign(progress: 0) |> reload()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Not rendered: #{reason}.")}
    end
  end

  def handle_event("delete_cut", _params, socket) do
    {:ok, _} = Cuts.delete_cut(socket.assigns.cut)

    {:noreply,
     socket
     |> put_flash(:info, "The cut and its bin are gone.")
     |> push_navigate(to: ~p"/admin/cuts")}
  end

  # ── Uploads and the cut's own news ────────────────────────────────────

  defp handle_progress(:media, entry, socket) do
    if entry.done? do
      cut = socket.assigns.cut

      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, Cuts.add_media(cut, path, entry.client_name)}
      end)

      {:noreply, reload(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:cut_media, _media}, socket), do: {:noreply, reload(socket)}

  def handle_info({:cut_render, percent}, socket),
    do: {:noreply, assign(socket, progress: percent)}

  def handle_info({:cut_rendered, cut}, socket) do
    {:noreply,
     socket
     |> put_cut(cut)
     |> assign(progress: nil)
     |> put_flash(
       :info,
       "Rendered into the log of #{Log.title(cut.audio_log)}, which is transcoding now. Publish it from Captain's Logs."
     )}
  end

  def handle_info({:cut_failed, cut}, socket) do
    {:noreply,
     socket
     |> put_cut(cut)
     |> assign(progress: nil)
     |> put_flash(:error, "The render failed. What ffmpeg said is under Render.")}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # ── Helpers ───────────────────────────────────────────────────────────

  defp trimmed(%{"id" => "c-" <> _, "kind" => "take"} = clip, "left", d),
    do: %{"in" => clip["in"] + d}

  defp trimmed(%{"id" => "c-" <> _, "kind" => "take"} = clip, _right, d),
    do: %{"out" => clip["out"] + d}

  defp trimmed(%{"id" => "c-" <> _} = clip, "left", d), do: %{"duration" => clip["duration"] - d}
  defp trimmed(%{"id" => "c-" <> _} = clip, _right, d), do: %{"duration" => clip["duration"] + d}

  defp trimmed(%{"id" => "t-" <> _} = t, "left", d),
    do: %{"at" => t["at"] + d, "duration" => t["duration"] - d}

  defp trimmed(%{"id" => "t-" <> _} = t, _right, d), do: %{"duration" => t["duration"] + d}

  defp trimmed(%{"id" => "s-" <> _} = s, "left", d),
    do: %{"at" => s["at"] + d, "in" => s["in"] + d}

  defp trimmed(%{"id" => "s-" <> _} = s, _right, d), do: %{"out" => s["out"] + d}

  defp field(value, :seconds), do: round(number(value) * 1000)
  defp field(value, :number), do: number(value)
  defp field(value, :text), do: to_string(value)

  defp number(value) when is_number(value), do: value * 1.0

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp number(_), do: 0.0

  defp int(value), do: round(number(value))
  defp ms(nil), do: 0
  defp ms(value), do: max(int(value), 0)

  defp secs(ms), do: :erlang.float_to_binary(ms / 1000, decimals: 2)
  defp clock(ms), do: WebWeb.AdminLive.Cuts.clock(ms)

  defp proxy_url(cut, %{proxy: proxy}), do: ~p"/admin/cuts/#{cut.id}/media/#{proxy}"

  defp print_url(frame) do
    [roll, n] = String.split(frame, "/")
    Negatives.sized_url("/negatives/frame/#{roll}/#{n}", 960)
  end

  defp label(%{"kind" => "take", "media" => id}, media), do: media[id] && media[id].name

  defp label(%{"kind" => "still", "frame" => frame}, _media),
    do: "Roll " <> String.replace(frame, "/", " · ")

  defp label(%{"text" => text}, _media), do: text
  defp label(%{"media" => id}, media), do: media[id] && media[id].name

  # What the hook plays: every clip, title and sound, where it falls and where
  # its picture or sound comes from.
  defp program(%{cut: cut, plan: layout, media: media}) do
    %{
      length: layout.length,
      clips:
        for clip <- layout.clips do
          base = %{
            id: clip["id"],
            kind: clip["kind"],
            start: clip["start"],
            length: clip["length"]
          }

          case clip do
            %{"kind" => "take", "media" => id} ->
              Map.merge(base, %{
                url: proxy_url(cut, media[id]),
                in: clip["in"],
                gain: clip["gain"],
                sound: media[id].has_audio
              })

            %{"kind" => "still", "frame" => frame} ->
              Map.merge(base, %{url: print_url(frame), move: clip["move"]})
          end
        end,
      titles:
        Enum.map(
          layout.titles,
          &%{
            id: &1["id"],
            text: &1["text"],
            style: &1["style"],
            at: &1["at"],
            length: &1["length"]
          }
        ),
      sounds:
        for sound <- layout.sounds do
          %{
            id: sound["id"],
            url: proxy_url(cut, media[sound["media"]]),
            at: sound["at"],
            in: sound["in"],
            length: sound["length"],
            gain: sound["gain"],
            fade_in: sound["fade_in"],
            fade_out: sound["fade_out"],
            duck: sound["duck"]
          }
        end
    }
    |> Jason.encode!()
  end

  # Titles or sounds that overlap in time each get a row of their own on the
  # track (the first row free when each begins), or the later would hide the
  # earlier. `{lane by id, rows}`.
  defp lanes(items) do
    {by_id, ends} =
      items
      |> Enum.sort_by(& &1["at"])
      |> Enum.reduce({%{}, []}, fn item, {by_id, ends} ->
        free = Enum.find_index(ends, &(&1 <= item["at"]))
        lane = free || length(ends)
        finish = item["at"] + item["length"]
        ends = if free, do: List.replace_at(ends, free, finish), else: ends ++ [finish]
        {Map.put(by_id, item["id"], lane), ends}
      end)

    {by_id, max(length(ends), 1)}
  end

  # Ruler marks: a label every so many seconds that they stay apart.
  defp marks(length, pps) do
    step = Enum.find([1, 2, 5, 10, 15, 30, 60, 120], 300, &(&1 * pps >= 70))
    last = div(max(length, 1000), 1000) + step
    for s <- 0..last//step, do: {s, clock(s * 1000)}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        program: program(assigns),
        item: assigns.selected && Timeline.find(assigns.cut.timeline, assigns.selected),
        marks: marks(assigns.plan.length, assigns.pps),
        title_lanes: lanes(assigns.plan.titles),
        sound_lanes: lanes(assigns.plan.sounds),
        uploads_busy: Enum.any?(assigns.uploads.media.entries, &(!&1.done?))
      )

    ~H"""
    <.page_head slug="Write / Cutting room" title={@cut.name}>
      <:lede>
        {clock(@plan.length)} · {length(@plan.clips)} clips
        <span :if={@cut.audio_log}>· rendered into the log of {Log.title(@cut.audio_log)}</span>
      </:lede>
      <:actions>
        <.link navigate={~p"/admin/cuts"} class="adm-btn adm-btn--quiet">All cuts</.link>
        <.link :if={@cut.audio_log} navigate={~p"/admin/logs"} class="adm-btn adm-btn--quiet">
          Captain's Logs
        </.link>
        <button
          type="submit"
          form="publish-form"
          class="adm-btn adm-btn--primary"
          disabled={@cut.status == "rendering" or @plan.clips == []}
        >
          {cond do
            @cut.status == "rendering" -> "Rendering #{@progress || 0}%"
            @cut.audio_log -> "Render again"
            true -> "Render and publish"
          end}
        </button>
      </:actions>
    </.page_head>

    <div class="adm-cut-bench">
      <aside class="adm-cut-bin" aria-label="Bin">
        <form id="upload-form" phx-change="upload" phx-submit="upload" class="adm-cut-section">
          <h2 class="adm-cut-heading">Bin</h2>
          <label class="adm-cut-drop" phx-drop-target={@uploads.media.ref}>
            <.live_file_input upload={@uploads.media} class="adm-cut-file" />
            <span>Drop takes and music here, or choose files</span>
          </label>
          <div :for={entry <- @uploads.media.entries} class="adm-cut-uploading">
            <span>{entry.client_name}</span>
            <progress value={entry.progress} max="100">{entry.progress}%</progress>
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              class="adm-dr-reset"
            >
              Cancel
            </button>
            <span :for={err <- upload_errors(@uploads.media, entry)} class="adm-dr-error">
              {error_text(err)}
            </span>
          </div>
        </form>

        <div id="recorder" class="adm-cut-section" phx-hook=".Recorder" phx-update="ignore">
          <video class="adm-cut-camera" muted playsinline hidden></video>
          <button type="button" class="adm-btn adm-btn--small" data-role="record">
            <.icon name="hero-microphone" class="size-4" /> Record a take
          </button>
        </div>

        <ul class="adm-cut-media">
          <li
            :for={file <- @cut.media}
            id={"media-#{file.id}"}
            class={["adm-cut-file-row", "is-#{file.status}"]}
          >
            <span class="adm-cut-file-name">{file.name}</span>
            <span class="adm-cut-file-meta">
              <span :if={file.status == "processing"}>reading…</span>
              <span :if={file.status == "failed"} class="adm-dr-error" title={file.error}>
                could not be read
              </span>
              <span :if={file.status == "ready"}>
                {if file.kind == "video", do: "take", else: "sound"} · {clock(file.duration_ms)}
              </span>
            </span>
            <span class="adm-cut-file-actions">
              <button
                :if={file.status == "ready" and file.kind == "video"}
                type="button"
                phx-click="add_take"
                phx-value-id={file.id}
                class="adm-dr-reset"
              >
                Add to picture
              </button>
              <button
                :if={file.status == "ready" and (file.kind == "audio" or file.has_audio)}
                type="button"
                data-add-sound={file.id}
                class="adm-dr-reset"
              >
                Add as sound
              </button>
              <button
                type="button"
                phx-click="remove_media"
                phx-value-id={file.id}
                class="adm-dr-reset"
                data-confirm="Take this file out of the bin, and off the timeline?"
              >
                Remove
              </button>
            </span>
          </li>
        </ul>

        <div class="adm-cut-section">
          <h2 class="adm-cut-heading">Prints</h2>
          <form id="roll-picker" phx-change="pick_roll">
            <select name="roll" class="adm-input">
              <option value="">Choose a roll</option>
              <option :for={roll <- @rolls} value={roll} selected={roll == @roll}>Roll {roll}</option>
            </select>
          </form>
          <ul :if={@prints != []} class="adm-cut-prints">
            <li :for={print <- @prints}>
              <button
                type="button"
                phx-click="add_still"
                phx-value-frame={"#{@roll}/#{print.frame}"}
                class="adm-cut-print"
                title={"Add frame #{print.frame}"}
              >
                <img
                  src={Negatives.sized_url(print.url, 480)}
                  alt={"Frame #{print.frame}"}
                  loading="lazy"
                />
              </button>
            </li>
          </ul>
        </div>
      </aside>

      <section
        id="cutting"
        class="adm-cut-main"
        phx-hook=".Cutting"
        data-program={@program}
        data-selected={@selected}
      >
        <div id="screen" class="adm-cut-screen" phx-update="ignore">
          <video data-role="a" playsinline preload="auto"></video>
          <video data-role="b" playsinline preload="auto"></video>
          <div data-role="still" class="adm-cut-still"><img alt="" /></div>
          <div data-role="titles"></div>
        </div>
        <div class="adm-cut-transport">
          <button type="button" class="adm-btn adm-btn--small" data-role="play" aria-label="Play">
            <.icon name="hero-play" class="size-4" />
          </button>
          <span id="timecode" class="adm-cut-timecode" phx-update="ignore">0:00.0</span>
          <span class="adm-cut-length">/ {clock(@plan.length)}</span>
          <button type="button" class="adm-btn adm-btn--small adm-btn--quiet" data-role="split">
            Split (S)
          </button>
          <button type="button" class="adm-btn adm-btn--small adm-btn--quiet" data-role="title">
            Add a title
          </button>
          <form id="zoom" phx-change="zoom" class="adm-cut-zoom">
            <label>Zoom <input type="range" name="pps" min="5" max="200" value={@pps} /></label>
          </form>
        </div>

        <div
          class="adm-cut-timeline"
          style={"--pps: #{@pps}; --length: #{@plan.length / 1000}"}
          data-role="timeline"
        >
          <div class="adm-cut-ruler" data-role="ruler">
            <span :for={{s, text} <- @marks} class="adm-cut-mark" style={"--at: #{s}"}>{text}</span>
          </div>
          <div
            class="adm-cut-track adm-cut-track--titles"
            data-track="titles"
            style={"--lanes: #{elem(@title_lanes, 1)}"}
          >
            <span class="adm-cut-track-name">Titles</span>
            <div
              :for={title <- @plan.titles}
              class={["adm-cut-block adm-cut-block--title", @selected == title["id"] && "is-selected"]}
              data-id={title["id"]}
              data-at={title["at"]}
              data-length={title["length"]}
              style={"--at: #{title["at"] / 1000}; --len: #{title["length"] / 1000}; --lane: #{elem(@title_lanes, 0)[title["id"]]}"}
            >
              <span class="adm-cut-handle" data-edge="left"></span>
              <span class="adm-cut-block-label">{title["text"]}</span>
              <span class="adm-cut-handle" data-edge="right"></span>
            </div>
          </div>
          <div class="adm-cut-track adm-cut-track--picture" data-track="clips">
            <span class="adm-cut-track-name">Picture</span>
            <div
              :for={clip <- @plan.clips}
              class={[
                "adm-cut-block",
                "adm-cut-block--#{clip["kind"]}",
                @selected == clip["id"] && "is-selected"
              ]}
              data-id={clip["id"]}
              data-at={clip["start"]}
              data-length={clip["length"]}
              style={"--at: #{clip["start"] / 1000}; --len: #{clip["length"] / 1000}"}
            >
              <span class="adm-cut-handle" data-edge="left"></span>
              <span class="adm-cut-block-label">{label(clip, @media)}</span>
              <span class="adm-cut-handle" data-edge="right"></span>
            </div>
          </div>
          <div
            class="adm-cut-track adm-cut-track--sound"
            data-track="sounds"
            style={"--lanes: #{elem(@sound_lanes, 1)}"}
          >
            <span class="adm-cut-track-name">Sound</span>
            <div
              :for={sound <- @plan.sounds}
              class={["adm-cut-block adm-cut-block--sound", @selected == sound["id"] && "is-selected"]}
              data-id={sound["id"]}
              data-at={sound["at"]}
              data-length={sound["length"]}
              style={"--at: #{sound["at"] / 1000}; --len: #{sound["length"] / 1000}; --lane: #{elem(@sound_lanes, 0)[sound["id"]]}"}
            >
              <span class="adm-cut-handle" data-edge="left"></span>
              <span class="adm-cut-block-label">{label(sound, @media)}</span>
              <span class="adm-cut-handle" data-edge="right"></span>
            </div>
          </div>
          <div id="playhead" class="adm-cut-playhead" phx-update="ignore"></div>
        </div>
      </section>

      <aside class="adm-cut-inspector" aria-label="Inspector">
        <form :if={@item} id="inspector" phx-change="inspect" class="adm-cut-section">
          <div class="adm-dr-section-head">
            <h2 class="adm-cut-heading">{kind_name(@item)}</h2>
            <button type="button" phx-click="delete" class="adm-dr-reset">Remove</button>
          </div>
          <.inspect_fields item={@item} media={@media} />
        </form>

        <div class="adm-cut-section">
          <h2 class="adm-cut-heading">The cut</h2>
          <form id="rename" phx-change="rename" phx-debounce="400">
            <label class="adm-label" for="cut-name">Working name</label>
            <input
              id="cut-name"
              type="text"
              name="name"
              value={@cut.name}
              class="adm-input"
              maxlength="120"
            />
          </form>
          <form id="publish-form" phx-submit="publish" class="adm-cut-publish">
            <div :if={!@cut.audio_log}>
              <label class="adm-label" for="recorded-on">Recorded on</label>
              <input
                id="recorded-on"
                type="date"
                name="recorded_on"
                value={Date.to_iso8601(Web.Clock.local_today())}
                class="adm-input"
              />
              <label class="adm-label" for="caption">Caption</label>
              <input id="caption" type="text" name="caption" class="adm-input" maxlength="200" />
            </div>
            <p :if={@cut.audio_log} class="adm-dr-hint">
              Rendering again gives the log of {Log.title(@cut.audio_log)} the new film. It is off the site while it transcodes.
            </p>
          </form>
          <p :if={@cut.status == "rendering"} class="adm-dr-hint">
            <progress value={@progress || 0} max="100"></progress> Rendering…
          </p>
          <details :if={@cut.status == "failed" and @cut.render_error} class="adm-cut-error" open>
            <summary>What ffmpeg said</summary>
            <pre>{@cut.render_error}</pre>
          </details>
          <p class="adm-dr-hint">
            Select anything on the timeline to change it. Space plays, S splits at the playhead, Delete takes the selected item out.
          </p>
          <button
            type="button"
            phx-click="delete_cut"
            class="adm-btn adm-btn--small adm-btn--danger"
            data-confirm="Delete this cut and every file in its bin? A log it was rendered into stays."
          >
            Delete the cut
          </button>
        </div>
      </aside>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Recorder">
      // A take from the camera, sent into the bin by the same upload the drop
      // zone uses. The booth's recorder makes a log of one take; this only adds
      // a take to the bin.
      export default {
        mounted() {
          this.video = this.el.querySelector("video")
          this.button = this.el.querySelector("[data-role=record]")
          this.button.addEventListener("click", () => (this.recorder ? this.stop() : this.start()))
        },
        async start() {
          try {
            this.stream = await navigator.mediaDevices.getUserMedia({video: true, audio: true})
          } catch (e) {
            this.button.textContent = "No camera: " + e.message
            return
          }
          this.video.srcObject = this.stream
          this.video.hidden = false
          this.video.play()
          this.chunks = []
          this.recorder = new MediaRecorder(this.stream)
          this.recorder.ondataavailable = (e) => e.data.size && this.chunks.push(e.data)
          this.recorder.onstop = () => {
            const type = this.recorder.mimeType || "video/webm"
            const ext = type.includes("mp4") ? "mp4" : "webm"
            const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-")
            const file = new File(this.chunks, `take-${stamp}.${ext}`, {type})
            this.stream.getTracks().forEach((t) => t.stop())
            this.video.hidden = true
            this.recorder = null
            this.button.textContent = "Record a take"
            this.upload("media", [file])
          }
          this.recorder.start(1000)
          this.button.textContent = "Stop and keep the take"
        },
        stop() { this.recorder && this.recorder.stop() },
        destroyed() { this.stream && this.stream.getTracks().forEach((t) => t.stop()) }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".Cutting">
      // Plays the program and handles the hand on the timeline. The program is
      // the server's (data-program); this never changes it except by events.
      const FRAME = 1000 / 30
      const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v))
      const clock = (ms) => {
        const s = Math.max(ms, 0) / 1000
        return `${Math.floor(s / 60)}:${(s % 60).toFixed(1).padStart(4, "0")}`
      }
      const level = (db) => clamp(Math.pow(10, (db || 0) / 20), 0, 1)

      export default {
        mounted() {
          this.t = 0
          this.playing = false
          this.screen = this.el.querySelector("#screen")
          this.videos = [...this.screen.querySelectorAll("video")]
          this.still = this.screen.querySelector("[data-role=still]")
          this.stillImg = this.still.querySelector("img")
          this.titleBox = this.screen.querySelector("[data-role=titles]")
          this.timecode = this.el.querySelector("#timecode")
          this.playhead = this.el.querySelector("#playhead")
          this.audios = new Map()
          this.read()

          this.el.querySelector("[data-role=play]").addEventListener("click", () => this.toggle())
          this.el.querySelector("[data-role=split]").addEventListener("click", () => this.pushEvent("split", {at: Math.round(this.t)}))
          this.el.querySelector("[data-role=title]").addEventListener("click", () => this.pushEvent("add_title", {at: Math.round(this.t)}))
          document.addEventListener("click", this.onAddSound = (e) => {
            const id = e.target.closest("[data-add-sound]")?.dataset.addSound
            if (id) this.pushEvent("add_sound", {id, at: Math.round(this.t)})
          })
          this.el.addEventListener("pointerdown", (e) => this.down(e))
          this.el.addEventListener("pointermove", (e) => this.moveTo(e))
          this.el.addEventListener("pointerup", (e) => this.up(e))
          this.el.addEventListener("pointercancel", (e) => this.up(e))
          window.addEventListener("keydown", this.onKey = (e) => this.key(e))
          this.show(0)
        },
        updated() {
          this.read()
          this.show(this.t)
        },
        destroyed() {
          this.pause()
          window.removeEventListener("keydown", this.onKey)
          document.removeEventListener("click", this.onAddSound)
        },

        read() {
          this.program = JSON.parse(this.el.dataset.program)
          this.timeline = this.el.querySelector("[data-role=timeline]")
          this.pps = parseFloat(getComputedStyle(this.timeline).getPropertyValue("--pps")) || 40
          // Titles drawn as the render sets them.
          this.titleBox.replaceChildren(...this.program.titles.map((title) => {
            const el = document.createElement("div")
            el.className = `adm-cut-overlay adm-cut-overlay--${title.style}`
            el.textContent = title.style === "lower" ? title.text.toUpperCase() : title.text
            el.dataset.id = title.id
            return el
          }))
          // One audio element per sound, kept across updates by its file.
          const keep = new Map()
          for (const sound of this.program.sounds) {
            let audio = this.audios.get(sound.id)
            if (!audio || audio.dataset.url !== sound.url) {
              audio = new Audio(sound.url)
              audio.preload = "auto"
              audio.dataset.url = sound.url
            }
            keep.set(sound.id, audio)
          }
          for (const [id, audio] of this.audios) if (!keep.has(id)) audio.pause()
          this.audios = keep
          this.t = clamp(this.t, 0, this.program.length)
        },

        clipAt(t) {
          const clips = this.program.clips
          return clips.find((c) => t >= c.start && t < c.start + c.length) || clips[clips.length - 1]
        },

        // Puts the picture, titles and playhead where t says, without playing.
        show(t) {
          this.t = clamp(t, 0, this.program.length)
          const clip = this.clipAt(this.t)
          if (!clip) {
            this.videos.forEach((v) => (v.hidden = true))
            this.still.hidden = true
          } else if (clip.kind === "take") {
            const video = this.load(clip)
            if (!this.playing) video.currentTime = (clip.in + this.t - clip.start) / 1000
            this.front(video)
          } else {
            this.videos.forEach((v) => { v.hidden = true; v.pause() })
            this.still.hidden = false
            if (this.stillImg.getAttribute("src") !== clip.url) this.stillImg.src = clip.url
            this.stillImg.style.transform = this.camera(clip, (this.t - clip.start) / clip.length)
          }
          for (const el of this.titleBox.children) {
            const title = this.program.titles.find((x) => x.id === el.dataset.id)
            const into = this.t - title.at
            const fade = Math.min(400, title.length / 2)
            const on = into >= 0 && into < title.length
            el.hidden = !on
            el.style.opacity = on ? clamp(Math.min(into, title.length - into) / fade, 0, 1) : 0
          }
          this.timecode.textContent = clock(this.t)
          this.playhead.style.left = `calc(var(--track-name-w) + ${(this.t / 1000) * this.pps}px)`
        },

        // The render's zoompan, as a transform: 12% over the print's time.
        camera(clip, p) {
          p = clamp(p, 0, 1)
          switch (clip.move) {
            case "in": return `scale(${1 + 0.12 * p})`
            case "out": return `scale(${1.12 - 0.12 * p})`
            case "pan-left": return `scale(1.12) translateX(${(0.5 - p) * 10.7}%)`
            case "pan-right": return `scale(1.12) translateX(${(p - 0.5) * 10.7}%)`
            default: return "none"
          }
        },

        // The video holding this clip's take, loading it into the spare one.
        load(clip) {
          let video = this.videos.find((v) => v.dataset.clip === clip.id)
          if (!video) {
            video = this.videos.find((v) => v.hidden) || this.videos[0]
            video.dataset.clip = clip.id
            if (video.getAttribute("src") !== clip.url) video.src = clip.url
            video.currentTime = clip.in / 1000
          }
          video.volume = level(clip.gain)
          return video
        },

        front(video) {
          this.still.hidden = true
          for (const v of this.videos) {
            if (v === video) v.hidden = false
            else { v.hidden = true; v.pause() }
          }
        },

        // The take after this one, ready in the spare video before it is needed.
        preload(clip) {
          const next = this.program.clips[this.program.clips.indexOf(clip) + 1]
          if (next && next.kind === "take" && !this.videos.some((v) => v.dataset.clip === next.id)) {
            const spare = this.videos.find((v) => v.hidden)
            if (spare) { spare.dataset.clip = next.id; if (spare.getAttribute("src") !== next.url) spare.src = next.url; spare.currentTime = next.in / 1000 }
          }
        },

        toggle() { this.playing ? this.pause() : this.play() },

        play() {
          if (!this.program.clips.length) return
          if (this.t >= this.program.length - FRAME) this.show(0)
          this.playing = true
          this.el.querySelector("[data-role=play]").classList.add("is-on")
          this.clock0 = performance.now() - this.t
          this.current = null
          const tick = () => {
            if (!this.playing) return
            const clip = this.clipAt(this.t)
            if (clip !== this.current) {
              this.current = clip
              if (clip.kind === "take") {
                const video = this.load(clip)
                video.currentTime = (clip.in + this.t - clip.start) / 1000
                this.front(video)
                video.play().catch(() => {})
              }
              this.clock0 = performance.now() - this.t
              this.preload(clip)
            }
            if (clip.kind === "take") {
              const video = this.videos.find((v) => v.dataset.clip === clip.id)
              this.t = clip.start + video.currentTime * 1000 - clip.in
            } else {
              this.t = performance.now() - this.clock0
            }
            if (this.t >= clip.start + clip.length) this.t = clip.start + clip.length
            this.sounds(clip)
            this.show(this.t)
            if (this.t >= this.program.length - 1) return this.pause()
            this.frame = requestAnimationFrame(tick)
          }
          this.frame = requestAnimationFrame(tick)
        },

        sounds(clip) {
          const speaking = clip && clip.kind === "take" && clip.sound
          for (const sound of this.program.sounds) {
            const audio = this.audios.get(sound.id)
            const into = this.t - sound.at
            if (this.playing && into >= 0 && into < sound.length) {
              let v = level(sound.gain)
              if (sound.fade_in && into < sound.fade_in) v *= into / sound.fade_in
              if (sound.fade_out && sound.length - into < sound.fade_out) v *= (sound.length - into) / sound.fade_out
              if (sound.duck && speaking) v *= 0.3
              audio.volume = clamp(v, 0, 1)
              const want = (sound.in + into) / 1000
              if (audio.paused) { audio.currentTime = want; audio.play().catch(() => {}) }
              else if (Math.abs(audio.currentTime - want) > 0.25) audio.currentTime = want
            } else if (!audio.paused) audio.pause()
          }
        },

        pause() {
          this.playing = false
          cancelAnimationFrame(this.frame)
          this.videos.forEach((v) => v.pause())
          for (const audio of this.audios.values()) audio.pause()
          this.el.querySelector("[data-role=play]")?.classList.remove("is-on")
        },

        seek(t) {
          const playing = this.playing
          this.pause()
          this.show(t)
          if (playing) this.play()
        },

        key(e) {
          if (e.target.closest("input, textarea, select")) return
          const step = e.shiftKey ? 1000 : FRAME
          if (e.key === " ") { e.preventDefault(); this.toggle() }
          else if (e.key === "s" || e.key === "S") this.pushEvent("split", {at: Math.round(this.t)})
          else if (e.key === "Delete" || e.key === "Backspace") { if (this.el.dataset.selected) { e.preventDefault(); this.pushEvent("delete", {}) } }
          else if (e.key === "ArrowRight") { e.preventDefault(); this.seek(this.t + step) }
          else if (e.key === "ArrowLeft") { e.preventDefault(); this.seek(this.t - step) }
          else if (e.key === "Home") this.seek(0)
          else if (e.key === "End") this.seek(this.program.length)
        },

        // The timeline under the hand: a block is selected, moved or trimmed;
        // anywhere else on it puts the playhead there.
        msAt(e) {
          const box = this.timeline.getBoundingClientRect()
          const name = parseFloat(getComputedStyle(this.timeline).getPropertyValue("--track-name-w")) || 0
          return ((e.clientX - box.left - name + this.timeline.scrollLeft) / this.pps) * 1000
        },

        down(e) {
          if (!e.target.closest("[data-role=timeline]")) return
          const block = e.target.closest(".adm-cut-block")
          if (!block) {
            this.scrubbing = true
            this.seek(this.msAt(e))
            this.el.setPointerCapture(e.pointerId)
            return
          }
          e.preventDefault()
          this.drag = {
            block,
            id: block.dataset.id,
            track: block.closest("[data-track]").dataset.track,
            edge: e.target.dataset.edge || null,
            x: e.clientX,
            at: parseFloat(block.dataset.at),
            length: parseFloat(block.dataset.length),
            dx: 0
          }
          this.el.setPointerCapture(e.pointerId)
        },

        moveTo(e) {
          if (this.scrubbing) return this.seek(this.msAt(e))
          if (!this.drag) return
          const d = this.drag
          d.dx = e.clientX - d.x
          const ds = d.dx / this.pps
          if (!d.edge) d.block.style.transform = `translateX(${d.dx}px)`
          else if (d.edge === "right") d.block.style.setProperty("--len", Math.max(d.length / 1000 + ds, 0.1))
          else { d.block.style.setProperty("--at", d.at / 1000 + ds); d.block.style.setProperty("--len", Math.max(d.length / 1000 - ds, 0.1)) }
        },

        up(e) {
          if (this.scrubbing) { this.scrubbing = false; return }
          const d = this.drag
          if (!d) return
          this.drag = null
          const delta = Math.round((d.dx / this.pps) * 1000)
          if (Math.abs(d.dx) < 3) return this.pushEvent("select", {id: d.id})
          if (d.edge) return this.pushEvent("trim", {id: d.id, edge: d.edge, delta})
          if (d.track === "clips") {
            const middle = d.at + delta + d.length / 2
            const others = this.program.clips.filter((c) => c.id !== d.id)
            const index = others.filter((c) => c.start + c.length / 2 < middle).length
            this.pushEvent("move", {id: d.id, index})
          } else {
            this.pushEvent("place", {id: d.id, at: Math.max(Math.round(d.at + delta), 0)})
          }
        }
      }
    </script>
    """
  end

  defp kind_name(%{"kind" => "take"}), do: "Take"
  defp kind_name(%{"kind" => "still"}), do: "Print"
  defp kind_name(%{"text" => _}), do: "Title"
  defp kind_name(_), do: "Sound"

  defp error_text(:too_large), do: "too large"
  defp error_text(:not_accepted), do: "not a video or sound file"
  defp error_text(:too_many_files), do: "eight at a time"
  defp error_text(other), do: to_string(other)

  attr :item, :map, required: true
  attr :media, :map, required: true

  defp inspect_fields(%{item: %{"kind" => "take"}} = assigns) do
    ~H"""
    <p class="adm-dr-hint">{@media[@item["media"]] && @media[@item["media"]].name}</p>
    <.num_field name="in" label="In (s)" value={secs(@item["in"])} step="0.01" />
    <.num_field name="out" label="Out (s)" value={secs(@item["out"])} step="0.01" />
    <.num_field name="gain" label="Gain (dB)" value={@item["gain"]} step="0.5" />
    """
  end

  defp inspect_fields(%{item: %{"kind" => "still"}} = assigns) do
    ~H"""
    <img src={print_url(@item["frame"])} alt="" class="adm-cut-inspect-print" />
    <.num_field name="duration" label="Length (s)" value={secs(@item["duration"])} step="0.1" />
    <label class="adm-label" for="move">Camera</label>
    <select id="move" name="move" class="adm-input">
      <option
        :for={
          {value, text} <- [
            {"in", "Slowly closer"},
            {"out", "Slowly further"},
            {"pan-left", "Across, to the left"},
            {"pan-right", "Across, to the right"},
            {"none", "Still"}
          ]
        }
        value={value}
        selected={@item["move"] == value}
      >
        {text}
      </option>
    </select>
    """
  end

  defp inspect_fields(%{item: %{"text" => _}} = assigns) do
    ~H"""
    <label class="adm-label" for="title-text">Words</label>
    <input
      id="title-text"
      type="text"
      name="text"
      value={@item["text"]}
      class="adm-input"
      maxlength="120"
      phx-debounce="300"
    />
    <label class="adm-label" for="style">Style</label>
    <select id="style" name="style" class="adm-input">
      <option value="title" selected={@item["style"] == "title"}>Across the middle</option>
      <option value="lower" selected={@item["style"] == "lower"}>Along the foot</option>
    </select>
    <.num_field name="at" label="Starts at (s)" value={secs(@item["at"])} step="0.1" />
    <.num_field name="duration" label="Length (s)" value={secs(@item["duration"])} step="0.1" />
    """
  end

  defp inspect_fields(assigns) do
    ~H"""
    <p class="adm-dr-hint">{@media[@item["media"]] && @media[@item["media"]].name}</p>
    <.num_field name="at" label="Starts at (s)" value={secs(@item["at"])} step="0.1" />
    <.num_field name="in" label="From (s) into the file" value={secs(@item["in"])} step="0.1" />
    <.num_field name="out" label="To (s) into the file" value={secs(@item["out"])} step="0.1" />
    <.num_field name="gain" label="Gain (dB)" value={@item["gain"]} step="0.5" />
    <.num_field name="fade_in" label="Fade in (s)" value={secs(@item["fade_in"])} step="0.1" />
    <.num_field name="fade_out" label="Fade out (s)" value={secs(@item["fade_out"])} step="0.1" />
    <input type="hidden" name="duck_shown" value="1" />
    <label class="adm-cut-check">
      <input type="checkbox" name="duck" value="true" checked={@item["duck"]} />
      Lower it while the picture speaks
    </label>
    """
  end

  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :step, :string, default: "1"

  defp num_field(assigns) do
    ~H"""
    <label class="adm-label" for={"inspect-#{@name}"}>{@label}</label>
    <input
      id={"inspect-#{@name}"}
      type="number"
      name={@name}
      value={@value}
      step={@step}
      class="adm-input"
      phx-debounce="300"
    />
    """
  end
end
