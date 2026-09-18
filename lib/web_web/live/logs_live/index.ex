defmodule WebWeb.LogsLive.Index do
  use WebWeb, :live_view

  alias Web.Audio
  alias Web.Audio.Log
  alias WebWeb.LogEntry
  import WebWeb.Navigation, only: [return_context: 1]
  import WebWeb.LogsLive.Format

  @moduledoc """
  The captain's logs index: recordings made under way, video and audio alike.

  Shaped like the rides archive — the newest entry in view owns the first
  screen, everything else is one chronological run beneath it, and the years
  are a footnote. Sort and keyword filter both live in the URL
  (`?sort=witnessed&keyword=nyc`) so any view of the archive can be linked to.
  "Witnessed" for a log means plays.

  One read in `mount/3`, filtering in `handle_params/3` against the list
  already in memory, so a sort or filter click is a patch that costs no query.

  **No card mounts a player.** Opening this page fetches posters and nothing
  else; the media is only reached from an entry's own page.
  """

  def mount(params, _session, socket) do
    {return_to, return_label} = return_context(Map.get(params, "from"))

    {:ok,
     socket
     |> assign(:page_title, "Captain's Logs")
     |> assign(:return_to, return_to)
     |> assign(:return_label, return_label)
     |> assign(:client_ip, client_ip(socket))
     |> assign(:play_counts, Audio.get_all_play_counts())
     |> assign(:keywords, Audio.list_keywords())
     |> assign(:logs, Audio.list_ready_logs())
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
        Audio.record_play(log_id, socket.assigns.client_ip)

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

  # Captured at mount and kept in assigns: connect_info is only readable while
  # mounting, and reaching for it from handle_event/3 raises — which is what
  # the first real play on this page would have done.
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

  # list_ready_logs/0 already returns newest recording first, so "recent" is
  # the identity and only "witnessed" has to re-order. The featured entry is
  # whatever leads the current view, so it follows the sort and the filter.
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

    socket
    |> assign(:visible_logs, visible)
    |> assign(:featured, List.first(visible))
    # The featured entry keeps its place in the run below, so the count in the
    # readout and the rows on the page never disagree.
    |> assign(:years, Audio.yearly_totals(visible))
    |> assign(:runtime, Audio.total_runtime(visible))
  end

  defp plays(socket_play_counts, log), do: Map.get(socket_play_counts, log.id, 0)

  def render(assigns) do
    ~H"""
    <div class="logs-wrapper nx01">
      <article class="console-frame">
        <div class="console-rail">
          <span class="rail-tag">NX-01</span>
          <span class="rail-hazard" aria-hidden="true"></span>
          <span :if={@visible_logs != []} class="rail-readout">
            {length(@visible_logs)} on file
          </span>
        </div>

        <header class="console-head">
          <h1 class="logs-title">Captain's Logs</h1>
          <p class="logs-bio">Recorded under way</p>
        </header>

        <dl class="status-strip">
          <div class="status-cell">
            <dt>Entries</dt>
            <dd>{length(@visible_logs)}</dd>
          </div>
          <div class="status-cell">
            <dt>Runtime</dt>
            <dd>{format_runtime(@runtime)}</dd>
          </div>
          <div class="status-cell">
            <dt>Witnessed</dt>
            <dd>{@total_plays}</dd>
          </div>
        </dl>

        <nav class="console-bank" aria-label="Sort">
          <span class="bank-label">Sort</span>
          <.link
            patch={logs_path("recent", @keyword)}
            class={["console-btn", @sort == "recent" && "is-active"]}
            aria-current={@sort == "recent" && "true"}
          >
            Most recent
          </.link>
          <.link
            patch={logs_path("witnessed", @keyword)}
            class={["console-btn", @sort == "witnessed" && "is-active"]}
            aria-current={@sort == "witnessed" && "true"}
          >
            Most witnessed
          </.link>
        </nav>

        <nav :if={@keywords != []} class="console-bank" aria-label="Filter by keyword">
          <span class="bank-label">Filter</span>
          <.link
            patch={logs_path(@sort, nil)}
            class={["console-tab", is_nil(@keyword) && "is-active"]}
            aria-current={is_nil(@keyword) && "true"}
          >
            All
          </.link>
          <.link
            :for={{keyword, count} <- @keywords}
            patch={logs_path(@sort, keyword)}
            class={["console-tab", @keyword == keyword && "is-active"]}
            aria-current={@keyword == keyword && "true"}
          >
            {keyword} <span class="tab-count">{count}</span>
          </.link>
        </nav>

        <%!-- The theater: whatever leads the current view owns the first screen. --%>
        <section :if={@featured} class="log-feature">
          <LogEntry.meta log={@featured} />
          <h2 class="log-feature-title">
            <.link navigate={~p"/logs/#{@featured.slug}"}>{LogEntry.title(@featured)}</.link>
          </h2>
          <p :if={presence(@featured.caption)} class="log-feature-caption">
            {@featured.caption}
          </p>
          <LogEntry.plate log={@featured} />
          <LogEntry.figures log={@featured} plays={plays(@play_counts, @featured)} />
        </section>

        <section :if={length(@visible_logs) > 1} class="log-feed" aria-label="The archive">
          <h2 class="log-feed-head">
            The archive <span class="log-feed-count">{length(@visible_logs)}</span>
          </h2>
          <LogEntry.card
            :for={log <- Enum.drop(@visible_logs, 1)}
            log={log}
            plays={plays(@play_counts, log)}
          />
        </section>

        <p :if={@visible_logs == []} class="log-empty">
          <span :if={@keyword}>Nothing filed under “{@keyword}”.</span>
          <span :if={is_nil(@keyword)}>No logs yet. The first recording will appear here.</span>
        </p>

        <footer :if={@years != []} class="log-totals">
          <p :for={year <- @years}>{totals_line(year)}</p>
        </footer>
      </article>
    </div>
    """
  end
end
