defmodule WebWeb.AdminLive.Dashboard do
  use WebWeb, :live_view
  alias Web.Newsletter
  alias Web.Analytics
  alias Web.Contact
  alias Web.SiteSettings

  def mount(_params, session, socket) do
    if session["admin_user"] do
      subscribers = Newsletter.list_subscribers()
      hits_today = Analytics.count_hits_today() || 0
      {total_hits, biweekly_trends} = Analytics.get_biweekly_trends(28)
      unique_today = Analytics.count_unique_visitors_today() || 0
      top_pages = Analytics.top_pages(10)
      messages = Contact.list_messages()

      spotify_playlist_id =
        SiteSettings.get_setting("spotify_playlist_id", "37i9dQZF1DXcBWIGoYBM5M")

      {:ok,
       assign(socket,
         subscribers: subscribers,
         page_title: "Admin Dashboard",
         hits_today: hits_today,
         total_hits: total_hits,
         biweekly_trends: biweekly_trends,
         unique_today: unique_today,
         top_pages: top_pages,
         messages: messages,
         spotify_playlist_id: spotify_playlist_id
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_event("message_status", %{"id" => id, "status" => status}, socket) do
    Contact.update_status(id, status)
    messages = Contact.list_messages()
    {:noreply, assign(socket, messages: messages)}
  end

  def handle_event("delete_message", %{"id" => id}, socket) do
    Contact.delete_message(id)
    messages = Contact.list_messages()
    {:noreply, assign(socket, messages: messages)}
  end

  def handle_event("switch_to_audio", _params, socket) do
    {:noreply, push_navigate(socket, to: "/admin/content?tab=audio")}
  end

  def handle_event("save_settings", %{"spotify_playlist_id" => raw_input}, socket) do
    # 1. Trim whitespace
    input = String.trim(raw_input)

    # 2. Extract ID using Regex (supports URL or direct ID)
    # Matches /playlist/ID or just the entire string if it looks like an ID
    playlist_id =
      case Regex.run(~r/playlist\/([a-zA-Z0-9]+)/, input) do
        [_, id] ->
          id

        nil ->
          # Fallback: assume the input itself is the ID if it doesn't look like a URL
          if String.contains?(input, "spotify.com"), do: input, else: input
      end

    # 3. Save and handle result
    case SiteSettings.put_setting("spotify_playlist_id", playlist_id) do
      {:ok, _setting} ->
        {:noreply,
         socket
         |> assign(spotify_playlist_id: playlist_id)
         |> put_flash(:info, "Settings saved! Playlist ID: #{playlist_id}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save settings.")}
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <h1 class="theme-title" style="margin-bottom: 2rem;">Overview</h1>

      <div class="glass-panel" style="padding: 2rem; margin-top: 2rem;">
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 1rem; margin-bottom: 2rem;">
          <div style="background: rgba(0,0,0,0.3); padding: 1.5rem; border-radius: 8px; text-align: center;">
            <div style="font-size: 2rem; font-weight: bold; color: var(--theme-color);">
              {@unique_today}
            </div>
            <div style="color: #888; font-size: 0.9rem;">Hits Today</div>
            <div style="color: #555; font-size: 0.7rem; margin-top: 0.25rem;">
              Unique hits (24h period)
            </div>
          </div>
          <div style="background: rgba(0,0,0,0.3); padding: 1.5rem; border-radius: 8px; text-align: center;">
            <div style="font-size: 2rem; font-weight: bold; color: #4ade80;">{@hits_today}</div>
            <div style="color: #888; font-size: 0.9rem;">Total Page Views</div>
            <div style="color: #555; font-size: 0.7rem; margin-top: 0.25rem;">Includes reloads</div>
          </div>
          <div style="background: rgba(0,0,0,0.3); padding: 1.5rem; border-radius: 8px; text-align: center;">
            <div style="font-size: 2rem; font-weight: bold; color: #a78bfa;">{@total_hits}</div>
            <div style="color: #888; font-size: 0.9rem;">Aggregate Hits</div>
            <div style="color: #555; font-size: 0.7rem; margin-top: 0.25rem;">
              Last 28 bi-weekly periods
            </div>
          </div>
        </div>

        <div style="margin-bottom: 2rem;">
          <h3 style="color: #ddd;">Bi-Weekly Trend (28 Bins)</h3>
          <div style="display: flex; align-items: flex-end; gap: 4px; height: 100px; padding-top: 1rem; padding-bottom: 0.5rem; overflow-x: auto;">
            <%= for {start_date, _end, count} <- @biweekly_trends do %>
              <% max_h = Enum.max(Enum.map(@biweekly_trends, fn {_, _, c} -> c end)) %>
              <% max_h = if max_h == 0, do: 1, else: max_h %>
              <% height = trunc(count / max_h * 100) %>
              <div
                style={"width: 100%; min-width: 10px; background: " <> (if count > 0, do: "#a78bfa", else: "#333") <> "; height: #{max(height, 2)}%; border-radius: 2px 2px 0 0; position: relative;"}
                title={"#{Calendar.strftime(start_date, "%b %d")}: #{count}"}
              >
              </div>
            <% end %>
          </div>
        </div>

        <div style="margin-bottom: 2rem;">
          <h3 style="color: #ddd;">Top Pages</h3>
          <ul style="list-style: none; padding: 0;">
            <%= for {path, count} <- @top_pages do %>
              <li style="display: flex; justify-content: space-between; padding: 0.5rem 0; border-bottom: 1px solid #333;">
                <span style="color: #ccc; font-family: monospace;">{path}</span>
                <span style="color: #888;">{count} hits</span>
              </li>
            <% end %>
          </ul>
        </div>
      </div>
      
    <!-- Inbox Section -->
      <div class="glass-panel" style="padding: 2rem; margin-top: 2rem;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 1.5rem;">
          <h2 class="theme-subtitle" style="margin: 0;">Inbox</h2>
        </div>

        <div style="display: flex; flex-direction: column; gap: 2rem;">
          <!-- Needs Attention -->
          <div>
            <h3 style="color: #ff6b6b; font-size: 1rem; border-bottom: 1px solid #333; padding-bottom: 0.5rem; margin-bottom: 1rem;">
              Needs Attention
            </h3>
            <%= for msg <- Enum.filter(@messages, & &1.status == "attention") do %>
              <.message_card msg={msg} />
            <% end %>
            <%= if Enum.empty?(Enum.filter(@messages, & &1.status == "attention")) do %>
              <p style="color: #666; font-size: 0.9rem; font-style: italic;">
                No items needing attention.
              </p>
            <% end %>
          </div>
          
    <!-- Inbox -->
          <div>
            <h3 style="color: #4ade80; font-size: 1rem; border-bottom: 1px solid #333; padding-bottom: 0.5rem; margin-bottom: 1rem;">
              Inbox
            </h3>
            <%= for msg <- Enum.filter(@messages, & &1.status == "inbox") do %>
              <.message_card msg={msg} />
            <% end %>
            <%= if Enum.empty?(Enum.filter(@messages, & &1.status == "inbox")) do %>
              <p style="color: #666; font-size: 0.9rem; font-style: italic;">Inbox empty.</p>
            <% end %>
          </div>
          
    <!-- Archive -->
          <div>
            <h3 style="color: #888; font-size: 1rem; border-bottom: 1px solid #333; padding-bottom: 0.5rem; margin-bottom: 1rem;">
              Archive
            </h3>
            <%= for msg <- Enum.filter(@messages, & &1.status == "archive") |> Enum.take(5) do %>
              <.message_card msg={msg} />
            <% end %>
            <%= if Enum.count(Enum.filter(@messages, & &1.status == "archive")) > 5 do %>
              <p style="color: #666; font-size: 0.8rem; margin-top: 0.5rem;">
                ... and {Enum.count(Enum.filter(@messages, &(&1.status == "archive"))) - 5} more archived messages.
              </p>
            <% end %>
          </div>
        </div>
      </div>

      <div class="glass-panel" style="padding: 2rem; margin-top: 2rem;">
        <h2 class="theme-subtitle" style="margin-top: 0;">
          Newsletter Subscribers ({length(@subscribers)})
        </h2>

        <div style="margin-top: 1.5rem; overflow-x: auto;">
          <table style="width: 100%; border-collapse: collapse; color: #ddd;">
            <thead>
              <tr style="border-bottom: 2px solid #333; text-align: left;">
                <th style="padding: 0.75rem;">Email</th>
                <th style="padding: 0.75rem;">Status</th>
                <th style="padding: 0.75rem;">Joined</th>
              </tr>
            </thead>
            <tbody>
              <%= for sub <- @subscribers do %>
                <tr style="border-bottom: 1px solid #222;">
                  <td style="padding: 0.75rem;">{sub.email}</td>
                  <td style="padding: 0.75rem;">
                    <%= if sub.active do %>
                      <span style="color: #4ade80;">Active</span>
                    <% else %>
                      <span style="color: #f87171;">Unsubscribed</span>
                    <% end %>
                  </td>
                  <td style="padding: 0.75rem; color: #888;">
                    {Calendar.strftime(sub.inserted_at, "%Y-%m-%d %H:%M")}
                  </td>
                </tr>
              <% end %>
              <%= if Enum.empty?(@subscribers) do %>
                <tr>
                  <td colspan="3" style="padding: 2rem; text-align: center; color: #666;">
                    No subscribers yet.
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <div style="margin-top: 2rem; padding-top: 2rem; border-top: 1px solid #333;">
          <p style="color: #aaa; font-size: 0.9rem;">
            To export: Currently just copy-paste the table above. CSV export coming soon.
          </p>
        </div>
      </div>

      <div class="glass-panel" style="padding: 2rem; margin-top: 2rem;">
        <h2 class="theme-subtitle" style="margin-top: 0;">Site Settings</h2>

        <form phx-submit="save_settings" style="margin-top: 1rem;">
          <label style="display: block; margin-bottom: 0.5rem; color: #ccc;">
            Spotify Playlist ID (or URL)
          </label>
          <div style="display: flex; gap: 1rem;">
            <input
              type="text"
              name="spotify_playlist_id"
              value={@spotify_playlist_id}
              class="glass-input"
              style="flex: 1;"
              placeholder="Paste Spotify Playlist URL or ID here..."
            />
            <button type="submit" class="theme-btn">Save Setting</button>
          </div>
          <p style="color: #666; font-size: 0.8rem; margin-top: 0.5rem;">
            Updates the bottom-left player. Changes take effect on next page load.
          </p>
        </form>
      </div>
    </div>
    """
  end

  defp message_card(assigns) do
    ~H"""
    <div style={"padding: 1rem; background: rgba(255,255,255,0.05); border-radius: 6px; margin-bottom: 1rem; border-left: 3px solid " <> case @msg.status do "attention" -> "#ff6b6b"; "inbox" -> "#4ade80"; _ -> "#666" end}>
      <div style="display: flex; justify-content: space-between; margin-bottom: 0.5rem; align-items: flex-start;">
        <div>
          <span style="font-weight: bold; color: white;">{@msg.name}</span>
          <span style="font-weight: normal; color: #888; display: block; font-size: 0.85rem;">
            {@msg.email}
          </span>
        </div>
        <span style="font-size: 0.75rem; color: #666;">
          {Calendar.strftime(@msg.inserted_at, "%Y-%m-%d %H:%M")}
        </span>
      </div>
      <p style="color: #ddd; white-space: pre-wrap; margin: 0.5rem 0 1rem 0; font-size: 0.95rem;">
        {@msg.message}
      </p>

      <div style="display: flex; gap: 0.5rem;">
        <%= if @msg.status != "inbox" do %>
          <button
            phx-click="message_status"
            phx-value-id={@msg.id}
            phx-value-status="inbox"
            style="font-size: 0.75rem; background: #333; color: #ccc; border: none; padding: 0.3rem 0.6rem; border-radius: 4px; cursor: pointer;"
          >
            Move to Inbox
          </button>
        <% end %>
        <%= if @msg.status != "attention" do %>
          <button
            phx-click="message_status"
            phx-value-id={@msg.id}
            phx-value-status="attention"
            style="font-size: 0.75rem; background: #5a2525; color: #ffadad; border: none; padding: 0.3rem 0.6rem; border-radius: 4px; cursor: pointer;"
          >
            Needs Attention
          </button>
        <% end %>
        <%= if @msg.status != "archive" do %>
          <button
            phx-click="message_status"
            phx-value-id={@msg.id}
            phx-value-status="archive"
            style="font-size: 0.75rem; background: #333; color: #888; border: none; padding: 0.3rem 0.6rem; border-radius: 4px; cursor: pointer;"
          >
            Archive
          </button>
        <% else %>
          <button
            phx-click="delete_message"
            phx-value-id={@msg.id}
            data-confirm="Delete this message? This cannot be undone."
            style="font-size: 0.75rem; background: #7f1d1d; color: #fecaca; border: none; padding: 0.3rem 0.6rem; border-radius: 4px; cursor: pointer;"
          >
            Delete
          </button>
        <% end %>
      </div>
    </div>
    """
  end
end
