defmodule WebWeb.RideRedirectController do
  @moduledoc """
  Sends old ride addresses on to where rides live now. `/rides` and
  `/rides/:id` were the activities' first home and move permanently (301) to
  `/fitness/rides`. `/live` is a temporary (302) redirect, because that short
  address may be used for something else one day.
  """

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

  # Deliberately a 302 — the short path may point elsewhere someday.
  def live(conn, _params) do
    redirect(conn, to: ~p"/fitness/rides")
  end
end
