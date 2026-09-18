defmodule WebWeb.AdminLive.LogsManager do
  use WebWeb, :live_view

  alias Web.Audio
  alias Web.Audio.Log
  alias Web.Media
  alias Web.Media.Transcoder
  alias Web.Uploads

  import WebWeb.CmsStyles
  import WebWeb.LogsLive.Format, only: [format_duration: 1, presence: 1]

  @moduledoc """
  Admin for the captain's logs: a recording booth first, a file manager
  second.

  The screen is a theater — camera preview in the viewport, one record button
  under it — and the edit controls appear in place once there is something to
  review: trim handles over the timeline, a scrubber for the poster frame,
  and the metadata beside them. Trim and poster are *numbers*, pushed as
  ordinary form fields and applied by ffmpeg during the transcode, so nothing
  is re-encoded in the browser.

  The blob reaches the server through LiveView's chunked uploader
  (`this.upload/2` from the hook), not base64 through `pushEvent` — which is
  what the old, dead `audio_recorder.js` did and what a video would have
  broken outright.

  Whatever arrives — recorded here or dropped from disk — lands as a row at
  `status: "pending"` and goes straight on the transcode queue, so a file is
  never held anywhere unaccounted for. Publishing is a separate decision that
  can be made while it encodes.
  """

  @accept ~w(.webm .mp4 .m4a .mp3 .wav .mov .ogg
             video/webm video/mp4 video/quicktime
             audio/webm audio/mp4 audio/mpeg audio/ogg audio/wav)

  # A 30-minute 720p recording is about 560 MB; this leaves room above that
  # without inviting an upload that would take an hour over a websocket.
  @max_file_size 1_000_000_000

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Captain's Logs | Admin")
      |> assign(:accept, @accept)
      |> assign(:editing, nil)
      |> assign(:progress, %{})
      |> assign(:staged, %{})
      |> assign_new_form()
      |> load_logs()
      |> allow_upload(:media,
        accept: @accept,
        max_entries: 1,
        max_file_size: @max_file_size,
        auto_upload: true,
        progress: &handle_progress/3
      )

    Enum.each(socket.assigns.logs, fn log ->
      if log.status in ["pending", "processing"], do: Transcoder.subscribe(log.id)
    end)

    {:ok, socket}
  end

  # --- The form ---

  def handle_event("validate", %{"log" => params}, socket) do
    changeset =
      socket.assigns.editing
      |> log_or_new()
      |> Audio.change_log(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  # Only ever reached when editing an existing entry: a new one is created by
  # the upload finishing, not by a submit.
  def handle_event("save", %{"log" => params}, socket) do
    case socket.assigns.editing do
      nil ->
        {:noreply,
         put_flash(socket, :error, "Record something or drop a file — there is nothing to save.")}

      log ->
        update_existing(socket, log, params)
    end
  end

  # Takes the recorder's choices — trim, poster frame, whether to publish —
  # before the upload starts. The hook waits for this reply and only then
  # begins uploading, so handle_progress/3 can never read the form halfway
  # through a change. Leaning on phx-change instead would be exactly that
  # race: for a short recording the upload can finish before the change lands.
  def handle_event("stage", params, socket) when is_map(params) do
    {:reply, %{ok: true}, assign(socket, :staged, Map.delete(params, "_target"))}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    log = Audio.get_log!(id)

    {:noreply,
     socket
     |> assign(:editing, log)
     |> assign(:form, to_form(Audio.change_log(log)))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> assign(:editing, nil) |> assign_new_form()}
  end

  def handle_event("toggle_published", %{"id" => id}, socket) do
    log = Audio.get_log!(id)
    {:ok, _log} = Audio.update_log(log, %{published: !log.published})
    {:noreply, load_logs(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id |> Audio.get_log!() |> Audio.delete_log()

    {:noreply,
     socket
     |> assign(:editing, nil)
     |> assign_new_form()
     |> load_logs()
     |> put_flash(:info, "Log purged.")}
  end

  # Re-runs a failed transcode. Only possible while the source is still on
  # disk — it is deleted the moment an encode succeeds, so this is for a job
  # that never got that far.
  def handle_event("retry", %{"id" => id}, socket) do
    log = Audio.get_log!(id)

    if log.source_path && File.regular?(log.source_path) do
      Transcoder.subscribe(log.id)
      Media.enqueue(log.id)
      {:noreply, socket |> load_logs() |> put_flash(:info, "Re-queued.")}
    else
      {:noreply,
       put_flash(socket, :error, "The source for that entry is gone — it has to be re-recorded.")}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media, ref)}
  end

  # --- Ingest ---

  # Runs as the upload completes. Everything that arrives is written down
  # immediately, whether it was recorded here or dropped in: a file on disk
  # with no row pointing at it is the one state worth never being in.
  defp handle_progress(:media, entry, socket) do
    if entry.done? do
      # The form holds what was typed; `staged` holds what the recorder chose.
      # The recorder's values win, and they are read from their own assign
      # because a "validate" between staging and completion would have wiped
      # them out of the form.
      params = Map.merge(socket.assigns.form.params, socket.assigns.staged)

      staged =
        consume_uploaded_entries(socket, :media, fn %{path: path}, entry ->
          {:ok, Uploads.stage_upload!(path, entry.client_name)}
        end)

      case staged do
        [source] -> {:noreply, ingest(socket, params, source, entry)}
        [] -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp ingest(socket, params, source, entry) do
    attrs =
      params
      |> Map.put("source_path", source)
      |> Map.put_new("recorded_on", Date.to_iso8601(Web.Clock.local_today()))
      |> Map.put("kind", kind_of(entry))
      |> Map.put("status", "pending")
      |> Map.put_new("recorded_at", DateTime.utc_now() |> DateTime.truncate(:second))

    case Audio.create_log(attrs) do
      {:ok, log} ->
        Transcoder.subscribe(log.id)
        Media.enqueue(log.id)

        socket
        |> assign(:editing, nil)
        |> assign(:staged, %{})
        |> assign_new_form()
        |> load_logs()
        |> put_flash(:info, "#{Log.title(log)} filed — transcoding now.")

      {:error, changeset} ->
        # The row did not take, so nothing should be left holding the file.
        Uploads.discard_staged(source)

        socket
        |> assign(:form, to_form(changeset))
        |> put_flash(:error, "That recording could not be filed.")
    end
  end

  # What the *form* asked for, falling back to what the file looks like.
  # Either way the transcoder has the last word: it probes the source and
  # corrects the row if there turns out to be no video in it.
  defp kind_of(%{client_type: "audio/" <> _}), do: "audio"

  defp kind_of(%{client_name: name}) when is_binary(name) do
    extension = name |> Path.extname() |> String.downcase()
    if extension in ~w(.m4a .mp3 .wav .ogg), do: "audio", else: "video"
  end

  defp kind_of(_entry), do: "video"

  defp update_existing(socket, log, params) do
    case Audio.update_log(log, params) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(:editing, nil)
         |> assign_new_form()
         |> load_logs()
         |> put_flash(:info, "#{Log.title(updated)} updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # --- Transcode progress ---

  def handle_info({:transcode_progress, id, percent}, socket) do
    {:noreply, assign(socket, :progress, Map.put(socket.assigns.progress, id, percent))}
  end

  def handle_info({:transcode_done, id, _status}, socket) do
    {:noreply,
     socket
     |> assign(:progress, Map.delete(socket.assigns.progress, id))
     |> load_logs()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # --- Assigns ---

  defp log_or_new(nil), do: %Log{}
  defp log_or_new(%Log{} = log), do: log

  defp assign_new_form(socket) do
    assign(
      socket,
      :form,
      to_form(
        Audio.change_log(%Log{}, %{
          "recorded_on" => Date.to_iso8601(Web.Clock.local_today()),
          "kind" => "video",
          "published" => "true"
        })
      )
    )
  end

  defp load_logs(socket), do: assign(socket, :logs, Audio.list_logs())

  defp upload_error_message(:too_large), do: "That file is larger than 1 GB."
  defp upload_error_message(:not_accepted), do: "That is not a video or audio file."
  defp upload_error_message(:too_many_files), do: "One recording at a time."
  defp upload_error_message(_error), do: "That upload was refused."

  defp status_label("pending"), do: "Queued"
  defp status_label("processing"), do: "Transcoding"
  defp status_label("ready"), do: "Ready"
  defp status_label("failed"), do: "Failed"
  defp status_label(other), do: other

  def render(assigns) do
    ~H"""
    <.cms_styles />
    <.theater_styles />

    <div class="cms">
      <h1 class="cms-title">Captain's Logs</h1>
      <p class="cms-lede">Record here, or drop a file you already have.</p>

      <%!-- The theater. Everything the recorder needs is inside this one
            element, so the hook works against `this.el` rather than hunting
            the document for ids the way the one it replaced did. --%>
      <section
        id="theater"
        class="cms-panel theater"
        phx-hook=".LogRecorder"
        phx-drop-target={@uploads.media.ref}
      >
        <div class="theater-screen">
          <video class="theater-video" playsinline muted></video>

          <div class="theater-placeholder" data-role="placeholder">
            <p class="theater-placeholder-title" data-role="placeholder-title">Camera off</p>
            <p class="cms-hint" data-role="placeholder-hint">
              Drop a video or audio file here, or arm the camera below.
            </p>
          </div>

          <div class="theater-tally" data-role="tally" hidden>
            <span class="theater-dot" aria-hidden="true"></span>
            <span data-role="elapsed">0:00</span>
          </div>

          <canvas class="theater-meter" data-role="meter" width="480" height="48"></canvas>
        </div>

        <div class="theater-controls">
          <div class="theater-modes" role="group" aria-label="Recording mode">
            <button type="button" class="theater-mode is-active" data-mode="video">Video</button>
            <button type="button" class="theater-mode" data-mode="audio">Audio</button>
          </div>

          <button type="button" class="theater-record" data-role="record">
            <span class="theater-record-mark" aria-hidden="true"></span>
            <span data-role="record-label">Arm camera</span>
          </button>

          <div class="theater-devices">
            <label class="theater-device" data-role="camera-field">
              <span>Camera</span>
              <select data-role="cameras"></select>
            </label>
            <label class="theater-device">
              <span>Microphone</span>
              <select data-role="mics"></select>
            </label>
          </div>

          <p class="cms-error theater-device-error" data-role="device-error" hidden></p>
        </div>

        <%!-- Review. Trim and poster are numbers, applied by ffmpeg on the
              server — nothing is re-encoded in the browser. --%>
        <div class="theater-review" data-role="review" hidden>
          <div class="theater-trim">
            <label class="theater-range">
              <span>In <b data-role="in-label">0:00</b></span>
              <input type="range" data-role="trim-in" min="0" max="1000" value="0" step="1" />
            </label>
            <label class="theater-range">
              <span>Out <b data-role="out-label">0:00</b></span>
              <input type="range" data-role="trim-out" min="0" max="1000" value="1000" step="1" />
            </label>
            <label class="theater-range">
              <span>Poster <b data-role="poster-label">0:00</b></span>
              <input type="range" data-role="poster-at" min="0" max="1000" value="100" step="1" />
            </label>
          </div>

          <div class="cms-actions">
            <button type="button" class="cms-link" data-role="retake">Retake</button>
            <button type="button" class="cms-link" data-role="save-draft">Save as draft</button>
            <button type="button" class="theater-publish" data-role="publish">Publish</button>
          </div>
        </div>

        <div :for={entry <- @uploads.media.entries} class="theater-upload">
          <p class="cms-hint">Uploading {entry.client_name} — {entry.progress}%</p>
          <div class="cms-progress">
            <div class="cms-progress-bar" style={"width: #{entry.progress}%"}></div>
          </div>
          <button type="button" class="cms-link" phx-click="cancel_upload" phx-value-ref={entry.ref}>
            Cancel
          </button>
          <p :for={err <- upload_errors(@uploads.media, entry)} class="cms-error">
            {upload_error_message(err)}
          </p>
        </div>

        <p :for={err <- upload_errors(@uploads.media)} class="cms-error">
          {upload_error_message(err)}
        </p>

        <script :type={Phoenix.LiveView.ColocatedHook} name=".LogRecorder">
          // The recording booth. Everything is scoped to `this.el` — the hook
          // this replaced reached into the document for ids, which is why it
          // silently did nothing the moment the markup moved.
          //
          // Trim and poster are never applied here: they are two numbers sent
          // with the upload and handed to ffmpeg, so the browser re-encodes
          // nothing and a 30-minute take costs one pass on the server.
          const fmt = (s) => {
            const m = Math.floor(s / 60)
            return `${m}:${String(Math.floor(s % 60)).padStart(2, "0")}`
          }

          export default {
            mounted() {
              this.mode = "video"
              this.stream = null
              this.recorder = null
              this.chunks = []
              this.blob = null
              this.blobUrl = null
              this.duration = 0
              this.startedAt = 0
              this.timer = null
              this.audioCtx = null
              this.raf = null

              this.$ = (role) => this.el.querySelector(`[data-role="${role}"]`)
              this.video = this.el.querySelector(".theater-video")
              this.meter = this.$("meter")

              // The chosen devices are remembered here rather than read off
              // the <select> on demand: re-enumerating rebuilds the options
              // (labels only exist once permission has been granted), and a
              // rebuilt <select> has forgotten what was picked.
              this.selected = { videoinput: null, audioinput: null }

              this.el.querySelectorAll("[data-mode]").forEach((button) => {
                button.addEventListener("click", () => this.setMode(button.dataset.mode))
              })

              this.el.querySelectorAll('[data-role="cameras"], [data-role="mics"]')
                .forEach((select) => {
                  select.addEventListener("change", () => this.pickDevice(select))
                })

              // A device appearing or going away should update the list.
              this.onDeviceChange = () => this.listDevices()
              navigator.mediaDevices?.addEventListener?.("devicechange", this.onDeviceChange)

              this.$("record").addEventListener("click", () => this.toggleRecord())
              this.$("retake").addEventListener("click", () => this.reset())
              this.$("publish").addEventListener("click", () => this.send(true))
              this.$("save-draft").addEventListener("click", () => this.send(false))

              this.el.querySelectorAll('[data-role^="trim-"], [data-role="poster-at"]')
                .forEach((input) => input.addEventListener("input", () => this.syncRanges()))

              this.syncChrome()
              this.listDevices()
            },

            // Every label and affordance that depends on state is set in one
            // place, so they cannot drift apart as the state moves.
            syncChrome() {
              this.$("record-label").textContent =
                this.recorder ? "Stop" : this.stream ? "Record" : this.mode === "audio" ? "Arm microphone" : "Arm camera"

              const camera = this.$("camera-field")
              if (camera) camera.hidden = this.mode !== "video"

              const title = this.$("placeholder-title")
              if (title) {
                title.textContent =
                  this.mode === "audio" ? (this.stream ? "Microphone live" : "Microphone off") : "Camera off"
              }

              this.el.querySelectorAll("[data-mode]").forEach((b) =>
                b.classList.toggle("is-active", b.dataset.mode === this.mode))
            },

            setMode(mode) {
              if (this.recorder || this.mode === mode) return
              this.mode = mode
              this.disarm()
            },

            // Picking a device that does nothing until you disarm is what
            // makes a picker feel broken, so reopen the stream on the spot.
            async pickDevice(select) {
              const kind = select.dataset.role === "cameras" ? "videoinput" : "audioinput"
              this.selected[kind] = select.value || null

              if (this.stream && !this.recorder) {
                this.disarm()
                try {
                  await this.arm()
                } catch (error) {
                  this.showDeviceError(error)
                }
              }
            },

            showDeviceError(problem) {
              const box = this.$("device-error")
              if (!box) return
              const message =
                problem instanceof Error ? `Could not open that device — ${problem.message}` : problem
              box.hidden = !message
              box.textContent = message || ""
            },

            async listDevices() {
              if (!navigator.mediaDevices?.enumerateDevices) return

              const devices = await navigator.mediaDevices.enumerateDevices()

              const fill = (select, kind, noun) => {
                if (!select) return
                const options = devices.filter((d) => d.kind === kind)

                // Labels are blank until permission has been granted once, so
                // this runs again after arming — and rebuilding the options
                // resets the <select>. Only rebuild when the set has actually
                // changed, and put the choice back either way.
                const signature = options.map((d) => `${d.deviceId}:${d.label}`).join("|")
                if (select.dataset.signature !== signature) {
                  select.dataset.signature = signature
                  select.innerHTML = ""
                  options.forEach((d, i) => {
                    const option = document.createElement("option")
                    option.value = d.deviceId
                    option.textContent = d.label || `${noun} ${i + 1}`
                    select.appendChild(option)
                  })
                }

                const wanted = this.selected[kind]
                if (wanted && options.some((d) => d.deviceId === wanted)) select.value = wanted
                this.selected[kind] = select.value || null
              }

              fill(this.$("cameras"), "videoinput", "Camera")
              fill(this.$("mics"), "audioinput", "Microphone")
              this.syncChrome()
            },

            constraints() {
              const camera = this.selected.videoinput
              const mic = this.selected.audioinput

              // `exact`, and it has to be: Chrome treats an `ideal` deviceId
              // as a suggestion and hands back the default anyway, so the
              // picker silently selects nothing. The cost is that a device
              // which has gone away throws, which `arm/0` catches.
              const audio = mic ? { deviceId: { exact: mic } } : true

              if (this.mode === "audio") return { audio, video: false }

              // 720p30 caps the blob at roughly 560 MB for half an hour,
              // rather than the several GB an uncapped capture would make.
              return {
                audio,
                video: {
                  width: { ideal: 1280 },
                  height: { ideal: 720 },
                  frameRate: { ideal: 30 },
                  ...(camera ? { deviceId: { exact: camera } } : {})
                }
              }
            },

            async arm() {
              this.showDeviceError(null)

              try {
                this.stream = await navigator.mediaDevices.getUserMedia(this.constraints())
              } catch (error) {
                // A remembered device that has since been unplugged fails the
                // `exact` constraint. Opening the default is better than
                // opening nothing, as long as it is said out loud.
                if (!["OverconstrainedError", "NotFoundError"].includes(error.name)) throw error
                this.selected = { videoinput: null, audioinput: null }
                this.stream = await navigator.mediaDevices.getUserMedia(this.constraints())
                this.showDeviceError("That device is no longer available — using the default.")
              }

              if (this.mode === "video") {
                this.video.srcObject = this.stream
                this.video.muted = true
                await this.video.play().catch(() => {})
              }

              this.el.classList.add("is-armed")
              // Audio has nothing to show, so the plate keeps its caption and
              // the level meter does the talking.
              this.$("placeholder").hidden = this.mode === "video"
              this.startMeter()
              this.syncChrome()

              // Device labels only exist once permission has been granted, so
              // the list is worth re-reading now that it has been.
              await this.listDevices()
              this.syncSelectionFromStream()
            },

            // Show what is actually open rather than what was asked for. A
            // constraint can be met by a different device than the one
            // requested, and a picker that disagrees with the microphone you
            // are actually recording through is worse than no picker.
            syncSelectionFromStream() {
              if (!this.stream) return

              const tracks = {
                videoinput: this.stream.getVideoTracks()[0],
                audioinput: this.stream.getAudioTracks()[0]
              }

              for (const [kind, track] of Object.entries(tracks)) {
                const id = track?.getSettings?.().deviceId
                if (!id) continue
                this.selected[kind] = id
                const select = this.$(kind === "videoinput" ? "cameras" : "mics")
                if (select && [...select.options].some((o) => o.value === id)) select.value = id
              }
            },

            disarm() {
              if (this.stream) this.stream.getTracks().forEach((t) => t.stop())
              this.stream = null
              this.stopMeter()
              if (this.video) this.video.srcObject = null
              this.el.classList.remove("is-armed")
              const placeholder = this.$("placeholder")
              if (placeholder) placeholder.hidden = false
              this.syncChrome()
            },

            async toggleRecord() {
              if (!this.stream) {
                try {
                  await this.arm()
                } catch (error) {
                  // Into its own element. Writing this into the placeholder
                  // replaced its children with a bare string, and the drop
                  // hint never came back.
                  this.showDeviceError(error)
                }
                return
              }

              if (this.recorder) return this.stop()
              this.start()
            },

            pickMime() {
              const wanted = this.mode === "audio"
                ? ["audio/webm;codecs=opus", "audio/webm", "audio/mp4"]
                : ["video/webm;codecs=vp9,opus", "video/webm;codecs=vp8,opus", "video/webm", "video/mp4"]
              return wanted.find((t) => MediaRecorder.isTypeSupported(t)) || ""
            },

            start() {
              const mimeType = this.pickMime()
              this.chunks = []
              this.recorder = new MediaRecorder(this.stream, {
                ...(mimeType ? { mimeType } : {}),
                ...(this.mode === "video" ? { videoBitsPerSecond: 2_500_000 } : {})
              })

              this.recorder.ondataavailable = (e) => { if (e.data.size) this.chunks.push(e.data) }
              this.recorder.onstop = () => this.review(mimeType)
              this.recorder.start(1000)

              this.startedAt = Date.now()
              this.el.classList.add("is-recording")
              this.$("tally").hidden = false
              this.syncChrome()
              this.timer = setInterval(() => {
                this.$("elapsed").textContent = fmt((Date.now() - this.startedAt) / 1000)
              }, 250)
            },

            stop() {
              if (this.recorder?.state === "recording") this.recorder.stop()
              clearInterval(this.timer)
              this.el.classList.remove("is-recording")
              this.$("tally").hidden = true
            },

            review(mimeType) {
              this.duration = (Date.now() - this.startedAt) / 1000
              this.blob = new Blob(this.chunks, { type: mimeType || this.chunks[0]?.type || "" })
              this.recorder = null
              this.disarm()

              this.blobUrl = URL.createObjectURL(this.blob)
              if (this.mode === "video") {
                this.video.srcObject = null
                this.video.src = this.blobUrl
                this.video.muted = false
                this.video.controls = true
              }

              this.$("placeholder").hidden = this.mode === "video"
              this.$("review").hidden = false
              this.syncChrome()
              this.syncRanges()
            },

            // The sliders are permille of the take, so they need no knowledge
            // of its length until there is one.
            syncRanges() {
              const at = (role) => (Number(this.$(role).value) / 1000) * this.duration
              let inAt = at("trim-in")
              let outAt = at("trim-out")
              if (outAt <= inAt) {
                outAt = Math.min(this.duration, inAt + 0.5)
                this.$("trim-out").value = String(Math.round((outAt / this.duration) * 1000))
              }
              const posterAt = Math.min(Math.max(at("poster-at"), inAt), outAt)

              this.$("in-label").textContent = fmt(inAt)
              this.$("out-label").textContent = fmt(outAt)
              this.$("poster-label").textContent = fmt(posterAt)
              this.marks = { inAt, outAt, posterAt }

              if (this.mode === "video" && this.video.readyState > 0) {
                this.video.currentTime = posterAt
              }
            },

            send(published) {
              if (!this.blob) return
              const { inAt, outAt, posterAt } = this.marks
              const extension = (this.blob.type.split(";")[0].split("/")[1] || "webm")
              const name = `log-${Date.now()}.${extension}`
              const file = new File([this.blob], name, { type: this.blob.type })

              // Wait for the server to acknowledge the numbers before sending
              // any bytes: the upload of a short take can otherwise finish
              // before a phx-change would have landed.
              this.pushEvent("stage", {
                trim_start_ms: Math.round(inAt * 1000),
                trim_duration_ms: Math.round((outAt - inAt) * 1000),
                // Relative to the trimmed take, which is what ffmpeg sees.
                poster_at_ms: Math.round((posterAt - inAt) * 1000),
                published: published ? "true" : "false"
              }, () => {
                this.upload("media", [file])
                this.reset()
              })
            },

            reset() {
              this.stop()
              this.disarm()
              if (this.blobUrl) URL.revokeObjectURL(this.blobUrl)
              this.blobUrl = null
              this.blob = null
              this.chunks = []
              this.duration = 0
              if (this.video) { this.video.removeAttribute("src"); this.video.controls = false; this.video.load() }
              this.$("review").hidden = true
              const placeholder = this.$("placeholder")
              if (placeholder) placeholder.hidden = false
              this.showDeviceError(null)
              this.syncChrome()
            },

            startMeter() {
              if (!this.meter || !this.stream?.getAudioTracks().length) return
              const ctx = this.meter.getContext("2d")
              this.audioCtx = new (window.AudioContext || window.webkitAudioContext)()
              const analyser = this.audioCtx.createAnalyser()
              analyser.fftSize = 256
              this.audioCtx.createMediaStreamSource(this.stream).connect(analyser)
              const data = new Uint8Array(analyser.frequencyBinCount)

              const draw = () => {
                this.raf = requestAnimationFrame(draw)
                analyser.getByteFrequencyData(data)
                const { width, height } = this.meter
                ctx.clearRect(0, 0, width, height)
                const barWidth = width / data.length
                for (let i = 0; i < data.length; i++) {
                  const value = (data[i] / 255) * height
                  ctx.fillStyle = `rgba(255, 158, 61, ${0.25 + (data[i] / 255) * 0.75})`
                  ctx.fillRect(i * barWidth, height - value, barWidth - 1, value)
                }
              }
              draw()
            },

            stopMeter() {
              if (this.raf) cancelAnimationFrame(this.raf)
              this.raf = null
              if (this.audioCtx) { this.audioCtx.close().catch(() => {}); this.audioCtx = null }
              if (this.meter) {
                this.meter.getContext("2d").clearRect(0, 0, this.meter.width, this.meter.height)
              }
            },

            destroyed() {
              navigator.mediaDevices?.removeEventListener?.("devicechange", this.onDeviceChange)
              this.stop()
              this.disarm()
              if (this.blobUrl) URL.revokeObjectURL(this.blobUrl)
            }
          }
        </script>
      </section>

      <%!-- Metadata. The recorder's own choices do not come through this form
            — they are staged over the socket just before the upload — so the
            two can never be read half-applied. --%>
      <section class="cms-panel">
        <h2>
          {if @editing, do: "Editing #{Log.title(@editing)}", else: "Details for the next take"}
        </h2>

        <.form for={@form} phx-change="validate" phx-submit="save" id="log-form">
          <%!-- Must stay inside this form. The recorder hands its blob to
                LiveView with `this.upload/2`, which works by putting the file
                on this input and dispatching a change — and that change only
                allocates an upload entry if a phx-change binding sees it.
                Outside a form it fails silently on both sides: no entry, no
                error. --%>
          <.live_file_input upload={@uploads.media} class="cms-file-input" />

          <div class="cms-field">
            <.input field={@form[:caption]} type="text" label="Caption (optional)" class="cms-input" />
          </div>
          <div class="theater-row">
            <.input field={@form[:recorded_on]} type="date" label="Recorded on" class="cms-input" />
            <.input
              field={@form[:kind]}
              type="select"
              label="Kind"
              options={[{"Video", "video"}, {"Audio", "audio"}]}
              class="cms-input"
            />
          </div>
          <div class="cms-field">
            <.input field={@form[:keywords]} type="text" label="Keywords" class="cms-input" />
          </div>
          <div class="cms-field">
            <.input field={@form[:description]} type="textarea" label="Notes" class="cms-input" />
          </div>
          <div class="cms-field">
            <.input field={@form[:published]} type="checkbox" label="Published" />
          </div>

          <div :if={@editing} class="cms-actions">
            <button type="submit" class="theater-publish">Save changes</button>
            <button type="button" phx-click="cancel_edit" class="cms-link">Cancel</button>
          </div>
        </.form>
      </section>

      <section class="cms-panel">
        <h2>Archive</h2>

        <p :if={@logs == []} class="cms-empty">Nothing recorded yet.</p>

        <div class="cms-list">
          <article :for={log <- @logs} class="cms-item">
            <div class="cms-item-head">
              <div>
                <h3 class="cms-item-title">{Log.title(log)}</h3>
                <p class="cms-item-meta">
                  <span class={["theater-status", "is-#{log.status}"]}>
                    {status_label(log.status)}
                  </span>
                  · {log.kind} · {format_duration(log.duration) || "—"} · {log.slug}
                  <span :if={not log.published}>· draft</span>
                </p>
              </div>

              <div class="cms-item-actions">
                <.link :if={log.status == "ready"} navigate={~p"/logs/#{log.slug}"} class="cms-link">
                  View
                </.link>
                <button phx-click="edit" phx-value-id={log.id} class="cms-link">Edit</button>
                <button
                  :if={log.status == "failed"}
                  phx-click="retry"
                  phx-value-id={log.id}
                  class="cms-link"
                >
                  Retry
                </button>
                <button phx-click="toggle_published" phx-value-id={log.id} class="cms-link">
                  {if log.published, do: "Unpublish", else: "Publish"}
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={log.id}
                  data-confirm="Purge this log and its media?"
                  class="cms-link danger"
                >
                  Delete
                </button>
              </div>
            </div>

            <p :if={presence(log.caption)} class="cms-hint">{log.caption}</p>

            <div :if={Map.has_key?(@progress, log.id)} class="theater-transcode">
              <div class="cms-progress">
                <div class="cms-progress-bar" style={"width: #{@progress[log.id]}%"}></div>
              </div>
              <span class="cms-hint">Transcoding — {@progress[log.id]}%</span>
            </div>

            <p :if={log.status == "failed"} class="cms-error">{log.transcode_error}</p>

            <p
              :if={log.status == "ready" and is_nil(presence(log.keywords))}
              class="cms-keyword-missing"
            >
              No keywords — it will not appear under any filter.
            </p>
          </article>
        </div>
      </section>
    </div>
    """
  end

  # The booth's own styling. Admin pages carry their own <style> block in this
  # app — the admin layout is a deliberate dark exception to the paper design
  # system — and this is the part only the logs manager needs.
  defp theater_styles(assigns) do
    ~H"""
    <style>
      .theater-row { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1rem; }

      /* The screen: always 16/9, always dark, whether or not anything is in it. */
      .theater-screen {
        position: relative;
        aspect-ratio: 16 / 9;
        overflow: hidden;
        background: #08090b;
        border: 1px solid #2a2a2a;
        border-radius: 8px;
        display: flex;
        align-items: center;
        justify-content: center;
      }

      .theater-video { width: 100%; height: 100%; object-fit: contain; background: #08090b; }
      .theater.is-armed .theater-placeholder { display: none; }

      .theater-placeholder { position: absolute; inset: 0; display: flex; flex-direction: column;
        align-items: center; justify-content: center; gap: 0.25rem; text-align: center; padding: 1rem; }
      .theater-placeholder-title { color: #777; text-transform: uppercase; letter-spacing: 2px;
        font-size: 0.8rem; margin: 0; }

      /* Tally light: the one thing on the page allowed to be red. */
      .theater-tally { position: absolute; top: 0.75rem; left: 0.75rem; display: flex; align-items: center;
        gap: 0.5rem; padding: 0.25rem 0.6rem; background: rgba(0,0,0,0.65); border-radius: 999px;
        font-variant-numeric: tabular-nums; font-size: 0.8rem; color: #fff; }
      .theater-dot { width: 9px; height: 9px; border-radius: 50%; background: #e5484d;
        box-shadow: 0 0 10px rgba(229,72,77,0.9); animation: theater-blink 1.4s infinite; }
      @keyframes theater-blink { 50% { opacity: 0.25; } }
      @media (prefers-reduced-motion: reduce) { .theater-dot { animation: none; } }

      .theater-meter { position: absolute; left: 0; right: 0; bottom: 0; width: 100%; height: 48px;
        pointer-events: none; opacity: 0.85; }

      .theater-controls { display: flex; flex-wrap: wrap; align-items: center; gap: 1rem; margin-top: 1rem; }

      .theater-modes { display: flex; border: 1px solid #333; border-radius: 6px; overflow: hidden; }
      .theater-mode { background: none; border: 0; padding: 0.45rem 0.9rem; cursor: pointer;
        color: #999; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 1px; }
      .theater-mode.is-active { background: #ff6600; color: #111; font-weight: 700; }

      /* 48px tall, so the one control that matters clears the target minimum. */
      .theater-record { display: inline-flex; align-items: center; gap: 0.6rem; min-height: 48px;
        padding: 0 1.25rem; cursor: pointer; background: #1a1a1a; border: 1px solid #3a3a3a;
        border-radius: 999px; color: #eee; font-size: 0.8rem; text-transform: uppercase;
        letter-spacing: 1.5px; }
      .theater-record:hover { border-color: #ff6600; }
      .theater-record-mark { width: 14px; height: 14px; border-radius: 50%; background: #e5484d; }
      .theater.is-recording .theater-record-mark { border-radius: 2px; }

      .theater-devices { display: flex; gap: 1rem; margin-left: auto; flex-wrap: wrap; }
      .theater-device { display: flex; flex-direction: column; gap: 0.25rem; font-size: 0.7rem;
        text-transform: uppercase; letter-spacing: 1px; color: #777; }
      .theater-device select { background: #111; color: #ddd; border: 1px solid #333;
        border-radius: 6px; padding: 0.35rem 0.5rem; max-width: 220px; }

      .theater-review { margin-top: 1.25rem; padding-top: 1.25rem; border-top: 1px solid #2a2a2a; }
      .theater-trim { display: grid; gap: 0.75rem; }
      .theater-range { display: grid; gap: 0.3rem; font-size: 0.72rem; text-transform: uppercase;
        letter-spacing: 1px; color: #888; }
      .theater-range b { color: #ff6600; font-variant-numeric: tabular-nums; }
      .theater-range input[type="range"] { width: 100%; accent-color: #ff6600; }

      .theater-publish { background: #ff6600; color: #111; border: 0; border-radius: 6px;
        min-height: 40px; padding: 0 1.1rem; font-weight: 700; font-size: 0.78rem;
        text-transform: uppercase; letter-spacing: 1px; cursor: pointer; }
      .theater-publish:hover { background: #ff7d26; }

      .theater-upload { margin-top: 1rem; }
      .theater-transcode { display: flex; align-items: center; gap: 0.75rem; margin-top: 0.5rem; }
      .theater-transcode .cms-progress { flex: 1; margin-top: 0; }

      .theater-status { text-transform: uppercase; letter-spacing: 1px; font-size: 0.7rem; }
      .theater-status.is-ready { color: #4ade80; }
      .theater-status.is-failed { color: #f87171; }
      .theater-status.is-processing, .theater-status.is-pending { color: #fbbf24; }

      @media (max-width: 640px) {
        .theater-row { grid-template-columns: 1fr; }
        .theater-devices { margin-left: 0; }
      }
    </style>
    """
  end
end
