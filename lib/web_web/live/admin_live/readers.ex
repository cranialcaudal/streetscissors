defmodule WebWeb.AdminLive.Readers do
  @moduledoc """
  Who is reading, and where from (`/admin/readers`).

  Groups `analytics_hits` by visitor (`ip_hash`) and resolves or guesses each
  visitor's location without ever storing an address:

    * **GeoIP (`:geo`)** — the hash matched against the Caddy access log in
      memory and resolved to city, region, country and ISP in
      `reader_geo_cache.json`.
    * **Guessed (`:inferred`)** — for a visitor older than the log on disk,
      estimated from the hours they read at and whether they read the
      author's local pages (training days and rides).

  **Three views, cut separately.** The author, the readers and the bot bursts
  are counted and limited one at a time. Taking the top 150 of everything and
  sorting them out afterwards is what made the page useless: one scraper
  working from 276 addresses filled the list and left no room for anybody
  real.

  **The author is a view, not a deletion.** "This is me" records the hash in
  `Web.Analytics.Owner`, which takes it out of this page and out of every
  figure on the site, and leaves the rows where they are — so a hash marked by
  mistake is one button from being counted again. "Remove from count" still
  deletes, and is meant for a bot burst, where there is nothing to keep.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Analytics
  alias Web.Analytics.Owner

  # Enough to read through, with the three views cut on their own.
  @per_view 60

  @views %{"readers" => :readers, "mine" => :mine, "bots" => :bots, "all" => :all}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Readers | Admin",
       show: "readers",
       profiles: nil,
       candidates: [],
       reading?: false,
       scanning?: false
     )
     |> read()}
  end

  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :show, view_name(params["show"]))}
  end

  def handle_event("mine", %{"hash" => ip_hash}, socket) do
    {:ok, _} = Owner.add(ip_hash, source: "manual")

    {:noreply,
     socket
     |> assign(:candidates, Enum.reject(socket.assigns.candidates, &(&1.hash == ip_hash)))
     |> read()
     |> put_flash(
       :info,
       "##{badge(ip_hash)} is you. Those views are out of every figure on the site, " <>
         "and the visits are still here if you change your mind."
     )}
  end

  def handle_event("not_mine", %{"hash" => ip_hash}, socket) do
    :ok = Owner.remove(ip_hash)

    {:noreply,
     socket
     |> read()
     |> put_flash(:info, "##{badge(ip_hash)} is counted again.")}
  end

  def handle_event("forget", %{"hash" => ip_hash}, socket) do
    {deleted, _} = Analytics.forget_reader(ip_hash)

    {:noreply,
     socket
     |> read()
     |> put_flash(:info, "Deleted #{deleted} #{plural(deleted, "view")} for ##{badge(ip_hash)}.")}
  end

  def handle_event("find_mine", _params, socket) do
    {:noreply, socket |> assign(:scanning?, true) |> start_async(:mine, &Owner.refresh/0)}
  end

  def handle_event("not_a_reader", %{"hash" => ip_hash}, socket) do
    :ok = Owner.dismiss(ip_hash)

    {:noreply,
     socket
     |> assign(:candidates, Enum.reject(socket.assigns.candidates, &(&1.hash == ip_hash)))
     |> put_flash(:info, "##{badge(ip_hash)} will be left as a reader.")}
  end

  def handle_event("refresh_geo", _params, socket) do
    {:noreply,
     socket |> assign(:scanning?, true) |> start_async(:geo, &Analytics.refresh_geo_cache/0)}
  end

  def handle_async(:profiles, {:ok, profiles}, socket) do
    {:noreply, assign(socket, profiles: profiles, reading?: false)}
  end

  def handle_async(:profiles, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(reading?: false, profiles: [])
     |> put_flash(:error, "The visits could not be read: #{inspect(reason)}")}
  end

  def handle_async(:mine, {:ok, {:ok, %{added: added, candidates: _}}}, socket) do
    proposed = Owner.candidates()

    {:noreply,
     socket
     |> assign(scanning?: false, candidates: proposed)
     |> read()
     |> put_flash(:info, mine_found(added, length(proposed)))}
  end

  def handle_async(:mine, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:scanning?, false)
     |> put_flash(:error, "The access log could not be read: #{inspect(reason)}")}
  end

  def handle_async(:geo, {:ok, {:ok, 0}}, socket) do
    {:noreply,
     socket
     |> assign(:scanning?, false)
     |> read()
     |> put_flash(:info, "Every visitor the access log still holds is already resolved.")}
  end

  def handle_async(:geo, {:ok, {:ok, count}}, socket) do
    {:noreply,
     socket
     |> assign(:scanning?, false)
     |> read()
     |> put_flash(:info, "Resolved #{count} new #{plural(count, "location")}.")}
  end

  def handle_async(:geo, {:ok, {:error, _}}, socket) do
    {:noreply,
     socket
     |> assign(:scanning?, false)
     |> put_flash(:error, "Could not reach the GeoIP service just now.")}
  end

  def handle_async(:geo, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:scanning?, false)
     |> put_flash(:error, "The lookup did not finish: #{inspect(reason)}")}
  end

  # Reading every hit and grouping it is not work to do while a page is
  # waiting to render, and the first, static render would throw the result
  # away (the pattern WebWeb.AdminLive.ContentHealth sets).
  defp read(socket) do
    if connected?(socket) do
      socket
      |> assign(:reading?, true)
      |> start_async(:profiles, fn -> Analytics.top_readers(filter: :all, limit: nil) end)
    else
      assign(socket, :reading?, true)
    end
  end

  defp view_name(show) when is_map_key(@views, show), do: show
  defp view_name(_), do: "readers"

  defp badge(ip_hash), do: String.slice(ip_hash, 0, 6)

  defp plural(1, word), do: word
  defp plural(_n, word), do: word <> "s"

  defp mine_found(0, 0), do: "Nothing new: the access log holds no address of yours to settle."

  defp mine_found(added, 0),
    do:
      "Recorded #{added} #{plural(added, "address")} from EXCLUDED_IPS. " <>
        "Nothing in the log needs deciding."

  defp mine_found(_added, found),
    do:
      "#{found} #{plural(found, "address")} in the log answered an admin page. " <>
        "Each one needs your word on whether the visits are yours."

  defp split(nil), do: %{readers: [], mine: [], bots: [], all: []}

  defp split(profiles) do
    {mine, rest} = Enum.split_with(profiles, & &1.mine?)
    {bots, readers} = Enum.split_with(rest, & &1.bot_burst?)

    %{
      readers: Enum.take(readers, @per_view),
      mine: Enum.take(mine, @per_view),
      bots: Enum.take(bots, @per_view),
      all: Enum.take(profiles, @per_view * 2)
    }
  end

  defp counts(nil), do: %{readers: 0, mine: 0, bots: 0, all: 0}

  defp counts(profiles) do
    {mine, rest} = Enum.split_with(profiles, & &1.mine?)
    {bots, readers} = Enum.split_with(rest, & &1.bot_burst?)

    %{
      readers: length(readers),
      mine: length(mine),
      bots: length(bots),
      all: length(profiles)
    }
  end

  defp admin_when(%{admin_first: nil}), do: "an unknown date"

  defp admin_when(%{admin_first: first, admin_last: last}) do
    first_day = first |> Web.Clock.local_today() |> Calendar.strftime("%b %-d, %Y")
    last_day = last |> Web.Clock.local_today() |> Calendar.strftime("%b %-d, %Y")

    if first_day == last_day, do: first_day, else: "#{first_day} – #{last_day}"
  end

  defp format_date(%NaiveDateTime{} = ndt) do
    ndt
    |> DateTime.from_naive!("Etc/UTC")
    |> Web.Clock.local_today()
    |> Calendar.strftime("%b %-d, %Y")
  end

  def render(assigns) do
    counts = counts(assigns.profiles)
    shown = Map.fetch!(split(assigns.profiles), Map.fetch!(@views, assigns.show))

    assigns = assign(assigns, shown: shown, counts: counts)

    ~H"""
    <.page_head slug="Studio / Readers" title="Readers">
      <:lede>
        Who is reading the site, and where from. A location comes from the access log while the
        log still holds that visitor, and is guessed from reading hours and local pages when it
        does not. Your own reading is kept out of this page and out of every figure on the site.
      </:lede>
      <:actions>
        <button type="button" phx-click="find_mine" class="adm-btn" disabled={@scanning?}>
          Find my own addresses
        </button>
        <button
          type="button"
          phx-click="refresh_geo"
          class="adm-btn adm-btn--quiet"
          disabled={@scanning?}
        >
          Resolve locations
        </button>
      </:actions>
    </.page_head>

    <.panel :if={@candidates != []} title="Looks like you" count={length(@candidates)}>
      <p class="ov-quiet">
        Each of these addresses was answered on an admin page, so it was yours at that moment.
        That is not the same as every visit from it being yours: a home address is lent and
        reassigned, and a house holds more than one reader. Where the browser that read does not
        match the browser that signed in, it is worth a second look.
      </p>

      <div class="adm-list adm-list--desk" id="owner-candidates">
        <article :for={c <- @candidates} id={"candidate-#{c.badge}"} class="adm-item">
          <div class="adm-item-main">
            <h2 class="adm-item-title"><code>#{c.badge}</code></h2>

            <div class="adm-item-meta">
              <span>
                Signed in <span class="adm-figure">{c.admin_requests}</span>
                {plural(c.admin_requests, "time")} on {admin_when(c)}
              </span>
              <span :if={c.admin_agents != []}>as {Enum.join(c.admin_agents, ", ")}</span>
            </div>

            <div class="adm-item-meta">
              <span>
                Read <span class="adm-figure">{c.hits}</span> {plural(c.hits, "page")} over
                <span class="adm-figure">{c.days}</span> {plural(c.days, "day")}
              </span>
              <span :if={c.devices != []}>as {Enum.join(c.devices, ", ")}</span>
              <span :if={c.first_seen}>
                {format_date(c.first_seen)} – {format_date(c.last_seen)}
              </span>
            </div>
          </div>

          <div class="adm-item-actions">
            <button
              type="button"
              phx-click="mine"
              phx-value-hash={c.hash}
              class="adm-btn adm-btn--small adm-btn--primary"
            >
              Those are mine
            </button>

            <button
              type="button"
              phx-click="not_a_reader"
              phx-value-hash={c.hash}
              class="adm-btn adm-btn--small adm-btn--quiet"
            >
              Leave as a reader
            </button>
          </div>
        </article>
      </div>
    </.panel>

    <.panel title="Visitors" count={length(@shown)}>
      <.tabs label="Visitor filter">
        <:tab patch={~p"/admin/readers"} active={@show == "readers"} count={@counts.readers}>
          Readers
        </:tab>
        <:tab patch={~p"/admin/readers?show=mine"} active={@show == "mine"} count={@counts.mine}>
          Mine
        </:tab>
        <:tab patch={~p"/admin/readers?show=bots"} active={@show == "bots"} count={@counts.bots}>
          Bot bursts
        </:tab>
        <:tab patch={~p"/admin/readers?show=all"} active={@show == "all"} count={@counts.all}>
          Everyone
        </:tab>
      </.tabs>

      <.empty :if={@reading? and @profiles == nil}>
        Reading the visits…
      </.empty>

      <.empty :if={not @reading? and @shown == []}>
        <%= if @show == "mine" do %>
          None of your own addresses are recognised yet. "Find my own addresses" reads the access
          log for pages only you can be served.
        <% else %>
          No visitors in this view yet.
        <% end %>
      </.empty>

      <div :if={@shown != []} class="adm-list adm-list--desk" id="readers-list">
        <article :for={r <- @shown} id={"reader-#{r.badge}"} class="adm-item">
          <div class="adm-item-main">
            <h2 class="adm-item-title">
              <code>#{r.badge}</code> · {r.location.label}
            </h2>

            <div class="adm-item-meta">
              <.pill :if={r.mine?} tone="neutral">You</.pill>
              <.pill :if={r.location.kind == :geo} tone="live">GeoIP</.pill>
              <.pill :if={r.location.kind == :inferred} tone="held">Guessed</.pill>
              <.pill :if={r.bot_burst? and not r.mine?} tone="fail">Bot burst</.pill>
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
              <span>{format_date(r.first_seen)} – {format_date(r.last_seen)}</span>
            </div>

            <div class="adm-item-meta">
              <span :for={{path, count} <- r.top_pages}>
                <a href={path} class="adm-link">{path}</a> (<span class="adm-figure">{count}</span>)
              </span>
            </div>
          </div>

          <div class="adm-item-actions">
            <button
              :if={not r.mine?}
              type="button"
              phx-click="mine"
              phx-value-hash={r.ip_hash}
              class="adm-btn adm-btn--small adm-btn--quiet"
            >
              This is me
            </button>

            <button
              :if={r.mine?}
              type="button"
              phx-click="not_mine"
              phx-value-hash={r.ip_hash}
              class="adm-btn adm-btn--small adm-btn--quiet"
            >
              Count me again
            </button>

            <button
              :if={not r.mine?}
              type="button"
              phx-click="forget"
              phx-value-hash={r.ip_hash}
              data-confirm={"Delete all #{r.total_hits} views for ##{r.badge}? This cannot be undone."}
              class="adm-btn adm-btn--small adm-btn--danger"
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
