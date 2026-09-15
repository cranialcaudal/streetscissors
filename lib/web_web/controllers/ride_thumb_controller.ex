defmodule WebWeb.RideThumbController do
  use WebWeb, :controller

  alias Web.Rides
  alias Web.Rides.Thumbs

  def show(conn, %{"id" => id}) do
    with ride when not is_nil(ride) <- Rides.get_ride(id),
         true <- Thumbs.exists?(ride) do
      conn
      |> put_resp_content_type("image/jpeg")
      |> put_resp_header("cache-control", "public, max-age=86400")
      |> send_file(200, Thumbs.path(ride))
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> text("Thumbnail not found")
    end
  end
end
