defmodule WebWeb.AdminLive.Newsletter do
  use WebWeb, :live_view
  alias Web.Newsletter
  alias Web.Email
  alias Web.Mailer

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Newsletter Admin",
       return_to: "/admin/dashboard",
       return_label: "back to dashboard",
       form: to_form(%{"subject" => "", "body" => ""}),
       subscribers_count: length(Newsletter.list_active_emails()),
       drafts: Newsletter.list_drafts(),
       sending: false
     )}
  end

  def handle_event("validate", %{"subject" => subject, "body" => body}, socket) do
    {:noreply, assign(socket, form: to_form(%{"subject" => subject, "body" => body}))}
  end

  def handle_event("send", %{"subject" => subject, "body" => body}, socket) do
    subscribers = Newsletter.list_active_emails()

    # Send asynchronously (Fire and Forget)
    Task.Supervisor.start_child(Web.TaskSupervisor, fn ->
      require Logger
      Logger.info("Starting newsletter broadcast to #{length(subscribers)} subscribers")

      for email <- subscribers do
        result =
          email
          |> Email.newsletter(subject, body)
          |> Mailer.deliver()

        Logger.info("Sent to #{email}: #{inspect(result)}")
        # Small delay between sends
        Process.sleep(500)
      end

      Logger.info("Newsletter broadcast complete")
    end)

    # Mark draft as sent if it exists in the assigns (optional, logic needed if we track specific drafts)
    # For now, just logging or relying on the async task is enough for the UI update.

    {:noreply,
     socket
     |> put_flash(:info, "Broadcasting to #{length(subscribers)} subscribers in the background.")
     |> assign(form: to_form(%{"subject" => "", "body" => ""}))}
  end

  def handle_event("load_draft", %{"id" => id}, socket) do
    draft = Web.Repo.get!(Web.Newsletter.Draft, id)
    {:noreply, assign(socket, form: to_form(%{"subject" => draft.subject, "body" => draft.body}))}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="theme-title" style="margin-bottom: 2rem;">Compose Newsletter</h1>

      <div class="glass-panel" style="padding: 2rem; margin-top: 2rem;">
        <div style="margin-bottom: 2rem; color: #888;">
          Targeting <span style="color: #4ade80; font-weight: bold;">{@subscribers_count}</span>
          active subscribers.
        </div>

        <%= if Enum.any?(@drafts) do %>
          <div style="margin-bottom: 2rem; background: rgba(255,255,255,0.05); padding: 1rem; border-radius: 6px;">
            <h3 style="color: #ddd; margin-top: 0; font-size: 1rem;">AI Drafts</h3>
            <div style="display: flex; gap: 0.5rem; flex-wrap: wrap;">
              <%= for draft <- @drafts do %>
                <button
                  phx-click="load_draft"
                  phx-value-id={draft.id}
                  style="background: #333; color: #ccc; border: 1px solid #555; padding: 0.5rem; border-radius: 4px; cursor: pointer;"
                >
                  Load: {draft.subject}
                  <span style="font-size: 0.75rem; color: #888; display: block;">
                    {Calendar.strftime(draft.inserted_at, "%m/%d %H:%M")}
                  </span>
                </button>
              <% end %>
            </div>
          </div>
        <% end %>

        <.form
          for={@form}
          id="newsletter-form"
          phx-change="validate"
          phx-submit="send"
          style="display: flex; flex-direction: column; gap: 1.5rem;"
        >
          <div>
            <label style="display: block; color: #ccc; margin-bottom: 0.5rem;">Subject</label>
            <.input
              field={@form[:subject]}
              type="text"
              placeholder="Updates from StreetScissors..."
              required
              style="width: 100%; background: #2a2a2a; border: 1px solid #444; color: white; padding: 0.8rem; border-radius: 6px;"
            />
          </div>

          <div>
            <label style="display: block; color: #ccc; margin-bottom: 0.5rem;">
              Body (HTML supported)
            </label>
            <.input
              field={@form[:body]}
              type="textarea"
              placeholder="Hello everyone..."
              required
              rows="10"
              style="width: 100%; background: #2a2a2a; border: 1px solid #444; color: white; padding: 0.8rem; border-radius: 6px; font-family: monospace;"
            />
            <p style="color: #666; font-size: 0.8rem; margin-top: 0.5rem;">
              Basic HTML tags are supported.
            </p>
          </div>

          <button
            type="submit"
            class="theme-btn"
            data-confirm="Are you sure you want to send this to all subscribers?"
            style="background: #a78bfa; color: white; padding: 1rem; border: none; font-size: 1.1rem; cursor: pointer;"
          >
            <i class="fas fa-paper-plane" style="margin-right: 0.5rem;"></i> Broadcast Newsletter
          </button>
        </.form>
      </div>
    </div>
    """
  end
end
