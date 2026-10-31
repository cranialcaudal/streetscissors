defmodule WebWeb.AdminLive.Readers do
  @moduledoc """
  Top readers and where they are reading from (`/admin/readers`).

  Groups `analytics_hits` by visitor (`ip_hash`) and resolves or guesses each
  visitor's geographic location without storing raw IP addresses in the
  database:

    * **GeoIP (`:geo`)** — matched in memory against recent Caddy access logs
      and resolved to city, region, country, and ISP in `reader_geo_cache.json`.
    * **Guessed (`:inferred`)** — when a visitor predates the active access log
      window, estimated from their UTC active-hour timezone pattern and whether
      they read the author's local pages (training days and rides).
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Analytics

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok,
       socket
       |> assign(page_title: "Readers | Admin", show: "readers")
       |> load()}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_params(params, _uri, socket) do
    show =
      case params["show"] do
        "all" -> "all"
        "bots" -> "bots"
        _ -> "readers"
      end

    {:noreply, assign(socket, :show, show)}
  end

  def handle_event("forget", %{"hash" => ip_hash}, socket) do
    {deleted, _} = Analytics.forget_reader(ip_hash)
    badge = String.slice(ip_hash, 0, 6)

    {:noreply,
     socket
     |> load()
     |> put_flash(:info, "Removed #{deleted} #{plural(deleted, "view")} for ##{badge}.")}
  end

  def handle_event("refresh_geo", _params, socket) do
    case Analytics.refresh_geo_cache() do
      {:ok, 0} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(:info, "All access-log visitors are already resolved.")}

      {:ok, count} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(:info, "Resolved #{count} new visitor #{plural(count, "location")} from access logs.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not reach GeoIP service just now.")}
    end
  end

  defp load(socket) do
    all = Analytics.top_readers(filter: :all, limit: 150)
    readers = Enum.reject(all, & &1.bot_burst?)
    bots = Enum.filter(all, & &1.bot_burst?)

    assign(socket,
      all_visitors: all,
      readers: readers,
      bots: bots
    )
  end

  defp plural(1, word), do: word
  defp plural(_n, word), do: word <> "s"

  defp format_date(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> Web.Clock.local_today()
    |> Calendar.strftime("%b %-d, %Y")
  end

  def render(assigns) do
    shown =
      case assigns.show do
        "all" -> assigns.all_visitors
        "bots" -> assigns.bots
        _ -> assigns.readers
      end

    assigns = assign(assigns, :shown, shown)

    ~H"""
    <.page_head slug="Studio / Readers" title="Readers">
      <:lede>
        Who is reading the site and where they are coming from. Locations are matched in memory
        against Caddy access logs when available, or guessed from active-hour timezone patterns
        and local reading habits when older than the log window.
      </:lede>
      <:actions>
        <button type="button" phx-click="refresh_geo" class="adm-btn">
          Scan logs &amp; resolve locations
        </button>
      </:actions>
    </.page_head>

    <.panel title="Top readers" count={length(@shown)}>
      <.tabs label="Visitor filter">
        <:tab
          patch={~p"/admin/readers"}
          active={@show == "readers"}
          count={length(@readers)}
        >
          Readers
        </:tab>
        <:tab
          patch={~p"/admin/readers?show=all"}
          active={@show == "all"}
          count={length(@all_visitors)}
        >
          All visitors
        </:tab>
        <:tab
          patch={~p"/admin/readers?show=bots"}
          active={@show == "bots"}
          count={length(@bots)}
        >
          Bot bursts
        </:tab>
      </.tabs>

      <.empty :if={@shown == []}>
        No visitors recorded in this view yet.
      </.empty>

      <div :if={@shown != []} class="adm-list adm-list--desk" id="readers-list">
        <article
          :for={r <- @shown}
          id={"reader-#{r.badge}"}
          class="adm-item"
        >
          <div class="adm-item-main">
            <h2 class="adm-item-title">
              <code>#{r.badge}</code> · {r.location.label}
            </h2>

            <div class="adm-item-meta">
              <.pill :if={r.location.kind == :geo} tone="live">GeoIP</.pill>
              <.pill :if={r.location.kind == :inferred} tone="held">Guessed</.pill>
              <.pill :if={r.bot_burst?} tone="fail">Bot burst</.pill>
              <.pill :if={r.location.mobile?} tone="neutral">Mobile</.pill>
              <span>{r.location.detail}</span>
            </div>

            <div class="adm-item-meta">
              <span>
                <span class="adm-figure">{r.total_hits}</span> {plural(r.total_hits, "view")}
              </span>
              <span>
                <span class="adm-figure">{r.active_days}</span> {plural(r.active_days, "day")}
              </span>
              <span>
                <span class="adm-figure">{r.distinct_pages}</span> {plural(r.distinct_pages, "page")}
              </span>
              <span>{Enum.join(r.devices, ", ")}</span>
              <span>Source: {Enum.join(r.sources, ", ")}</span>
              <span>
                {format_date(r.first_seen)} – {format_date(r.last_seen)}
              </span>
            </div>

            <div class="adm-item-meta">
              <span :for={{path, count} <- r.top_pages}>
                <a href={path} class="adm-link">{path}</a>
                (<span class="adm-figure">{count}</span>)
              </span>
            </div>
          </div>

          <div class="adm-item-actions">
            <button
              type="button"
              phx-click="forget"
              phx-value-hash={r.ip_hash}
              data-confirm={"Remove all #{r.total_hits} views for ##{r.badge} from the count?"}
              class="adm-btn adm-btn--small adm-btn--quiet"
            >
              Remove from count
            </button>
          </div>
        </article>
      </div>
    </.panel>
    """
  end
end
