defmodule WebWeb.HealthController do
  @moduledoc """
  `GET /health`: one query against the database, and a yes or a no.

  This is what a check from outside asks (`.github/workflows/uptime.yml`), and
  what `Web.Monitor` asks through the proxy. A 200 therefore means the whole
  chain a visitor depends on is standing: the proxy, the application behind
  it, and the database behind that.

  It says nothing else — no version, no uptime, no counts. Anyone can ask it.
  """

  use WebWeb, :controller

  def show(conn, _params) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    case Ecto.Adapters.SQL.query(Web.Repo, "SELECT 1", []) do
      {:ok, _} -> json(conn, %{status: "ok"})
      {:error, _} -> conn |> put_status(:service_unavailable) |> json(%{status: "down"})
    end
  rescue
    # No connection to be had at all is the same answer.
    _ -> conn |> put_status(:service_unavailable) |> json(%{status: "down"})
  end
end
