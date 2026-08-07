defmodule WebWeb.AdminLoginLive do
  use WebWeb, :live_view

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok, push_navigate(socket, to: "/admin/dashboard")}
    else
      {:ok, assign(socket, page_title: "Admin Login")}
    end
  end

  def render(assigns) do
    ~H"""
    <div
      id="login-overlay"
      class="animate-fade-in"
      style="position: fixed; inset: 0; z-index: 100000; background: rgba(0,0,0,0.7); backdrop-filter: blur(10px); display: flex; align-items: center; justify-content: center; padding: 1rem; overflow-y: auto;"
      phx-window-keydown={JS.navigate("/")}
      phx-key="Escape"
    >
      <div
        class="glass-panel"
        phx-click-away={JS.navigate("/")}
        style="width: 100%; max-width: 400px; padding: 3rem; text-align: center; border: 1px solid rgba(255,102,0,0.4); box-shadow: 0 20px 50px rgba(0,0,0,0.8); background: rgba(10,10,10,0.95); border-radius: 12px; position: relative;"
      >
        <button
          phx-click={JS.navigate("/")}
          style="position: absolute; top: 1.2rem; right: 1.2rem; font-size: 2.5rem; color: #444; background: none; border: none; cursor: pointer; transition: all 0.2s; line-height: 1; display: flex; align-items: center; justify-content: center; width: 44px; height: 44px; border-radius: 50%; z-index: 10;"
          onmouseover="this.style.color='#ff6600'; this.style.background='rgba(255,102,0,0.1)'"
          onmouseout="this.style.color='#444'; this.style.background='transparent'"
        >
          &times;
        </button>

        <h1 style="font-family: var(--font-heading); font-size: 1.2rem; color: #ff6600; letter-spacing: 4px; text-transform: uppercase; margin-bottom: 2rem;">
          Admin Access
        </h1>

        <%= if Phoenix.Flash.get(@flash, :error) do %>
          <div style="background: rgba(255, 107, 107, 0.1); border: 1px solid #ff6b6b; color: #ff6b6b; padding: 1rem; border-radius: 4px; margin-bottom: 2rem; font-size: 0.9rem; letter-spacing: 1px;">
            {Phoenix.Flash.get(@flash, :error)}
          </div>
        <% end %>

        <.form for={%{}} action={~p"/admin/login"} method="post">
          <div style="margin-bottom: 2rem;">
            <input
              type="password"
              name="password"
              placeholder="ENTER PASSWORD"
              required
              autofocus
              style="width: 100%; background: #000; border: 1px solid #333; color: white; padding: 1.2rem; border-radius: 4px; font-size: 1rem; text-align: center; letter-spacing: 2px;"
            />
          </div>

          <button
            type="submit"
            class="theme-btn"
            style="width: 100%; padding: 1.2rem; justify-content: center; font-size: 1rem; border: 1px solid #ff6600; color: #ff6600; background: transparent; letter-spacing: 2px; text-transform: uppercase; font-weight: bold;"
          >
            Enter
          </button>
        </.form>

        <div style="margin-top: 2rem; border-top: 1px solid #222; padding-top: 1.5rem;">
          <.link
            href={~p"/"}
            style="color: #666; font-size: 0.8rem; text-decoration: none; letter-spacing: 2px; text-transform: uppercase;"
          >
            ← return to homepage
          </.link>
        </div>
      </div>
    </div>
    """
  end
end
