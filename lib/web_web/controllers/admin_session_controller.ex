defmodule WebWeb.AdminSessionController do
  use WebWeb, :controller

  # A single shared password with no lockout is one long brute-force away from
  # being guessed. Ten attempts per IP per 15 minutes leaves normal typos
  # unaffected and makes an online guessing attack pointless.
  @attempt_limit 10
  @attempt_window :timer.minutes(15)

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"password" => password}) do
    case Web.RateLimit.hit("admin_login:#{client_ip(conn)}",
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
          |> configure_session(renew: true)
          |> redirect(to: "/admin/dashboard")
        else
          conn
          |> put_flash(:error, "Wrong password")
          |> redirect(to: "/admin/login")
        end
    end
  end

  # Caddy fronts the app, so remote_ip is always the proxy — the real client is
  # the first entry of x-forwarded-for.
  defp client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [value | _] -> value |> String.split(",") |> List.first() |> String.trim()
      [] -> conn.remote_ip |> :inet.ntoa() |> to_string()
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

  def delete(conn, params) do
    conn
    |> delete_session("admin_user")
    |> configure_session(renew: true)
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: params["redirect_to"] || "/")
  end
end
