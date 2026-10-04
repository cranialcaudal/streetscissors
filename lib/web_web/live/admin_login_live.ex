defmodule WebWeb.AdminLoginLive do
  use WebWeb, :live_view

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok, push_navigate(socket, to: "/admin/dashboard")}
    else
      {:ok, assign(socket, page_title: "Admin Login")}
    end
  end

  # A dialog over whatever page asked for it: Escape or a click outside goes
  # home. It says its own error; admin.css hides the layout's flash group
  # while the dialog is up, so the message isn't repeated behind it.
  def render(assigns) do
    ~H"""
    <div
      id="login-overlay"
      class="adm-login"
      phx-window-keydown={JS.navigate("/")}
      phx-key="Escape"
    >
      <div class="adm-login-card" phx-click-away={JS.navigate("/")}>
        <button
          type="button"
          class="adm-login-close"
          phx-click={JS.navigate("/")}
          aria-label="Close"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>

        <p class="adm-slug">streetscissors</p>
        <h1 class="adm-title">The composing room</h1>

        <p :if={msg = Phoenix.Flash.get(@flash, :error)} class="adm-login-error" role="alert">
          {msg}
        </p>

        <.form for={%{}} action={~p"/admin/login"} method="post">
          <label class="adm-label" for="admin-password">Password</label>
          <input
            id="admin-password"
            type="password"
            name="password"
            class="adm-input"
            autocomplete="current-password"
            required
            autofocus
          />
          <button type="submit" class="adm-btn adm-btn--primary">Enter</button>
        </.form>

        <div class="adm-login-foot">
          <.link href={~p"/"}>← Return to the site</.link>
        </div>
      </div>
    </div>
    """
  end
end
