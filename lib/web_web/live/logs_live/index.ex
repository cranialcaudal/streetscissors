defmodule WebWeb.LogsLive.Index do
  use WebWeb, :live_view

  alias Web.Audio
  alias Web.Audio.Log
  import WebWeb.Navigation, only: [return_context: 1]
  import WebWeb.LogsLive.Format

  @moduledoc """
  The captain's logs index: spoken work, decoupled from the blog.

  Sort and keyword filter both live in the URL (`?sort=witnessed&keyword=nyc`)
  so any view of the archive can be linked to. "Witnessed" for a log means
  plays, recorded by the `AudioPlayTracker` hook.
  """

  def mount(params, _session, socket) do
    {return_to, return_label} = return_context(Map.get(params, "from"))

    {:ok,
     socket
     |> assign(:page_title, "Captain's Logs")
     |> assign(:return_to, return_to)
     |> assign(:return_label, return_label)
     |> assign(:play_counts, Audio.get_all_play_counts())
     |> assign(:keywords, Audio.list_keywords())
     |> assign(:logs, Audio.list_published_logs())
     |> assign_total_plays()}
  end

  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:sort, parse_sort(params["sort"]))
     |> assign(:keyword, filter_keyword(params["keyword"]))
     |> assign_visible()}
  end

  # `id` arrives from the socket, so it is attacker-controlled: parse it
  # defensively and only count a play for a log actually on this page. The old
  # String.to_integer/1 raised on any non-numeric value, and an unknown id hit
  # the audio_plays foreign key — either one crashed the LiveView.
  def handle_event("track_play", %{"id" => id}, socket) do
    case play_target(socket, id) do
      nil ->
        {:noreply, socket}

      log_id ->
        Audio.record_play(log_id, client_ip(socket))

        {:noreply,
         socket
         |> assign(:play_counts, Audio.get_all_play_counts())
         |> assign_total_plays()
         |> assign_visible()}
    end
  end

  defp play_target(socket, id) when is_binary(id) do
    case Integer.parse(id) do
      {log_id, ""} -> if Enum.any?(socket.assigns.logs, &(&1.id == log_id)), do: log_id
      _ -> nil
    end
  end

  defp play_target(_socket, _id), do: nil

  # Only counts plays of logs actually on this page, so the readout can never
  # exceed what the archive below it accounts for.
  defp assign_total_plays(socket) do
    %{logs: logs, play_counts: play_counts} = socket.assigns
    assign(socket, :total_plays, Enum.sum_by(logs, &Map.get(play_counts, &1.id, 0)))
  end

  defp client_ip(socket) do
    case get_connect_info(socket, :peer_data) do
      %{address: address} when is_tuple(address) -> address |> :inet.ntoa() |> to_string()
      _ -> "unknown"
    end
  end

  # Total functions: an unknown value falls back to the default rather than
  # crashing on a hand-edited URL.
  defp parse_sort("witnessed"), do: "witnessed"
  defp parse_sort(_), do: "recent"

  defp filter_keyword(nil), do: nil

  defp filter_keyword(raw) do
    case Web.Keywords.normalize(raw) do
      "" -> nil
      keyword -> keyword
    end
  end

  # list_published_logs/0 already returns newest recording first, so "recent"
  # is the identity and only "witnessed" has to re-order.
  defp assign_visible(socket) do
    %{logs: logs, play_counts: play_counts, sort: sort, keyword: keyword} = socket.assigns

    visible =
      logs
      |> Enum.filter(&Web.Keywords.match?(Log.keyword_list(&1), keyword))
      |> then(fn filtered ->
        case sort do
          "witnessed" -> Enum.sort_by(filtered, &Map.get(play_counts, &1.id, 0), :desc)
          _ -> filtered
        end
      end)

    assign(socket, :visible_logs, visible)
  end

  def render(assigns) do
    ~H"""
    <div class="logs-wrapper nx01">
      <div class="console-frame">
        <div class="console-rail">
          <span class="rail-tag">Audio Archive</span>
          <span class="rail-hazard" aria-hidden="true"></span>
        </div>

        <header class="console-head">
          <h1 class="logs-title">Captain's Logs</h1>
          <p class="logs-bio">
            Audio recordings, filed by keyword. Written work is in the <.link navigate={~p"/blog"}>blog</.link>.
          </p>
        </header>

        <div class="status-strip">
          <div class="status-cell">
            <span class="status-label">Recordings</span>
            <span class="status-value">{length(@logs)}</span>
          </div>
          <div class="status-cell">
            <span class="status-label">Plays</span>
            <span class="status-value">{@total_plays}</span>
          </div>
        </div>

        <div class="console-bank">
          <span class="bank-label">Sort</span>
          <div class="bank-buttons">
            <.link
              patch={logs_path("recent", @keyword)}
              class={["console-btn", @sort == "recent" && "active"]}
            >
              Most Recent
            </.link>
            <.link
              patch={logs_path("witnessed", @keyword)}
              class={["console-btn", @sort == "witnessed" && "active"]}
            >
              Most Witnessed
            </.link>
          </div>
        </div>

        <div :if={@keywords != []} class="console-bank">
          <span class="bank-label">Filter</span>
          <div class="bank-buttons">
            <.link
              patch={logs_path(@sort, nil)}
              class={["console-tab", is_nil(@keyword) && "active"]}
            >
              All
            </.link>
            <.link
              :for={{keyword, count} <- @keywords}
              patch={logs_path(@sort, keyword)}
              class={["console-tab", @keyword == keyword && "active"]}
            >
              {keyword} <span class="tab-count">{count}</span>
            </.link>
          </div>
        </div>

        <div class="logs-feed">
          <article :for={log <- @visible_logs} class="log-card" id={"log-#{log.id}"}>
            <div class="log-card-rail">
              <span class="log-desig">{Calendar.strftime(log.recorded_on, "%B %-d, %Y")}</span>
              <span class="log-rail-spacer"></span>
              <span :if={format_duration(log.duration)}>{format_duration(log.duration)}</span>
            </div>

            <div class="log-card-body">
              <h2 class="log-card-title">
                <.link navigate={~p"/logs/#{log.slug}"}>{log.title}</.link>
              </h2>

              <div class="log-meta">
                <span class="log-meta-item">
                  <span class="log-meta-label">Plays</span>
                  {Map.get(@play_counts, log.id, 0)} plays
                </span>
              </div>

              <p :if={presence(log.description)} class="log-desc">{log.description}</p>

              <div class="log-audio-bezel">
                <audio
                  id={"audio-player-#{log.id}"}
                  class="log-audio"
                  controls
                  preload="metadata"
                  src={log.file_path}
                  phx-hook="AudioPlayTracker"
                  data-log-id={log.id}
                >
                </audio>
              </div>

              <div :if={Log.keyword_list(log) != []} class="log-keywords">
                <.link
                  :for={keyword <- Log.keyword_list(log)}
                  patch={logs_path(@sort, keyword)}
                  class="logs-tag"
                >
                  {keyword}
                </.link>
              </div>
            </div>
          </article>

          <div :if={@visible_logs == []} class="log-empty">
            <%= if @keyword do %>
              <span class="log-empty-code">Nothing found</span>
              No recordings filed under “{@keyword}”.
            <% else %>
              <span class="log-empty-code">Empty</span> No recordings yet.
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
