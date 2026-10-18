defmodule WebWeb.DarkroomController do
  @moduledoc """
  The print editor's pictures (`Web.Darkroom.Session`), to the admin session
  alone. A picture is asked for by its session's token and its own name, each
  held to the only shape it has, so nothing else on disk can be named.
  """

  use WebWeb, :controller

  alias Web.Darkroom.Session

  def picture(conn, %{"token" => token, "file" => file}) do
    with true <- !!get_session(conn, "admin_user"),
         {:ok, dir} <- Session.dir(token),
         true <- Regex.match?(~r/\A(?:p-\d+|before)\.jpg\z/, file),
         path = Path.join(dir, file),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type("image/jpeg", nil)
      |> put_resp_header("cache-control", "private, max-age=600")
      |> send_file(200, path)
    else
      _ -> WebWeb.NotFound.render(conn)
    end
  end
end
