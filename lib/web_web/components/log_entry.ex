defmodule WebWeb.LogEntry do
  @moduledoc """
  The pieces a captain's log is drawn with, on the index and on its own page.

  In the manner of `WebWeb.Activity` for the rides archive: a kicker line, a
  figures panel, a plate for the media, and a card for the feed. Everything
  reads in the console's vocabulary — an entry is titled by its date, marked
  by its ordinal when it shares a day.

  The plate is the load-bearing part. Nothing about a video is fetched until
  someone presses play: the `<video>` carries `preload="none"` and a poster,
  and the player library itself is a dynamic import, so an index of forty
  entries costs forty thumbnails and no video at all.
  """

  use WebWeb, :html

  alias Web.Audio.Log

  import WebWeb.LogsLive.Format

  @doc "An entry's title: the day it was recorded."
  def title(log), do: Log.title(log)

  attr :log, :map, required: true

  @doc "The kicker above a plate: what it is and when it was made."
  def meta(assigns) do
    ~H"""
    <p class={["log-meta", "log--#{@log.kind}"]}>
      <span class="log-kind">{kind_label(@log)}</span>
      <span class="log-meta-dot" aria-hidden="true">•</span>
      <span>{Calendar.strftime(@log.recorded_on, "%a %-d %b %Y")}</span>
      <span :if={Log.ordinal(@log)} class="log-meta-dot" aria-hidden="true">•</span>
      <span :if={Log.ordinal(@log)} class="log-ordinal">
        Entry {Log.ordinal(@log)}
      </span>
    </p>
    """
  end

  attr :log, :map, required: true
  attr :plays, :integer, default: 0

  @doc """
  The readout under a plate. Four cells, caption under value — the markup
  puts the label first and the CSS flips it, so the reading order stays
  sensible for a screen reader.
  """
  def figures(assigns) do
    assigns = assign(assigns, :figures, figure_list(assigns.log, assigns.plays))

    ~H"""
    <dl class="log-figures">
      <div :for={{label, value} <- @figures} class="log-figure">
        <dt class="log-figure-label">{label}</dt>
        <dd class="log-figure-value">{value}</dd>
      </div>
    </dl>
    """
  end

  defp figure_list(log, plays) do
    [
      {"Recorded", Calendar.strftime(log.recorded_on, "%-d %b %Y")},
      {"Length", format_duration(log.duration) || "—"},
      {"Witnessed", to_string(plays)}
    ]
  end

  defp kind_label(%{kind: "audio"}), do: "Audio log"
  defp kind_label(_log), do: "Video log"

  attr :log, :map, required: true
  attr :id, :string, default: nil

  @doc """
  The theater: a dark plate holding the poster, and the media once asked for.

  Under `.nx01` the `--ink` tokens are *light*, so everything meant to stay
  dark in here keys off `--paper-*`. See the warning at the top of logs.css.
  """
  def plate(assigns) do
    # assign_new/3 is no use here: `attr :id` has already put the key in
    # assigns with a nil value, so there is nothing for it to fill in.
    assigns =
      assigns
      |> assign(:id, assigns.id || "log-plate-#{assigns.log.id}")
      |> assign(:src, Log.media_url(assigns.log))
      |> assign(:poster, Log.poster_url(assigns.log))

    ~H"""
    <%!-- phx-update="ignore": the hook owns everything in here once it
          mounts. LiveView then merges only data-* attributes onto the plate
          and never touches its class or children, so no patch — counting a
          witness is one — can reset a running player or its state. --%>
    <div
      id={@id}
      class={["log-plate", "log--#{@log.kind}", is_nil(@poster) && "log-plate--blank"]}
      phx-hook=".LogPlayer"
      phx-update="ignore"
      data-log-id={@log.id}
      data-src={@src}
      data-kind={@log.kind}
      style={@log.width && @log.height && "--plate-ratio: #{@log.width} / #{@log.height}"}
    >
      <video
        :if={@log.kind == "video"}
        class="log-video"
        poster={@poster}
        preload="none"
        playsinline
        controls
      >
      </video>

      <audio :if={@log.kind == "audio"} class="log-audio" preload="none" controls></audio>

      <img :if={@poster} class="log-poster" src={@poster} alt="" loading="lazy" />
      <div :if={is_nil(@poster)} class="log-poster log-poster--none" aria-hidden="true">
        {kind_label(@log)}
      </div>

      <button :if={@src} type="button" class="log-play" aria-label={"Play #{title(@log)}"}>
        <span class="log-play-mark" aria-hidden="true"></span>
      </button>

      <div :if={@src} class="log-plate-error" role="alert" hidden>
        <p>Couldn't play this recording.</p>
        <div class="log-plate-error-actions">
          <button type="button" class="log-retry">Try again</button>
          <a class="log-file" href={@src} target="_blank" rel="noopener">Open the file</a>
        </div>
      </div>

      <p :if={is_nil(@src)} class="log-plate-pending">Still processing</p>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".LogPlayer">
      // One progressive file, played by the browser's own <video>/<audio>.
      // Nothing is fetched until the key is pressed (preload="none").
      //
      // The plate's state is a class — is-loading, is-playing, is-error —
      // and it only ever says what the media element has actually reported:
      // "playing" waits for the element's own `playing` event, not the click.
      export default {
        mounted() {
          this.media = this.el.querySelector("video, audio")
          this.button = this.el.querySelector(".log-play")
          this.error = this.el.querySelector(".log-plate-error")
          this.state = "idle"
          this.watchdog = null
          this.counted = false
          this.watched = 0
          this.lastTime = null

          if (this.button) this.button.addEventListener("click", () => this.start())

          const retry = this.el.querySelector(".log-retry")
          if (retry) retry.addEventListener("click", () => this.start({ reload: true }))

          if (!this.media) return

          this.media.addEventListener("playing", () => this.setState("playing"))
          this.media.addEventListener("waiting", () => {
            if (this.state === "playing") this.el.classList.add("is-buffering")
          })
          this.media.addEventListener("error", () => this.setState("error"))

          // A witness is someone who watched, not someone who pressed play:
          // count only time that actually played — small forward steps
          // between timeupdates, so a seek or scrub adds nothing — and send
          // it once, when 30 seconds have played (half the entry, if it is
          // shorter than a minute). The server keeps one row per browser.
          this.media.addEventListener("timeupdate", () => this.tally())
          this.media.addEventListener("seeking", () => { this.lastTime = null })
        },

        setState(state) {
          this.state = state
          this.el.classList.toggle("is-loading", state === "loading")
          this.el.classList.toggle("is-playing", state === "playing")
          this.el.classList.toggle("is-error", state === "error")
          this.el.classList.remove("is-buffering")

          if (state === "loading") this.el.setAttribute("aria-busy", "true")
          else this.el.removeAttribute("aria-busy")

          if (this.error) this.error.hidden = state !== "error"
          if (state !== "loading") clearTimeout(this.watchdog)
        },

        // Synchronous on purpose. Safari only lets play() start sound when it
        // is called inside the click itself; the old start awaited a player
        // library first, and Safari quietly refused. Nothing here awaits.
        start({ reload = false } = {}) {
          const src = this.el.dataset.src
          if (!src || !this.media) return
          if (this.state === "loading" || this.state === "playing") return

          this.setState("loading")

          if (!this.media.getAttribute("src")) {
            this.media.src = src
          } else if (reload) {
            // Pick up where it failed rather than from the top.
            const at = this.media.currentTime
            this.media.load()
            if (at > 0) {
              this.media.addEventListener("loadedmetadata", () => { this.media.currentTime = at }, { once: true })
            }
          }

          // Still nothing after 15 seconds is a failure worth saying so about,
          // with a way to try again, rather than a key that just sits there.
          this.watchdog = setTimeout(() => {
            if (this.state === "loading") this.setState("error")
          }, 15000)

          const attempt = this.media.play()
          if (attempt) {
            attempt.catch((error) => {
              // Superseded by a newer load or play — not a failure.
              if (error.name === "AbortError") return
              // The browser refused to start without a fresh press: back to
              // the key, which is exactly that press.
              if (error.name === "NotAllowedError") return this.setState("idle")
              this.setState("error")
            })
          }
        },

        tally() {
          if (this.state === "playing") this.el.classList.remove("is-buffering")

          const now = this.media.currentTime
          if (this.lastTime !== null && !this.media.paused) {
            const step = now - this.lastTime
            if (step > 0 && step < 1.5) this.watched += step
          }
          this.lastTime = now

          if (this.counted) return
          const duration = this.media.duration
          const needed = isFinite(duration) && duration > 0 ? Math.min(30, duration / 2) : 30
          if (this.watched < needed) return

          this.counted = true
          this.pushEvent("track_play", { id: this.el.dataset.logId, witness: this.witness() })
        },

        // An anonymous token this browser keeps for itself — random, and
        // nothing about the person. If storage is blocked it lasts the page.
        witness() {
          const key = "streetscissors_witness"
          const fresh = () =>
            (crypto.randomUUID && crypto.randomUUID()) ||
            Array.from(crypto.getRandomValues(new Uint8Array(16)), (b) =>
              b.toString(16).padStart(2, "0")
            ).join("")

          try {
            let token = localStorage.getItem(key)
            if (!token) {
              token = fresh()
              localStorage.setItem(key, token)
            }
            return token
          } catch (_error) {
            this.pageWitness = this.pageWitness || fresh()
            return this.pageWitness
          }
        },

        destroyed() {
          clearTimeout(this.watchdog)
        }
      }
    </script>
    """
  end

  attr :log, :map, required: true
  attr :plays, :integer, default: 0

  @doc """
  One row of the feed. The whole card is a link, so every child is a span —
  and it holds no player at all, which is what keeps the index cheap.
  """
  def card(assigns) do
    assigns = assign(assigns, :poster, Log.poster_url(assigns.log))

    ~H"""
    <.link navigate={~p"/logs/#{@log.slug}"} class={["log-card", "log--#{@log.kind}"]}>
      <span class="log-card-plate">
        <img :if={@poster} src={@poster} alt="" loading="lazy" />
        <span :if={is_nil(@poster)} class="log-card-blank">{kind_label(@log)}</span>
        <span :if={format_duration(@log.duration)} class="log-card-length">
          {format_duration(@log.duration)}
        </span>
      </span>
      <span class="log-card-body">
        <span class="log-card-title">{title(@log)}</span>
        <span :if={Log.ordinal(@log)} class="log-card-ordinal">Entry {Log.ordinal(@log)}</span>
        <span :if={presence(@log.caption)} class="log-card-caption">{@log.caption}</span>
        <span class="log-card-stats">{kind_label(@log)} · {@plays} witnessed</span>
      </span>
    </.link>
    """
  end
end
