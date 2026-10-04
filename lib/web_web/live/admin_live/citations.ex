defmodule WebWeb.AdminLive.Citations do
  @moduledoc """
  Webmentions awaiting a decision (`Web.Webmentions`): other sites that link
  to a piece. A mention arrives, is verified by fetching the source, and
  waits here as `held`; approved, it appears under the piece as "Cited by".

  The list is in the URL (`?show=held|approved|all`), opening on the held
  ones, the only list that asks anything of you.

  `?show=sent` is the other direction (`Web.Webmentions.Outgoing`): the sites
  this one has told that a post links to them, and what each said back.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Pieces
  alias Web.Webmentions
  alias Web.Webmentions.Outgoing
  alias WebWeb.AdminNav

  @views %{"held" => "held", "approved" => "approved", "all" => nil, "sent" => nil}

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok, assign(socket, page_title: "Citations | Admin", show: "held")}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_params(params, _uri, socket) do
    show = if Map.has_key?(@views, params["show"]), do: params["show"], else: "held"
    {:noreply, socket |> assign(:show, show) |> load()}
  end

  def handle_event("approve", %{"id" => id}, socket) do
    {:ok, _} = id |> Webmentions.get!() |> Webmentions.approve()

    {:noreply,
     socket |> load() |> AdminNav.refresh_counts() |> put_flash(:info, "Shown under the piece.")}
  end

  def handle_event("reject", %{"id" => id}, socket) do
    {:ok, _} = id |> Webmentions.get!() |> Webmentions.reject()
    {:noreply, socket |> load() |> AdminNav.refresh_counts() |> put_flash(:info, "Rejected.")}
  end

  def handle_event("retry", %{"id" => id}, socket) do
    {:ok, _job} = id |> Outgoing.get!() |> Outgoing.retry()
    {:noreply, socket |> load() |> put_flash(:info, "Queued to be sent again.")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Webmentions.get!() |> Webmentions.delete()
    {:noreply, socket |> load() |> AdminNav.refresh_counts() |> put_flash(:info, "Deleted.")}
  end

  defp load(socket) do
    mentions = Webmentions.list(@views[socket.assigns.show])

    pieces =
      mentions |> Enum.map(& &1.piece) |> Enum.uniq() |> Map.new(&{&1, Pieces.resolve(&1)})

    socket
    |> assign(:counts, Webmentions.count_by_status())
    |> assign(:mentions, mentions)
    |> assign(:pieces, pieces)
    |> assign(:sent, Outgoing.list())
  end

  def render(assigns) do
    ~H"""
    <.page_head slug="Mail / Citations" title="Citations">
      <:lede>
        Other sites that link to a piece, by webmention. Each is checked against the page that
        sent it; approved, it shows under the piece as “Cited by.”
      </:lede>
    </.page_head>

    <.tabs label="Citations">
      <:tab
        patch={~p"/admin/citations?show=held"}
        active={@show == "held"}
        count={Map.get(@counts, "held", 0)}
      >
        Waiting
      </:tab>
      <:tab
        patch={~p"/admin/citations?show=approved"}
        active={@show == "approved"}
        count={Map.get(@counts, "approved", 0)}
      >
        Shown
      </:tab>
      <:tab patch={~p"/admin/citations?show=all"} active={@show == "all"}>All</:tab>
      <:tab patch={~p"/admin/citations?show=sent"} active={@show == "sent"} count={length(@sent)}>
        Sent
      </:tab>
    </.tabs>

    <div :if={@show == "sent"} id="citations-sent">
      <p class="adm-help">
        Each link a post makes to another site is announced to that site once, within the hour.
        A site that takes no webmentions is noted and not asked again.
      </p>
      <.rows id="sent" rows={@sent} row_id={&"sent-#{&1.id}"}>
        <:col :let={row} label="From" class="adm-cell-title">
          <.link href={row.source} target="_blank" class="adm-link">{row.source}</.link>
        </:col>
        <:col :let={row} label="To">
          <a href={row.target} target="_blank" rel="noopener nofollow">{row.target}</a>
        </:col>
        <:col :let={row} label="Outcome">
          <.pill tone={sent_tone(row.status)}>{sent_label(row.status)}</.pill>
          <span :if={row.detail}>{row.detail}</span>
        </:col>
        <:col :let={row} label="When">{stamp(row.sent_at || row.updated_at)}</:col>
        <:action :let={row}>
          <button
            :if={row.status in ["failed", "no_endpoint"]}
            phx-click="retry"
            phx-value-id={row.id}
            class="adm-link"
          >
            Try again
          </button>
        </:action>
        <:empty>No post has linked to another site yet.</:empty>
      </.rows>
    </div>

    <.empty :if={@show != "sent" and @mentions == []}>{empty_line(@show)}</.empty>

    <div :if={@show != "sent" and @mentions != []} class="adm-list" id="citations">
      <article :for={mention <- @mentions} id={"citation-#{mention.id}"} class="adm-item">
        <div class="adm-item-main">
          <h2 class="adm-item-title">
            <a href={mention.source} target="_blank" rel="noopener nofollow">
              {mention.title || mention.source}
            </a>
          </h2>
          <div class="adm-item-meta">
            <span>{mention.source_host}</span>
            <span :if={mention.author_name}>by {mention.author_name}</span>
            <span>{stamp(mention.updated_at)}</span>
            <.pill tone={status_tone(mention.status)}>{status_label(mention.status)}</.pill>
          </div>
          <p class="adm-item-note">
            Cites
            <%= case @pieces[mention.piece] do %>
              <% {:ok, piece} -> %>
                <.link href={piece.path} target="_blank" class="adm-link">{piece.title}</.link>
              <% _ -> %>
                a piece no longer on the site ({mention.piece})
            <% end %>
          </p>
        </div>

        <div class="adm-item-actions">
          <button
            :if={mention.status == "held"}
            phx-click="approve"
            phx-value-id={mention.id}
            class="adm-btn adm-btn--primary adm-btn--small"
          >
            Approve
          </button>
          <button
            :if={mention.status in ["held", "approved"]}
            phx-click="reject"
            phx-value-id={mention.id}
            class="adm-link adm-link--quiet"
          >
            {if mention.status == "approved", do: "Take down", else: "Reject"}
          </button>
          <button
            phx-click="delete"
            phx-value-id={mention.id}
            data-confirm="Delete this citation? A new ping from its source would bring it back."
            class="adm-link adm-link--danger"
          >
            Delete
          </button>
        </div>
      </article>
    </div>
    """
  end

  defp status_tone("approved"), do: "live"
  defp status_tone("held"), do: "held"
  defp status_tone("pending"), do: "draft"
  defp status_tone(_), do: "quiet"

  defp status_label("approved"), do: "Shown"
  defp status_label("held"), do: "Waiting"
  defp status_label("pending"), do: "Checking"
  defp status_label("gone"), do: "Link gone"
  defp status_label("rejected"), do: "Rejected"

  defp sent_tone("sent"), do: "live"
  defp sent_tone("failed"), do: "failed"
  defp sent_tone("queued"), do: "draft"
  defp sent_tone(_), do: "quiet"

  defp sent_label("sent"), do: "Told"
  defp sent_label("queued"), do: "Sending"
  defp sent_label("no_endpoint"), do: "Takes none"
  defp sent_label("failed"), do: "Failed"
  defp sent_label("withdrawn"), do: "Withdrawn"

  defp empty_line("held"), do: "Nothing waiting. No site has cited a piece since you last looked."
  defp empty_line("approved"), do: "No citations shown yet."
  defp empty_line(_), do: "No site has sent a webmention yet."
end
