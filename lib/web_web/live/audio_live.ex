defmodule WebWeb.AudioLive do
  use WebWeb, :live_view
  alias Web.Audio
  import WebWeb.Navigation, only: [return_context: 1]

  def mount(params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Web.PubSub, "audio_logs")

    # Filter for published only
    logs = Audio.list_logs() |> Enum.filter(& &1.published)

    # Get play counts for display
    play_counts = Audio.get_all_play_counts()

    # Get client IP from session or connection
    client_ip = get_connect_info(socket, :peer_data)[:address] |> format_ip()

    {return_to, return_label} = return_context(Map.get(params, "from"))

    socket =
      socket
      |> assign(:page_title, "Captain's Logs")
      |> assign(:logs, logs)
      |> assign(:play_counts, play_counts)
      |> assign(:client_ip, client_ip)
      |> assign(:return_to, return_to)
      |> assign(:return_label, return_label)

    {:ok, socket}
  end

  def handle_event("track_play", %{"id" => id}, socket) do
    audio_log_id = String.to_integer(id)
    ip = socket.assigns.client_ip || "unknown"

    # Record the play
    Audio.record_play(audio_log_id, ip)

    # Update play counts
    play_counts = Audio.get_all_play_counts()

    {:noreply, assign(socket, :play_counts, play_counts)}
  end

  defp format_ip(nil), do: nil
  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip) when is_tuple(ip), do: :inet.ntoa(ip) |> to_string()
  defp format_ip(_), do: nil

  def render(assigns) do
    ~H"""
    <div class="container" style="padding-top: 5vh;">
      <header class="theme-header" style="margin-bottom: 2rem;">
        <h1 class="theme-title" style="margin-top: 0.5rem;">Captain's Logs</h1>
      </header>

      <div style="display: grid; gap: 1.5rem;">
        <%= for log <- @logs do %>
          <div
            class="glass-panel"
            style="padding: 0; overflow: hidden; display: flex; flex-direction: column;"
          >
            <!-- VLC-like Player Header -->
            <div style="background: #e0e0e0; color: #333; padding: 0.5rem 1rem; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #999;">
              <span style="font-size: 0.85rem; font-weight: bold;">
                {log.title}.mp3 - VLC media player
              </span>
              <div style="display: flex; gap: 0.5rem; align-items: center;">
                <span style="font-size: 0.7rem; color: #666; margin-right: 0.5rem;">
                  <.icon name="hero-play" class="size-4" /> {Map.get(@play_counts, log.id, 0)}
                </span>
                <div style="width: 10px; height: 10px; border-radius: 50%; background: #999;"></div>
                <div style="width: 10px; height: 10px; border-radius: 50%; background: #999;"></div>
                <div style="width: 10px; height: 10px; border-radius: 50%; background: #999;"></div>
              </div>
            </div>
            
    <!-- Player Body -->
            <div style="padding: 1.5rem; background: #000; color: white; display: flex; align-items: center; gap: 1rem; position: relative;">
              <!-- Cone Icon -->
              <div style="width: 60px; display: flex; flex-direction: column; align-items: center; justify-content: center; opacity: 0.8;">
                <i class="fas fa-traffic-cone" style="font-size: 2.5rem; color: #ff8800;"></i>
              </div>

              <div style="flex-grow: 1;">
                <div style="display: flex; justify-content: space-between; margin-bottom: 0.5rem;">
                  <span style="font-family: monospace;">SD {log.stardate}</span>
                  <span style="font-family: monospace; color: #888;">Audio File</span>
                </div>

                <audio
                  id={"audio-player-#{log.id}"}
                  controls
                  src={log.file_path}
                  phx-hook="AudioPlayTracker"
                  data-log-id={log.id}
                  style="width: 100%; height: 30px; border-radius: 0; filter: invert(1); opacity: 0.9;"
                  preload="metadata"
                >
                </audio>
              </div>
            </div>
          </div>
        <% end %>

        <%= if Enum.empty?(@logs) do %>
          <div style="text-align: center; padding: 3rem; color: #666;">
            No transmissions found.
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
