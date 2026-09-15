defmodule WebWeb.AdminLive.Newsletter do
  use WebWeb, :live_view
  alias Web.Newsletter
  alias Web.Workers.NewsletterSender

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Newsletter Admin",
       return_to: "/admin/dashboard",
       return_label: "back to dashboard",
       form: to_form(%{"subject" => "", "body" => ""}),
       subscribers_count: length(Newsletter.list_active_emails()),
       sent: Newsletter.list_sent()
     )}
  end

  def handle_event("validate", %{"subject" => subject, "body" => body}, socket) do
    {:noreply, assign(socket, form: to_form(%{"subject" => subject, "body" => body}))}
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

    Newsletter.record_send(subject, body, length(subscribers))

    {:noreply,
     socket
     |> put_flash(:info, "Queued #{length(subscribers)} subscribers for delivery.")
     |> assign(
       form: to_form(%{"subject" => "", "body" => ""}),
       sent: Newsletter.list_sent()
     )}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="theme-title" style="margin-bottom: 2rem;">Compose Newsletter</h1>

      <div class="glass-panel" style="padding: 2rem; margin-top: 2rem;">
        <div style="margin-bottom: 2rem; color: var(--ink-3);">
          Targeting
          <span style="color: var(--color-jade); font-weight: bold;">{@subscribers_count}</span>
          active subscribers.
        </div>

        <.form
          for={@form}
          id="newsletter-form"
          phx-change="validate"
          phx-submit="send"
          style="display: flex; flex-direction: column; gap: 1.5rem;"
        >
          <div>
            <label style="display: block; color: var(--ink-2); margin-bottom: 0.5rem;">Subject</label>
            <.input
              field={@form[:subject]}
              type="text"
              placeholder="Updates from StreetScissors..."
              required
              class="glass-input"
              style="padding: 0.8rem;"
            />
          </div>

          <div>
            <label style="display: block; color: var(--ink-2); margin-bottom: 0.5rem;">
              Body (HTML supported)
            </label>
            <.input
              field={@form[:body]}
              type="textarea"
              placeholder="Hello everyone..."
              required
              rows="10"
              class="glass-input"
              style="padding: 0.8rem;"
            />
            <p style="color: var(--ink-3); font-size: 0.8rem; margin-top: 0.5rem;">
              Basic HTML tags are supported. Sent inside the site's newsletter template.
            </p>
          </div>

          <button
            type="submit"
            class="theme-btn btn-submit"
            data-confirm="Are you sure you want to send this to all subscribers?"
            style="padding: 1rem; font-size: 1.1rem;"
          >
            <.icon name="hero-paper-airplane" class="size-4 mr-2" /> Broadcast Newsletter
          </button>
        </.form>
      </div>

      <div class="glass-panel" style="padding: 2rem; margin-top: 2rem;">
        <h2 class="theme-subtitle" style="margin-top: 0;">Send History</h2>

        <%= if Enum.empty?(@sent) do %>
          <p style="color: var(--ink-3);">No newsletters sent yet.</p>
        <% else %>
          <div style="display: flex; flex-direction: column; gap: 0.75rem;">
            <%= for draft <- @sent do %>
              <div style="display: flex; align-items: baseline; justify-content: space-between; gap: 1rem; padding: 0.75rem 0; border-bottom: 1px solid var(--hairline);">
                <span style="color: var(--ink);">{draft.subject}</span>
                <span style="color: var(--ink-3); font-family: var(--font-data); font-size: 0.85rem; white-space: nowrap;">
                  {draft.recipient_count} sent · {Calendar.strftime(draft.sent_at, "%Y-%m-%d %H:%M")}
                </span>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
