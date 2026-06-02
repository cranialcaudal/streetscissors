defmodule WebWeb.AdminSessionController do
  use WebWeb, :controller

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"password" => password}) do
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
