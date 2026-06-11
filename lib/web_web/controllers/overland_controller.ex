defmodule WebWeb.OverlandController do
  @moduledoc """
  Receives GPS batches from the Overland iOS app for live ride tracking.

  Overland POSTs `{"locations": [GeoJSON features]}` and requires a 200 with
  `{"result": "ok"}` to clear its on-device queue — any other response makes
  it retry the batch forever, so after auth we always acknowledge, even when
  no ride is active.
  """
  use WebWeb, :controller

  def create(conn, params) do
    if authorized?(conn, params) do
      Web.Rides.ingest_locations(List.wrap(params["locations"]))
      json(conn, %{result: "ok"})
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{result: "error"})
    end
  end

  # Token comes from the receiver URL query string (Overland's natural
  # carrier) or an Authorization: Bearer header.
  defp authorized?(conn, params) do
    expected = Application.get_env(:web, :overland_token)
    provided = params["token"] || bearer_token(conn)

    is_binary(expected) and expected != "" and is_binary(provided) and
      Plug.Crypto.secure_compare(provided, expected)
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> token
      _ -> nil
    end
  end
end
