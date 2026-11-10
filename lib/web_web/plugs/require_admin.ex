defmodule WebWeb.Plugs.RequireAdmin do
  @moduledoc """
  Halts a request with the site's 404 unless the session carries the admin flag.

  The router's `:admin_only` pipeline is this plug. It stands in front of the
  admin's controller routes, which a `live_session`'s `on_mount` hooks do not
  cover, and in front of the `/dev` scope (LiveDashboard and the Swoosh mailbox
  preview). `/dev` is compiled out wherever `dev_routes` is off, but that is a
  compile-time flag: a stale build, or a server started without `.env`, would
  serve those pages, so the session is checked at run time as well.

  The answer is `WebWeb.NotFound.render/1`, so an admin address asked for
  without a session looks like an address that does not exist.
  `WebWeb.Plugs.SetCurrentUser` does not protect routes: it only tells the
  templates whether the admin is looking.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    if get_session(conn, "admin_user") do
      conn
    else
      conn |> WebWeb.NotFound.render() |> halt()
    end
  end
end
