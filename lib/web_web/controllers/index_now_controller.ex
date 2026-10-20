defmodule WebWeb.IndexNowController do
  @moduledoc """
  `GET /indexnow.txt`: the IndexNow key, which proves to the search engines
  that a ping naming this file came from the site (`Web.IndexNow`). A 404
  while `INDEXNOW_KEY` is unset.
  """

  use WebWeb, :controller

  def show(conn, _params) do
    case Web.IndexNow.key() do
      nil -> send_resp(conn, 404, "")
      key -> conn |> put_resp_content_type("text/plain") |> send_resp(200, key)
    end
  end
end
