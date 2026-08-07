defmodule WebWeb.Plugs.RequireAdmin do
  @moduledoc """
  Halts a request unless the session carries an admin flag.

  This exists as a **runtime** backstop for the `/dev` scope (LiveDashboard and
  the Swoosh mailbox preview). Those routes are normally compiled out via
  `dev_routes`, but that is a compile-time flag read from the environment — a
  stale build, or a server started without `.env`, would silently ship them to
  the public again. It has happened: `/dev/dashboard` was reachable
  unauthenticated on the live site.

  `SetCurrentUser` deliberately does *not* protect routes (it only exposes
  `@admin_mode` to templates), so this is a separate plug rather than a change
  to that one.
  """

  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, "admin_user") do
      conn
    else
      conn
      |> put_status(:not_found)
      |> put_view(WebWeb.ErrorHTML)
      |> put_root_layout(false)
      |> put_layout(false)
      |> render("404.html")
      |> halt()
    end
  end
end
