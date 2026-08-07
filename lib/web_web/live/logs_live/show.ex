defmodule WebWeb.LogsLive.Show do
  use WebWeb, :live_view

  alias Web.Audio
  alias Web.Audio.Log
  import WebWeb.LogsLive.Format

  @moduledoc """
  A single captain's log at its own address, so a spoken piece can be linked
  to and shared the way a blog post can. Unpublished logs 404 rather than
  leaking a draft to anyone holding the URL.
  """

  def mount(%{"slug" => slug}, _session, socket) do
    # Unpublished and unknown slugs alike 404 rather than leak a draft.
    log =
      case Audio.get_published_log_by_slug(slug) do
        {:ok, log} -> log
        {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Log
      end

    {:ok,
     socket
     |> assign(:page_title, log.title)
     # Its own social card and canonical URL, so a shared log link is not
     # indistinguishable from every other page on the site.
     |> assign(:og_title, log.title)
     |> assign(:og_description, presence(log.description) || "A captain's log recording.")
     |> assign(:og_type, "article")
     |> assign(:canonical_path, ~p"/logs/#{log.slug}")
     |> assign(:log, log)
     |> assign(:play_count, Audio.get_play_count(log.id))}
  end

  # The id in the payload is attacker-controlled and this page has exactly one
  # log in scope, so ignore it and count against the mounted log. The old
  # String.to_integer/1 on that value crashed the LiveView on any non-numeric
  # input, and an unknown id tripped the audio_plays foreign key.
  def handle_event("track_play", _params, socket) do
    log = socket.assigns.log
    Audio.record_play(log.id, client_ip(socket))
    {:noreply, assign(socket, :play_count, Audio.get_play_count(log.id))}
  end

  defp client_ip(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: address} when is_tuple(address) -> address |> :inet.ntoa() |> to_string()
      _ -> "unknown"
    end
  end

  def render(assigns) do
    ~H"""
    <div class="logs-wrapper nx01">
      <div class="console-frame">
        <div class="console-rail">
          <span class="rail-tag">Recording</span>
          <span class="rail-hazard" aria-hidden="true"></span>
        </div>

        <div class="status-strip">
          <div class="status-cell">
            <span class="status-label">Recorded</span>
            <span class="status-value">
              {Calendar.strftime(@log.recorded_on, "%B %-d, %Y")}
            </span>
          </div>
          <div class="status-cell">
            <span class="status-label">Length</span>
            <span class="status-value">{format_duration(@log.duration) || "—"}</span>
          </div>
          <div class="status-cell">
            <span class="status-label">Plays</span>
            <span class="status-value">{@play_count}</span>
          </div>
        </div>

        <article class="log-panel">
          <header class="log-panel-header">
            <h1 class="log-panel-title">{@log.title}</h1>

            <div class="log-audio-bezel">
              <audio
                id={"audio-player-#{@log.id}"}
                class="log-audio"
                controls
                preload="metadata"
                src={@log.file_path}
                phx-hook="AudioPlayTracker"
                data-log-id={@log.id}
              >
              </audio>
            </div>
          </header>

          <div :if={presence(@log.description)} class="log-panel-body">
            <p class="log-panel-desc">{@log.description}</p>
          </div>

          <footer :if={Log.keyword_list(@log) != []} class="log-panel-keywords">
            <span class="logs-label">Filed under</span>
            <div class="logs-options">
              <.link
                :for={keyword <- Log.keyword_list(@log)}
                navigate={logs_path("recent", keyword)}
                class="logs-tag"
              >
                {keyword}
              </.link>
            </div>
          </footer>
        </article>
      </div>
    </div>
    """
  end
end
