defmodule WebWeb.AdminLive.GuestbookManager do
  @moduledoc """
  The guestbook's approval queue. Signatures arrive held (see
  `Web.General.create_guestbook_entry/1`) and appear on `/guestbook` only once
  approved here.

  Opens on the held ones, the only list that asks anything of you; `?show=`
  switches to what is live or to everything, and a signature arriving while
  the page is open lands in the queue without a reload.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.General
  alias WebWeb.AdminNav

  @views ~w(held live all)

  def mount(_params, _session, socket) do
    if connected?(socket) do
      General.subscribe_guestbook()
      General.subscribe_guestbook_admin()
    end

    {:ok, assign(socket, page_title: "Guestbook | Admin", show: "held")}
  end

  def handle_params(params, _uri, socket) do
    show = if params["show"] in @views, do: params["show"], else: "held"
    {:noreply, socket |> assign(:show, show) |> load()}
  end

  # Both topics — a new held signature, or one approved (here or in another
  # tab) — just mean "the list changed", so re-read it. Prepending the pushed
  # entry, as this used to, showed an approved entry twice.
  def handle_info({event, _entry}, socket)
      when event in [:guestbook_entry_held, :guestbook_entry_created] do
    {:noreply, socket |> load() |> AdminNav.refresh_counts()}
  end

  def handle_event("toggle_approved", %{"id" => id}, socket) do
    entry = General.get_guestbook_entry!(id)

    if entry.approved do
      General.unapprove_guestbook_entry(entry)
    else
      General.approve_guestbook_entry(entry)
    end

    {:noreply, socket |> load() |> AdminNav.refresh_counts()}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    entry = General.get_guestbook_entry!(id)
    {:ok, _} = General.delete_guestbook_entry(entry)

    {:noreply,
     socket
     |> load()
     |> AdminNav.refresh_counts()
     |> put_flash(:info, "Signature deleted.")}
  end

  defp load(socket) do
    all = General.list_all_guestbook_entries()

    socket
    |> assign(:held_count, Enum.count(all, &(!&1.approved)))
    |> assign(:live_count, Enum.count(all, & &1.approved))
    |> assign(:all_count, length(all))
    |> assign(:entries, filter(all, socket.assigns.show))
  end

  defp filter(entries, "held"), do: Enum.reject(entries, & &1.approved)
  defp filter(entries, "live"), do: Enum.filter(entries, & &1.approved)
  defp filter(entries, "all"), do: entries

  def render(assigns) do
    ~H"""
    <.page_head slug="Mail / Guestbook" title="Guestbook">
      <:lede>
        Signatures wait here until approved. Approved ones show on
        <.link href={~p"/guestbook"} class="adm-link" target="_blank">the guestbook</.link>
        for 60 days.
      </:lede>
    </.page_head>

    <.tabs label="Signatures">
      <:tab patch={~p"/admin/guestbook?show=held"} active={@show == "held"} count={@held_count}>
        Waiting
      </:tab>
      <:tab patch={~p"/admin/guestbook?show=live"} active={@show == "live"} count={@live_count}>
        Live
      </:tab>
      <:tab patch={~p"/admin/guestbook?show=all"} active={@show == "all"} count={@all_count}>
        All
      </:tab>
    </.tabs>

    <.empty :if={@entries == []}>{empty_line(@show)}</.empty>

    <div :if={@entries != []} class="adm-list" id="signatures">
      <article :for={entry <- @entries} id={"signature-#{entry.id}"} class="adm-item">
        <div class="adm-item-main">
          <h2 class="adm-item-title">{entry.name}</h2>
          <div class="adm-item-meta">
            <span>{stamp(entry.inserted_at)}</span>
            <span>{entry.ip_address || "no IP"}</span>
            <.pill :if={entry.approved} tone="live">Live</.pill>
            <.pill :if={!entry.approved} tone="held">Waiting</.pill>
          </div>
          <p class="adm-item-body">{entry.message}</p>
        </div>

        <div class="adm-item-actions">
          <button
            :if={!entry.approved}
            phx-click="toggle_approved"
            phx-value-id={entry.id}
            class="adm-btn adm-btn--primary adm-btn--small"
          >
            <.icon name="hero-check" class="size-4" /> Approve
          </button>
          <button
            :if={entry.approved}
            phx-click="toggle_approved"
            phx-value-id={entry.id}
            class="adm-btn adm-btn--quiet adm-btn--small"
          >
            Unpublish
          </button>
          <button
            phx-click="delete"
            phx-value-id={entry.id}
            data-confirm="Delete this signature permanently?"
            class="adm-link adm-link--danger"
          >
            <.icon name="hero-trash" class="size-4" /> Delete
          </button>
        </div>
      </article>
    </div>
    """
  end

  defp empty_line("held"), do: "Nothing waiting. Every signature has been seen."
  defp empty_line("live"), do: "Nothing approved yet."
  defp empty_line("all"), do: "No one has signed yet."
end
