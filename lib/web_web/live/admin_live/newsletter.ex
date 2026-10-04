defmodule WebWeb.AdminLive.Newsletter do
  @moduledoc """
  Composing, testing and sending the newsletter, and the list it goes to.

  The composer sits beside a preview of the message as a reader gets it —
  the same `Web.Email.shell/2` the send uses, in a sandboxed frame. A draft
  can be saved and picked up later; sending from a draft turns that row into
  the record of the send. "Send a test" posts one `[Test]` copy to a single
  address, recorded nowhere. The subscriber list moved here from the
  dashboard, since this is the page that uses it.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Email
  alias Web.Newsletter
  alias Web.SiteSettings
  alias Web.Workers.NewsletterSender

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Newsletter | Admin",
       draft: nil,
       test_email: SiteSettings.get_setting("newsletter_test_email", "")
     )
     |> assign_compose("", "")
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

  defp assign_compose(socket, subject, body) do
    assign(socket,
      form: to_form(%{"subject" => subject, "body" => body}),
      preview: preview(body)
    )
  end

  # The reader's view. Unsubscribe links are per-subscriber tokens, so the
  # preview's footer is the real footer with no address behind it.
  defp preview(body) do
    content =
      if String.trim(body) == "", do: "<p><em>The message will appear here.</em></p>", else: body

    Email.preview_page(content, Email.unsubscribe_html("preview@example.com"))
  end

  # --- Composing ---

  def handle_event("validate", %{"subject" => subject, "body" => body}, socket) do
    {:noreply, assign_compose(socket, subject, body)}
  end

  def handle_event("save_draft", _params, socket) do
    attrs = %{"subject" => subject(socket), "body" => body(socket)}

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
        {:noreply, socket |> assign(:draft, draft) |> assign_compose(draft.subject, draft.body)}
    end
  end

  def handle_event("new_message", _params, socket) do
    {:noreply, socket |> assign(:draft, nil) |> assign_compose("", "")}
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
        case Newsletter.send_test(address, subject(socket), body(socket)) do
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
  def handle_event("send", %{"subject" => subject, "body" => body}, socket) do
    subscribers = Newsletter.list_active_emails()
    now = DateTime.utc_now()

    subscribers
    |> Enum.with_index()
    |> Enum.map(fn {email, index} ->
      NewsletterSender.new(
        %{"email" => email, "subject" => subject, "body" => body},
        scheduled_at: DateTime.add(now, index * 250, :millisecond)
      )
    end)
    |> Oban.insert_all()

    Newsletter.record_send(subject, body, length(subscribers), socket.assigns.draft)

    {:noreply,
     socket
     |> put_flash(:info, "Queued #{length(subscribers)} subscribers for delivery.")
     |> assign(:draft, nil)
     |> assign_compose("", "")
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

  def render(assigns) do
    ~H"""
    <.page_head slug="Mail / Newsletter" title="Newsletter">
      <:lede>
        {@subscribers_count} active {if @subscribers_count == 1, do: "subscriber", else: "subscribers"}.
        A broadcast goes out as one queued job per reader.
      </:lede>
      <:actions>
        <.link href={~p"/admin/subscribers/export"} class="adm-btn adm-btn--quiet">
          <.icon name="hero-arrow-down-tray" class="size-4" /> Export CSV
        </.link>
      </:actions>
    </.page_head>

    <.panel title={if @draft, do: "Editing a draft", else: "Compose"}>
      <:actions>
        <button :if={@draft} type="button" phx-click="new_message" class="adm-link">
          <.icon name="hero-plus" class="size-4" /> New message
        </button>
      </:actions>

      <div class="adm-compose">
        <div class="adm-sheet">
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
            <.input
              field={@form[:body]}
              type="textarea"
              label="Body (HTML)"
              placeholder="<p>Hello everyone…</p>"
              rows="14"
              class="adm-input adm-input--code"
              phx-debounce="400"
              required
            />
            <p class="adm-help">
              Basic HTML, set inside the site's paper shell. Each reader's copy carries their own unsubscribe link.
            </p>

            <div class="adm-form-actions">
              <button
                type="submit"
                class="adm-btn adm-btn--primary"
                data-confirm={"Send this to all #{@subscribers_count} active subscribers?"}
              >
                <.icon name="hero-paper-airplane" class="size-4" /> Broadcast to {@subscribers_count}
              </button>
              <button type="button" phx-click="save_draft" class="adm-btn adm-btn--quiet">
                Save draft
              </button>
            </div>
          </.form>

          <form id="newsletter-test-form" phx-submit="send_test" class="adm-test-send">
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
              <button type="submit" class="adm-btn adm-btn--small">
                <.icon name="hero-envelope-open" class="size-4" /> Send test
              </button>
            </div>
          </form>
        </div>

        <div>
          <p class="adm-label">What a reader sees</p>
          <iframe
            id="newsletter-preview"
            class="adm-preview-frame"
            title="Newsletter preview"
            sandbox=""
            srcdoc={@preview}
          >
          </iframe>
        </div>
      </div>
    </.panel>

    <.panel :if={@drafts != []} title="Drafts" count={length(@drafts)}>
      <.rows id="drafts" rows={@drafts}>
        <:col :let={draft} label="Subject" class="adm-cell-title">{draft.subject}</:col>
        <:col :let={draft} label="Saved">{stamp(draft.updated_at)}</:col>
        <:action :let={draft}>
          <button phx-click="open_draft" phx-value-id={draft.id} class="adm-link">Open</button>
        </:action>
        <:action :let={draft}>
          <button
            phx-click="delete_draft"
            phx-value-id={draft.id}
            data-confirm="Delete this draft?"
            class="adm-link adm-link--danger"
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
        <:col :let={sent} label="When">{stamp(sent.sent_at)}</:col>
        <:empty>Nothing sent yet.</:empty>
      </.rows>
    </.panel>

    <.panel title="Subscribers" count={length(@subscribers)}>
      <.rows id="subscribers" rows={@subscribers}>
        <:col :let={sub} label="Email">{sub.email}</:col>
        <:col :let={sub} label="Status">
          <.pill :if={sub.active} tone="live">Active</.pill>
          <.pill :if={!sub.active} tone="quiet">Unsubscribed</.pill>
        </:col>
        <:col :let={sub} label="Joined">{stamp(sub.inserted_at)}</:col>
        <:action :let={sub}>
          <button
            phx-click="delete_subscriber"
            phx-value-id={sub.id}
            data-confirm={"Remove #{sub.email} from the subscriber list? This cannot be undone."}
            class="adm-link adm-link--danger"
            aria-label={"Remove #{sub.email}"}
          >
            <.icon name="hero-trash" class="size-4" /> Remove
          </button>
        </:action>
        <:empty>No subscribers yet.</:empty>
      </.rows>
    </.panel>
    """
  end
end
