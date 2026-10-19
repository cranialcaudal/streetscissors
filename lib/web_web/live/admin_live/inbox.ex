defmodule WebWeb.AdminLive.Inbox do
  @moduledoc """
  Messages sent through `/contact`, which used to live halfway down the
  dashboard with the archive cut at five.

  Three boxes — needs attention, inbox, archive — and the box is in the URL
  (`?box=`), so each is an address the Back button can return to. A message
  moves between them without being deleted; only an archived one can be.

  Letters (`Web.Letters`) arrive here too: a message about a particular
  piece, marked with a link to it. One whose writer allowed it can be
  published beneath the piece, and taken down again; one they did not
  allow has no publish control at all.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Contact
  alias Web.Letters
  alias Web.Pieces
  alias WebWeb.AdminNav

  @boxes ~w(attention inbox archive)

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok, assign(socket, page_title: "Inbox | Admin")}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_params(params, _uri, socket) do
    box = if params["box"] in @boxes, do: params["box"], else: default_box()
    {:noreply, socket |> assign(:box, box) |> load()}
  end

  # Open on what needs you: flagged messages when there are any, else the inbox.
  defp default_box do
    if Map.get(Contact.count_by_status(), "attention", 0) > 0, do: "attention", else: "inbox"
  end

  def handle_event("message_status", %{"id" => id, "status" => status}, socket)
      when status in @boxes do
    Contact.update_status(id, status)
    {:noreply, socket |> load() |> AdminNav.refresh_counts()}
  end

  def handle_event("publish_letter", %{"id" => id}, socket) do
    case id |> Contact.get_message() |> Letters.publish() do
      {:ok, _} ->
        {:noreply, socket |> load() |> put_flash(:info, "Published beneath the piece.")}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Its writer didn't allow this letter to be published.")}
    end
  end

  def handle_event("unpublish_letter", %{"id" => id}, socket) do
    case id |> Contact.get_message() |> Letters.unpublish() do
      {:ok, _} -> {:noreply, socket |> load() |> put_flash(:info, "Taken down from the piece.")}
      _ -> {:noreply, load(socket)}
    end
  end

  def handle_event("delete_message", %{"id" => id}, socket) do
    Contact.delete_message(id)

    {:noreply,
     socket
     |> load()
     |> AdminNav.refresh_counts()
     |> put_flash(:info, "Message deleted.")}
  end

  defp load(socket) do
    messages = Contact.list_messages(socket.assigns.box)

    # Each letter's piece, resolved once for its link and title.
    pieces =
      for %{piece: piece} <- messages, is_binary(piece), into: %{} do
        {piece, Pieces.resolve(piece)}
      end

    socket
    |> assign(:counts, Contact.count_by_status())
    |> assign(:messages, messages)
    |> assign(:pieces, pieces)
  end

  def render(assigns) do
    ~H"""
    <.page_head slug="Mail / Inbox" title="Inbox">
      <:lede>
        Messages from the contact page, and letters about a piece. Nothing here is public until
        you publish it under the piece.
      </:lede>
    </.page_head>

    <.tabs label="Boxes">
      <:tab
        patch={~p"/admin/inbox?box=attention"}
        active={@box == "attention"}
        count={Map.get(@counts, "attention", 0)}
      >
        Needs attention
      </:tab>
      <:tab
        patch={~p"/admin/inbox?box=inbox"}
        active={@box == "inbox"}
        count={Map.get(@counts, "inbox", 0)}
      >
        Inbox
      </:tab>
      <:tab
        patch={~p"/admin/inbox?box=archive"}
        active={@box == "archive"}
        count={Map.get(@counts, "archive", 0)}
      >
        Archive
      </:tab>
    </.tabs>

    <.empty :if={@messages == []}>{empty_line(@box)}</.empty>

    <div :if={@messages != []} class="adm-list adm-letters" id="messages">
      <article
        :for={msg <- @messages}
        id={"message-#{msg.id}"}
        class={["adm-item adm-letter", msg.status == "attention" && "adm-letter--flagged"]}
      >
        <header class="adm-letter-head">
          <h2 class="adm-letter-from">{msg.name}</h2>
          <div class="adm-item-meta adm-letter-meta">
            <span class="adm-mail-address">{msg.email}</span>
            <span class="adm-mail-when">{stamp(msg.inserted_at)}</span>
            <.pill :if={msg.status == "attention"} tone="attention">Needs attention</.pill>
            <.pill :if={msg.piece && msg.published_at} tone="live">Published</.pill>
            <.pill :if={msg.piece && !msg.may_publish} tone="quiet">Private</.pill>
          </div>
        </header>

        <p :if={msg.piece} class="adm-letter-about">
          About
          <%= case @pieces[msg.piece] do %>
            <% {:ok, piece} -> %>
              <.link href={piece.path} target="_blank" class="adm-letter-piece">{piece.title}</.link>
            <% _ -> %>
              a piece that is no longer on the site ({msg.piece})
          <% end %>
        </p>

        <p class="adm-letter-body">{msg.message}</p>

        <div class="adm-item-actions adm-letter-actions">
          <a href={"mailto:#{msg.email}"} class="adm-btn adm-btn--quiet adm-btn--small">
            <.icon name="hero-arrow-uturn-left" class="size-4" /> Reply
          </a>
          <button
            :if={msg.piece && msg.may_publish && is_nil(msg.published_at)}
            phx-click="publish_letter"
            phx-value-id={msg.id}
            class="adm-btn adm-btn--quiet adm-btn--small adm-act-accent"
          >
            Publish under the piece
          </button>
          <button
            :if={msg.piece && msg.published_at}
            phx-click="unpublish_letter"
            phx-value-id={msg.id}
            class="adm-btn adm-btn--quiet adm-btn--small"
          >
            Take down
          </button>
          <button
            :if={msg.status != "attention"}
            phx-click="message_status"
            phx-value-id={msg.id}
            phx-value-status="attention"
            class="adm-btn adm-btn--quiet adm-btn--small"
          >
            <.icon name="hero-flag" class="size-4" /> Flag
          </button>
          <button
            :if={msg.status != "inbox"}
            phx-click="message_status"
            phx-value-id={msg.id}
            phx-value-status="inbox"
            class="adm-btn adm-btn--quiet adm-btn--small"
          >
            <.icon name="hero-inbox" class="size-4" /> Move to inbox
          </button>
          <button
            :if={msg.status != "archive"}
            phx-click="message_status"
            phx-value-id={msg.id}
            phx-value-status="archive"
            class="adm-btn adm-btn--quiet adm-btn--small"
          >
            <.icon name="hero-archive-box" class="size-4" /> Archive
          </button>
          <button
            :if={msg.status == "archive"}
            phx-click="delete_message"
            phx-value-id={msg.id}
            data-confirm="Delete this message? This cannot be undone."
            class="adm-btn adm-btn--quiet adm-btn--small adm-act-danger"
          >
            <.icon name="hero-trash" class="size-4" /> Delete
          </button>
        </div>
      </article>
    </div>
    """
  end

  defp empty_line("attention"),
    do: "Nothing flagged. Flag a message from the inbox to keep it in view here."

  defp empty_line("inbox"), do: "The inbox is empty. Messages from the contact page land here."
  defp empty_line("archive"), do: "Nothing archived yet. Archive a message once it is answered."
end
