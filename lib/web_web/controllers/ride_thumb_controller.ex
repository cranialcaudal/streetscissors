defmodule WebWeb.RideThumbController do
  @moduledoc """
  Serves a ride's cached route image (`Web.Rides.Thumbs`): Komoot's static
  map of the tour as it draws it for a stranger. A ride with none cached, and
  a ride that is not clear (`Web.Rides.clear?/1`), are both 404.

  The image is named on disk for the map URL it came from, so the address a
  page uses carries that name's fingerprint as `?v=` and a re-cut route is a
  new address rather than a day of the old picture out of a cache.
  """

  use WebWeb, :controller

  alias Web.Rides
  alias Web.Rides.Thumbs

  def show(conn, %{"id" => id}) do
    with %{} = ride <- Rides.get_ride(id),
         true <- Rides.thumb?(ride) do
      conn
      |> put_resp_content_type("image/jpeg", nil)
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
