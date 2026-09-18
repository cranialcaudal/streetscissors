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
    <div
      id={@id}
      class={["log-plate", "log--#{@log.kind}", is_nil(@poster) && "log-plate--blank"]}
      phx-hook=".LogPlayer"
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
        hidden
      >
      </video>

      <audio :if={@log.kind == "audio"} class="log-audio" preload="none" controls hidden></audio>

      <img :if={@poster} class="log-poster" src={@poster} alt="" loading="lazy" />
      <div :if={is_nil(@poster)} class="log-poster log-poster--none" aria-hidden="true">
        {kind_label(@log)}
      </div>

      <button :if={@src} type="button" class="log-play" aria-label={"Play #{title(@log)}"}>
        <span class="log-play-mark" aria-hidden="true"></span>
      </button>

      <p :if={is_nil(@src)} class="log-plate-pending">Still processing</p>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".LogPlayer">
      // Nothing is fetched until the play button is pressed — not the media,
      // not the player. Safari and iOS play HLS natively from a plain src;
      // everyone else gets hls.js, which is a dynamic import so it only ever
      // reaches a browser that is about to watch something.
      //
      // Vendored: hls.js 1.6.15, light build (assets/vendor/hls.light.min.js).
      export default {
        mounted() {
          this.media = this.el.querySelector("video, audio")
          this.button = this.el.querySelector(".log-play")
          this.hls = null
          this.counted = false

          if (this.button) {
            this.button.addEventListener("click", () => this.start())
          }

          if (this.media) {
            // One play per mount, so scrubbing back and forth is not a crowd.
            this.media.addEventListener("play", () => {
              if (this.counted) return
              this.counted = true
              this.pushEvent("track_play", { id: this.el.dataset.logId })
            })
          }
        },

        async start() {
          const src = this.el.dataset.src
          if (!src || !this.media || this.el.classList.contains("is-playing")) return

          this.el.classList.add("is-playing")
          this.media.hidden = false

          if (this.el.dataset.kind !== "video") {
            this.media.src = src
          } else {
            // hls.js first, native second — deliberately, and not the other
            // way round. Desktop Chrome answers canPlayType("…mpegurl") with
            // "maybe", which is truthy but not a promise: HLS is not a
            // supported feature there, and trusting it means a silently dead
            // player on the builds where it does not work. iOS Safari, which
            // genuinely needs the native path, reports isSupported() as false
            // because it has no MSE for video — so it falls through here on
            // its own, with no user-agent sniffing.
            try {
              const { default: Hls } = await import("@/vendor/hls.light.min.js")
              if (Hls.isSupported()) {
                this.hls = new Hls({
                  enableWorker: true,
                  // Read ahead by a listenable amount and no more. The point
                  // of segmenting at all is that someone who opens a
                  // twenty-minute log and watches two minutes of it costs two
                  // minutes of bandwidth. backBufferLength then drops what
                  // has already played, so a long recording does not grow in
                  // memory for the whole of its runtime.
                  maxBufferLength: 20,
                  maxBufferSize: 20 * 1000 * 1000,
                  backBufferLength: 30
                })
                this.hls.loadSource(src)
                this.hls.attachMedia(this.media)
              } else {
                this.media.src = src
              }
            } catch (_error) {
              // If the chunk cannot be fetched at all, a direct src is still
              // worth trying — it is what Safari would have used anyway.
              this.media.src = src
            }
          }

          this.media.play().catch(() => {})
        },

        destroyed() {
          if (this.hls) this.hls.destroy()
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
