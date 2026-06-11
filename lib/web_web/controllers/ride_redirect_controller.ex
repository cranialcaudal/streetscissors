defmodule WebWeb.RideRedirectController do
  use WebWeb, :controller

  def index(conn, _params) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/fitness/rides")
  end

  def show(conn, %{"id" => id}) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: ~p"/fitness/rides/#{id}")
  end
end
