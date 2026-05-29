defmodule WebWeb.AdminLive.GuestbookManager do
  use WebWeb, :live_view
  alias Web.General

  def mount(_params, _session, socket) do
    if connected?(socket), do: Web.General.subscribe_guestbook()

    {:ok,
     assign(socket,
       entries: General.list_all_guestbook_entries(),
       page_title: "Manage Guestbook",
       return_to: "/admin/dashboard",
       return_label: "Dashboard"
     )}
  end

  def handle_info({:guestbook_entry_created, entry}, socket) do
    # Prepend new entry to list
    {:noreply, update(socket, :entries, fn entries -> [entry | entries] end)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    entry = General.get_guestbook_entry!(id)
    {:ok, _} = General.delete_guestbook_entry(entry)

    # Remove from list locally to feel snappy, or re-fetch
    {:noreply, assign(socket, :entries, General.list_all_guestbook_entries())}
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="theme-title" style="margin-bottom: 2rem;">Guestbook Manager</h1>

      <div class="glass-panel" style="padding: 2rem;">
        <table style="width: 100%; border-collapse: collapse; color: #ccc;">
          <thead>
            <tr style="border-bottom: 1px solid #444; font-size: 0.9rem; text-align: left;">
              <th style="padding: 1rem;">Date</th>
              <th style="padding: 1rem;">Name</th>
              <th style="padding: 1rem;">Message</th>
              <th style="padding: 1rem;">IP</th>
              <th style="padding: 1rem;">Action</th>
            </tr>
          </thead>
          <tbody>
            <%= for entry <- @entries do %>
              <tr style="border-bottom: 1px solid rgba(255,255,255,0.05);">
                <td style="padding: 1rem; color: #666; font-size: 0.8rem; white-space: nowrap;">
                  {Calendar.strftime(entry.inserted_at, "%Y-%m-%d %H:%M")}
                </td>
                <td style="padding: 1rem; font-weight: bold; color: #fff;">{entry.name}</td>
                <td style="padding: 1rem; max-width: 400px; color: #aaa;">{entry.message}</td>
                <td style="padding: 1rem; font-family: monospace; font-size: 0.8rem;">
                  {if entry.ip_address, do: entry.ip_address, else: "N/A"}
                </td>
                <td style="padding: 1rem;">
                  <button
                    phx-click="delete"
                    phx-value-id={entry.id}
                    data-confirm="Are you sure you want to delete this signature permanently?"
                    class="theme-btn"
                    style="background: #331111; border: 1px solid #552222; color: #ff6666; padding: 0.3rem 0.6rem; font-size: 0.8rem;"
                  >
                    Delete
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>

        <%= if @entries == [] do %>
          <div style="text-align: center; padding: 2rem; color: #666;">No signatures found.</div>
        <% end %>
      </div>
    </div>
    """
  end
end
