defmodule WebWeb.FitnessPhotoController do
  @moduledoc """
  Serves a progress photograph (`Web.Fitness.Photos`) to the admin session
  and to no one else: anyone else, and any address that is not a stored
  photograph, gets the site's 404. Never cached by a shared cache.
  """
  use WebWeb, :controller

  alias Web.Fitness.Photos

  def show(conn, %{"date" => date, "file" => file}) do
    with true <- get_session(conn, "admin_user") == true,
         {:ok, path} <- Photos.path(date, file) do
      conn
      |> put_resp_content_type(MIME.from_path(path), nil)
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-robots-tag", "noindex, nofollow")
      |> send_file(200, path)
    else
      _ -> WebWeb.NotFound.render(conn)
    end
  end
end
