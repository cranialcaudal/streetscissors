defmodule WebWeb.AdminSessionController do
  @moduledoc """
  Logging the admin in and out.

  There is one admin and one password (`ADMIN_PASSWORD`, or `dev-admin` in
  development). The check is a constant-time comparison (so its timing reveals
  nothing), and each address gets ten attempts per 15 minutes (so the password
  cannot be guessed by trying). A correct password sets `session["admin_user"] =
  true` in the signed session cookie. Every admin page checks that flag
  (`WebWeb.AdminAuth`), and so does the pipeline in front of the admin's
  controller routes (`WebWeb.Plugs.RequireAdmin`).

  Logging in also gives the session a `live_socket_id`, the name every
  LiveView socket opened with that cookie answers to. Logging out is a
  `DELETE`, so no link or picture on another page can do it in the admin's
  name. It takes the flag out of the cookie and then tells that name to
  disconnect: the pages open in the browser's other tabs lose their sockets
  at once, load again within a few seconds, and are turned away like anyone
  else.

  The cookie is signed and not kept on the server, so logging out ends the
  session in the browser that asked and nowhere else: a copy of the cookie
  made before stays good until it expires.

  Logging in also marks the browser as the author's (`WebWeb.OwnerMark`), so
  its reading stops being counted for good. Logging out deliberately does not
  undo that, since it means "stop showing me the admin", not "start counting
  me".
  """

  use WebWeb, :controller

  # A single shared password with no lockout is one long brute-force away from
  # being guessed. Ten attempts per IP per 15 minutes leaves normal typos
  # unaffected and makes an online guessing attack pointless.
  @attempt_limit 10
  @attempt_window :timer.minutes(15)

  def create(conn, %{"password" => password}) do
    case Web.RateLimit.hit("admin_login:#{WebWeb.Visitor.ip(conn)}",
           limit: @attempt_limit,
           window: @attempt_window
         ) do
      {:error, :rate_limited, retry_after} ->
        conn
        |> put_flash(:error, "Too many attempts. Try again in #{retry_after}s.")
        |> redirect(to: "/admin/login")

      {:ok, _remaining} ->
        if valid_password?(password) do
          conn
          |> put_session("admin_user", true)
          |> put_session("live_socket_id", live_socket_id(conn))
          |> configure_session(renew: true)
          |> WebWeb.OwnerMark.mark()
          |> redirect(to: "/admin/dashboard")
        else
          conn
          |> put_flash(:error, "Wrong password")
          |> redirect(to: "/admin/login")
        end
    end
  end

  # Constant-time comparison against the configured password to avoid
  # leaking information via timing. Returns false if no password is configured.
  defp valid_password?(password) when is_binary(password) do
    case Application.get_env(:web, :admin_password) do
      expected when is_binary(expected) and expected != "" ->
        Plug.Crypto.secure_compare(password, expected)

      _ ->
        false
    end
  end

  defp valid_password?(_), do: false

  # The name this browser's LiveView sockets answer to
  # (`Phoenix.LiveView.Socket.id/1` reads it from the session). A browser that
  # logs in while it is already in keeps the one it has, so none of its tabs
  # is left under a name the logout no longer knows.
  defp live_socket_id(conn) do
    get_session(conn, "live_socket_id") ||
      "admin_sessions:" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end

  def delete(conn, _params) do
    live_socket_id = get_session(conn, "live_socket_id")

    conn =
      conn
      |> delete_session("admin_user")
      |> delete_session("live_socket_id")
      |> configure_session(renew: true)
      |> put_flash(:info, "Logged out successfully.")
      |> redirect(to: "/")

    # After the reply and not before it. A dropped socket comes back (the
    # client reconnects, or loads its page again a few seconds on), and by
    # then the browser has to hold the cookie without the flag, or it would
    # be let in again. A session from before logins carried a name has none
    # to tell: its open pages last until they are next loaded.
    if live_socket_id, do: WebWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})

    conn
  end
end
