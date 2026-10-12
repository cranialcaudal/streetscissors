defmodule WebWeb.LogsLive.Show do
  use WebWeb, :live_view

  alias Web.Audio
  alias Web.Audio.Log
  alias WebWeb.LogEntry
  alias WebWeb.SEO
  import WebWeb.LogsLive.Format

  @moduledoc """
  A single captain's log at its own address, so a recording can be linked to
  and shared the way a blog post can.

  Drafts and entries still transcoding 404 here rather than leaking a
  half-built page — `Audio.get_ready_log_by_slug/1` is the one place that
  decides, and the index composes on the same rule.
  """

  def mount(%{"slug" => slug}, session, socket) do
    log =
      case Audio.get_ready_log_by_slug(slug) do
        {:ok, log} -> log
        {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Log
      end

    crumbs = [
      {"Home", ~p"/"},
      {"Captain's Log", ~p"/logs"},
      {Log.title(log), ~p"/logs/#{log.slug}"}
    ]

    json_ld = [
      SEO.media_json_ld(log),
      SEO.breadcrumb_json_ld(crumbs)
    ]

    {:ok,
     socket
     # two recordings of one day share a title: the tab says which this is
     |> assign(
       :page_title,
       if(Log.ordinal(log),
         do: "#{Log.title(log)} · Entry #{Log.ordinal(log)}",
         else: Log.title(log)
       )
     )
     |> assign(:neighbours, neighbours(log))
     # Its own social card and canonical URL, so a shared log link is not
     # indistinguishable from every other page on the site.
     |> assign(:og_title, Log.title(log))
     |> assign(:og_description, og_description(log))
     |> assign(:og_type, "article")
     |> assign(:og_image, Log.poster_url(log))
     |> assign(:canonical_path, ~p"/logs/#{log.slug}")
     |> assign(:json_ld, json_ld)
     |> assign(:log, log)
     |> assign(:client_ip, client_ip(socket))
     # The admin watching the entries back is not a view.
     |> assign(:is_admin, session["admin_user"] == true)
     |> assign(:play_count, Audio.get_play_count(log.id))}
  end

  defp og_description(log) do
    presence(log.description) || presence(log.caption) || "A captain's log recording."
  end

  # The id in the payload is attacker-controlled and this page has exactly one
  # log in scope, so ignore it and count against the mounted log. The old
  # String.to_integer/1 on that value crashed the LiveView on any non-numeric
  # input, and an unknown id tripped the audio_plays foreign key.
  def handle_event("track_play", _params, %{assigns: %{is_admin: true}} = socket),
    do: {:noreply, socket}

  def handle_event("track_play", params, socket) do
    log = socket.assigns.log
    Audio.record_play(log.id, params["witness"], socket.assigns.client_ip)
    {:noreply, assign(socket, :play_count, Audio.get_play_count(log.id))}
  end

  # Captured at mount and kept in assigns: connect_info is only readable while
  # mounting, and reaching for it from handle_event/3 raises — which is what
  # the first real play on this page would have done. Behind Caddy the peer is
  # always the proxy, so the viewer's address comes from x-forwarded-for.
  defp client_ip(socket), do: WebWeb.ClientIP.from_socket(socket)

  def render(assigns) do
    ~H"""
    <div class="logs-wrapper nx01">
      {raw(SEO.page_json_ld_tag(assigns))}
      <article class="console-frame h-entry">
        <WebWeb.Microformats.entry_fields path={~p"/logs/#{@log.slug}"} />
        <div class="console-rail">
          <span class="rail-tag">NX-01</span>
          <span class="rail-hazard" aria-hidden="true"></span>
          <span class="rail-readout">Log {@log.slug}</span>
        </div>

        <header class="console-head">
          <LogEntry.meta log={@log} />
          <h1 class="logs-title p-name">{Log.title(@log)}</h1>
          <p :if={presence(@log.caption)} class="logs-bio p-summary">{@log.caption}</p>
        </header>

        <LogEntry.plate log={@log} />
        <LogEntry.figures log={@log} plays={@play_count} />

        <div :if={presence(@log.description)} class="log-notes">
          <h2 class="log-notes-head">Notes</h2>
          <p>{@log.description}</p>
        </div>

        <footer :if={Log.keyword_list(@log) != []} class="log-filed">
          <span class="bank-label">Filed under</span>
          <.link
            :for={keyword <- Log.keyword_list(@log)}
            navigate={logs_path("recent", keyword)}
            class="console-tab"
          >
            {keyword}
          </.link>
        </footer>

        <%!-- The entry recorded before this one, the one after, and the way
              back to them all. --%>
        <nav class="log-back">
          <.link
            :if={@neighbours.older}
            navigate={~p"/logs/#{@neighbours.older.slug}"}
            class="console-btn"
            rel="prev"
          >
            ‹ Earlier entry
          </.link>
          <.link navigate={~p"/logs"} class="console-btn">All logs</.link>
          <.link
            :if={@neighbours.newer}
            navigate={~p"/logs/#{@neighbours.newer.slug}"}
            class="console-btn"
            rel="next"
          >
            Later entry ›
          </.link>
        </nav>
      </article>

      <%!-- Letters about this log, and the sites that cite it. --%>
      {live_render(@socket, WebWeb.LettersLive,
        id: "letters-log-#{@log.slug}",
        session: %{"piece" => Web.Pieces.log(@log.slug), "remote_ip" => @client_ip}
      )}
    </div>
    """
  end

  # The public entries either side of this one, by when they were recorded.
  defp neighbours(log) do
    all = Web.Audio.list_ready_logs()
    at = Enum.find_index(all, &(&1.id == log.id))

    if at do
      # the list runs newest first
      %{newer: at > 0 && Enum.at(all, at - 1), older: Enum.at(all, at + 1)}
      |> Map.new(fn {k, v} -> {k, v || nil} end)
    else
      %{newer: nil, older: nil}
    end
  end
end
