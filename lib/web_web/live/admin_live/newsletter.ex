defmodule WebWeb.AdminLive.Newsletter do
  @moduledoc """
  Composing, testing and sending the newsletter, and the list it goes to.

  The composer sits beside a preview of the message as a reader gets it —
  the same `Web.Email.shell/2` the send uses, in a sandboxed frame. A draft
  can be saved and picked up later; sending from a draft turns that row into
  the record of the send. "Send a test" posts one `[Test]` copy to a single
  address, recorded nowhere. The subscriber list moved here from the
  dashboard, since this is the page that uses it.

  A newsletter is written in Markdown in the document editor
  (`WebWeb.DocumentEditor`), rendered as a post is, embeds and all
  (`Web.Email.newsletter_html/2`). A draft from before that is HTML
  (`format: "html"`), and opens and sends as HTML.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents
  import WebWeb.DocumentEditor, only: [document_editor: 1]

  alias Web.Email
  alias Web.Newsletter
  alias Web.SiteSettings
  alias Web.Workers.NewsletterSender
  alias WebWeb.DocumentEditor

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Newsletter | Admin",
       draft: nil,
       test_email: SiteSettings.get_setting("newsletter_test_email", "")
     )
     |> assign_compose("", "")
     |> DocumentEditor.attach()
     |> load()}
  end

  defp load(socket) do
    assign(socket,
      subscribers: Newsletter.list_subscribers(),
      subscribers_count: length(Newsletter.list_active_emails()),
      drafts: Newsletter.list_drafts(),
      sent: Newsletter.list_sent()
    )
  end

  defp assign_compose(socket, subject, body, format \\ "markdown") do
    format = if format == "html", do: "html", else: "markdown"

    assign(socket,
      form: to_form(%{"subject" => subject, "body" => body, "format" => format}),
      preview: preview(body, format)
    )
  end

  # The composer's text is replaced (a draft opened, a new message, a send):
  # the editor is told, since it is never patched in place.
  defp compose(socket, subject, body, format \\ "markdown") do
    socket = assign_compose(socket, subject, body, format)
    DocumentEditor.set(socket, editor_id(format(socket)), body)
  end

  defp editor_id("html"), do: "newsletter-html"
  defp editor_id(_markdown), do: "newsletter-body"

  # The reader's view. Unsubscribe links are per-subscriber tokens, so the
  # preview's footer is the real footer with no address behind it.
  defp preview(body, format) do
    content =
      if String.trim(body) == "",
        do: "<p><em>The message will appear here.</em></p>",
        else: Email.newsletter_html(body, format)

    Email.preview_page(content, Email.unsubscribe_html("preview@example.com"))
  end

  # --- Composing ---

  def handle_event("validate", %{"subject" => subject, "body" => body} = params, socket) do
    {:noreply, assign_compose(socket, subject, body, params["format"] || format(socket))}
  end

  def handle_event("save_draft", _params, socket) do
    attrs = %{"subject" => subject(socket), "body" => body(socket), "format" => format(socket)}

    case Newsletter.save_draft(socket.assigns.draft, attrs) do
      {:ok, draft} ->
        {:noreply,
         socket
         |> assign(:draft, draft)
         |> load()
         |> put_flash(:info, "Draft saved.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "A draft needs a subject and a body.")}
    end
  end

  def handle_event("open_draft", %{"id" => id}, socket) do
    case Newsletter.get_draft(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That draft is gone.")}

      draft ->
        {:noreply,
         socket |> assign(:draft, draft) |> compose(draft.subject, draft.body, draft.format)}
    end
  end

  def handle_event("new_message", _params, socket) do
    {:noreply, socket |> assign(:draft, nil) |> compose("", "")}
  end

  def handle_event("delete_draft", %{"id" => id}, socket) do
    with %{} = draft <- Newsletter.get_draft(id), {:ok, _} <- Newsletter.delete_draft(draft) do
      # Deleting the draft open in the composer leaves the text where it is,
      # but a later save makes a new draft rather than updating a deleted row.
      socket =
        if socket.assigns.draft && socket.assigns.draft.id == draft.id,
          do: assign(socket, :draft, nil),
          else: socket

      {:noreply, socket |> load() |> put_flash(:info, "Draft deleted.")}
    else
      _ -> {:noreply, load(socket)}
    end
  end

  def handle_event("send_test", %{"test_email" => address}, socket) do
    address = String.trim(address)

    cond do
      subject(socket) == "" or body(socket) == "" ->
        {:noreply, put_flash(socket, :error, "Write a subject and a body before sending a test.")}

      not String.match?(address, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/) ->
        {:noreply, put_flash(socket, :error, "The test needs an address to go to.")}

      true ->
        case Newsletter.send_test(address, subject(socket), body(socket), format(socket)) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(:test_email, address)
             |> put_flash(:info, "Test sent to #{address}.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "The test didn't send: #{inspect(reason)}")}
        end
    end
  end

  # One Oban job per subscriber, staggered a quarter-second apart so the
  # sending API doesn't get hit all at once — the same pacing the old
  # Process.sleep(500) loop gave, but as durable jobs: a crash or redeploy
  # mid-broadcast no longer loses whoever hadn't been reached yet, and Oban
  # retries a failed send instead of silently dropping it.
  def handle_event("send", %{"subject" => subject, "body" => body} = params, socket) do
    format = params["format"] || format(socket)
    subscribers = Newsletter.list_active_emails()
    now = DateTime.utc_now()

    subscribers
    |> Enum.with_index()
    |> Enum.map(fn {email, index} ->
      NewsletterSender.new(
        %{"email" => email, "subject" => subject, "body" => body, "format" => format},
        scheduled_at: DateTime.add(now, index * 250, :millisecond)
      )
    end)
    |> Oban.insert_all()

    Newsletter.record_send(subject, body, length(subscribers), socket.assigns.draft, format)

    {:noreply,
     socket
     |> put_flash(:info, "Queued #{length(subscribers)} subscribers for delivery.")
     |> assign(:draft, nil)
     |> compose("", "")
     |> load()}
  end

  # --- The list ---

  def handle_event("delete_subscriber", %{"id" => id}, socket) do
    case Web.Repo.get(Web.Newsletter.Subscriber, id) do
      nil -> :ok
      subscriber -> Newsletter.delete_subscriber(subscriber)
    end

    {:noreply, load(socket)}
  end

  defp subject(socket), do: String.trim(socket.assigns.form.params["subject"] || "")
  defp body(socket), do: String.trim(socket.assigns.form.params["body"] || "")
  defp format(socket), do: socket.assigns.form.params["format"] || "markdown"

  def render(assigns) do
    ~H"""
    <.page_head slug="Mail / Newsletter" title="Newsletter">
      <:lede>
        {@subscribers_count} active {if @subscribers_count == 1, do: "subscriber", else: "subscribers"}.
        A broadcast is queued as one job per reader, so a restart partway through loses no one.
      </:lede>
      <:actions>
        <.link href={~p"/admin/subscribers/export"} class="adm-btn adm-btn--quiet">
          <.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV
        </.link>
      </:actions>
    </.page_head>

    <.panel title={if @draft, do: "Editing a draft", else: "Compose"} class="adm-compose-panel">
      <:actions>
        <button :if={@draft} type="button" phx-click="new_message" class="adm-btn adm-btn--quiet">
          <.icon name="hero-plus" class="size-4" /> New message
        </button>
      </:actions>

      <div class="adm-compose">
        <div class="adm-compose-write">
          <.form for={@form} id="newsletter-form" phx-change="validate" phx-submit="send">
            <.input
              field={@form[:subject]}
              type="text"
              label="Subject"
              placeholder="Updates from streetscissors"
              class="adm-input"
              phx-debounce="300"
              required
            />
            <input type="hidden" name="format" value={@form.params["format"]} />
            <label class="adm-label" for={"#{editor_id(@form.params["format"])}-input"}>
              {if @form.params["format"] == "html", do: "Body (HTML)", else: "Body (Markdown)"}
            </label>
            <.document_editor
              id={editor_id(@form.params["format"])}
              name="body"
              value={@form.params["body"]}
              complete={if @form.params["format"] == "html", do: "none", else: "blog"}
              media={@form.params["format"] != "html"}
              label="Body"
            />
            <p :if={@form.params["format"] == "html"} class="adm-help">
              An older draft, written in HTML, and sent as it is. Each reader's copy carries their own unsubscribe link.
            </p>
            <p :if={@form.params["format"] != "html"} class="adm-help">
              Markdown, set as a post is: <code>![[roll012/3]]</code> embeds a frame, and links to the
              site work from a mail client. Each reader's copy carries their own unsubscribe link.
            </p>

            <div class="adm-form-actions">
              <button
                type="submit"
                class="adm-btn adm-btn--primary"
                data-confirm={"Send this to all #{@subscribers_count} active subscribers?"}
              >
                <.icon name="hero-paper-airplane" class="size-4" /> Broadcast to {@subscribers_count}
              </button>
              <button type="button" phx-click="save_draft" class="adm-btn">
                Save draft
              </button>
            </div>
          </.form>

          <section class="adm-test-send" aria-labelledby="newsletter-test-title">
            <h3 id="newsletter-test-title" class="adm-mail-subhead">Send a test</h3>
            <p class="adm-help">
              One copy, marked [Test], to this one address. It is not recorded as a send.
            </p>
            <form id="newsletter-test-form" phx-submit="send_test">
              <label class="adm-label" for="test_email">Send a test to</label>
              <div class="adm-inline-form">
                <input
                  type="email"
                  id="test_email"
                  name="test_email"
                  value={@test_email}
                  class="adm-input"
                  placeholder="you@example.com"
                  autocomplete="email"
                />
                <button type="submit" class="adm-btn">
                  <.icon name="hero-envelope-open" class="size-4" /> Send test
                </button>
              </div>
            </form>
          </section>
        </div>

        <section class="adm-compose-look" aria-labelledby="newsletter-look-title">
          <h3 id="newsletter-look-title" class="adm-mail-subhead">What a reader sees</h3>
          <iframe
            id="newsletter-preview"
            class="adm-preview-frame"
            title="Newsletter preview"
            sandbox=""
            srcdoc={@preview}
          >
          </iframe>
          <p class="adm-help">
            The paper shell and footer a reader gets. The unsubscribe link is a placeholder; each
            reader's copy has their own.
          </p>
        </section>
      </div>
    </.panel>

    <.panel :if={@drafts != []} title="Drafts" count={length(@drafts)}>
      <.rows id="drafts" rows={@drafts}>
        <:col :let={draft} label="Subject" class="adm-cell-title">{draft.subject}</:col>
        <:col :let={draft} label="Saved" class="adm-mail-when">{stamp(draft.updated_at)}</:col>
        <:action :let={draft}>
          <button
            phx-click="open_draft"
            phx-value-id={draft.id}
            class="adm-btn adm-btn--quiet adm-btn--small"
          >
            Open
          </button>
        </:action>
        <:action :let={draft}>
          <button
            phx-click="delete_draft"
            phx-value-id={draft.id}
            data-confirm="Delete this draft?"
            class="adm-btn adm-btn--quiet adm-btn--small adm-act-danger"
          >
            Delete
          </button>
        </:action>
      </.rows>
    </.panel>

    <.panel title="Sent" count={length(@sent)}>
      <.rows id="sent" rows={@sent}>
        <:col :let={sent} label="Subject" class="adm-cell-title">{sent.subject}</:col>
        <:col :let={sent} label="Readers" class="adm-cell-num">{sent.recipient_count} sent</:col>
        <:col :let={sent} label="When" class="adm-mail-when">{stamp(sent.sent_at)}</:col>
        <:empty>Nothing sent yet. A broadcast is listed here once it is queued.</:empty>
      </.rows>
    </.panel>

    <.panel title="Subscribers" count={length(@subscribers)}>
      <.rows id="subscribers" rows={@subscribers}>
        <:col :let={sub} label="Email" class="adm-mail-address">{sub.email}</:col>
        <:col :let={sub} label="Status">
          <.pill :if={sub.active} tone="live">Active</.pill>
          <.pill :if={!sub.active} tone="quiet">Unsubscribed</.pill>
        </:col>
        <:col :let={sub} label="Joined" class="adm-mail-when">{stamp(sub.inserted_at)}</:col>
        <:action :let={sub}>
          <button
            phx-click="delete_subscriber"
            phx-value-id={sub.id}
            data-confirm={"Remove #{sub.email} from the subscriber list? This cannot be undone."}
            class="adm-btn adm-btn--quiet adm-btn--small adm-act-danger"
            aria-label={"Remove #{sub.email}"}
          >
            <.icon name="hero-trash" class="size-4" /> Remove
          </button>
        </:action>
        <:empty>No subscribers yet. Readers join through the sign-up on the site.</:empty>
      </.rows>
    </.panel>
    """
  end
end
