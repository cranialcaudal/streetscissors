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

  def mount(params, session, socket) do
    {return_to, return_label} = return_context(Map.get(params, "from"))

    {:ok,
     socket
     |> assign(:page_title, "Captain's Logs")
     |> assign(:return_to, return_to)
     |> assign(:return_label, return_label)
     |> assign(:client_ip, client_ip(socket))
     # The admin watching the entries back is not a witness.
     |> assign(:is_admin, session["admin_user"] == true)
     |> assign(:keywords, Audio.list_keywords())
     |> assign(:logs, Audio.list_ready_logs())
     |> assign_witnesses()}
  end

  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:sort, parse_sort(params["sort"]))
     |> assign(:keyword, filter_keyword(params["keyword"]))
     |> assign_keyword_feed()
     |> assign_visible()}
  end

  # `id` arrives from the socket, so it is attacker-controlled: parse it
  # defensively and only count a play for a log actually on this page. The old
  # String.to_integer/1 raised on any non-numeric value, and an unknown id hit
  # the audio_plays foreign key — either one crashed the LiveView. The hook
  # sends this only after 30 seconds have actually played; `witness` is the
  # browser's own token, checked in Audio.record_play/4.
  def handle_event("track_play", _params, %{assigns: %{is_admin: true}} = socket),
    do: {:noreply, socket}

  def handle_event("track_play", %{"id" => id} = params, socket) do
    case play_target(socket, id) do
      nil ->
        {:noreply, socket}

      log_id ->
        Audio.record_play(log_id, params["witness"], socket.assigns.client_ip)

        # The readouts move; the running order does not. Re-sorting here
        # would let watching something reorder the page underneath the
        # watcher — and under "most witnessed" it would pull the entry you
        # just started out of the theater mid-play. The order settles on the
        # next patch or visit, which is when a reader expects it to.
        {:noreply, assign_witnesses(socket)}
    end
  end

  defp play_target(socket, id) when is_binary(id) do
    case Integer.parse(id) do
      {log_id, ""} -> if Enum.any?(socket.assigns.logs, &(&1.id == log_id)), do: log_id
      _ -> nil
    end
  end

  defp play_target(_socket, _id), do: nil

  # Every figure counts witnesses, not plays: each card is how many people
  # saw that entry, and the console total is how many people saw any entry
  # on this page — a union, so someone who watched three counts once. Only
  # logs actually on this page count, so the readout can never exceed what
  # the archive below it accounts for.
  defp assign_witnesses(socket) do
    witnesses = Audio.witnesses_by_log()

    total =
      socket.assigns.logs
      |> Enum.reduce(MapSet.new(), &MapSet.union(&2, Map.get(witnesses, &1.id, MapSet.new())))
      |> MapSet.size()

    socket
    |> assign(:play_counts, Map.new(witnesses, fn {id, set} -> {id, MapSet.size(set)} end))
    |> assign(:total_plays, total)
  end

  # Captured at mount and kept in assigns: connect_info is only readable while
  # mounting, and reaching for it from handle_event/3 raises — which is what
  # the first real play on this page would have done. Behind Caddy the peer is
  # always the proxy, so the viewer's address comes from x-forwarded-for.
  defp client_ip(socket), do: WebWeb.ClientIP.from_socket(socket)

  # Total functions: an unknown value falls back to the default rather than
  # crashing on a hand-edited URL.
  defp parse_sort("witnessed"), do: "witnessed"
  defp parse_sort(_), do: "recent"

  # Read by the root layout's <link rel="alternate"> on first render; the
  # visible "Follow" link below keeps up with patches.
  defp assign_keyword_feed(%{assigns: %{keyword: nil}} = socket),
    do: assign(socket, :keyword_feed, nil)

  defp assign_keyword_feed(%{assigns: %{keyword: keyword}} = socket),
    do: assign(socket, :keyword_feed, ~p"/feed?keyword=#{keyword}")

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
          <a :if={@keyword_feed} href={@keyword_feed} class="console-follow">
            Follow “{@keyword}” by RSS
          </a>
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
