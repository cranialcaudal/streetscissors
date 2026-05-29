defmodule WebWeb.AdminSessionController do
  use WebWeb, :controller

  def new(conn, _params) do
    render(conn, :new)
  end

  def create(conn, %{"password" => password}) do
    if password == "TunaOn@Bike95811" do
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

  def delete(conn, params) do
    conn
    |> delete_session("admin_user")
    |> configure_session(renew: true)
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: params["redirect_to"] || "/")
  end
end
