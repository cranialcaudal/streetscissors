defmodule WebWeb.AdminAuth do
  @moduledoc """
  LiveView `on_mount` hook that restricts a `live_session` to authenticated
  admins.

  It mirrors the session flag (`"admin_user"`) set by
  `WebWeb.AdminSessionController`. Unauthenticated visitors are halted and
  redirected to the homepage before the LiveView mounts, so admin routes are
  protected centrally rather than relying on each LiveView's own `mount/3`
  check.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:ensure_admin, _params, session, socket) do
    if session["admin_user"] do
      {:cont, assign(socket, :admin_mode, true)}
    else
      {:halt, redirect(socket, to: "/")}
    end
  end
end
