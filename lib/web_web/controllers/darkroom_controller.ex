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

  @doc "A frame's repair mask, to the admin, for the editor to paint on."
  def mask(conn, %{"roll" => roll, "frame" => frame}) do
    with true <- !!get_session(conn, "admin_user"),
         {:ok, dir} <- Web.Negatives.roll_dir(roll),
         {frame, ""} <- Integer.parse(frame),
         path = Web.Darkroom.mask_path(dir, frame),
         true <- File.regular?(path) do
      conn
      |> put_resp_content_type("image/png", nil)
      |> put_resp_header("cache-control", "private, no-store")
      |> send_file(200, path)
    else
      _ -> WebWeb.NotFound.render(conn)
    end
  end

  @doc """
  A frame as it was developed, marks and all, 2000 pixels on its long side,
  for the repair mask to be painted over. Made on request.
  """
  def developed(conn, %{"roll" => roll, "frame" => frame}) do
    with true <- !!get_session(conn, "admin_user"),
         {:ok, dir} <- Web.Negatives.roll_dir(roll),
         {frame, ""} <- Integer.parse(frame),
         base = Web.Darkroom.base_path(dir, frame),
         path = if(File.regular?(base), do: base, else: Web.Darkroom.print_path(dir, frame)),
         true <- File.regular?(path),
         {jpeg, 0} <-
           System.cmd(Web.Negatives.magick_bin(), [
             path,
             "-resize",
             "2000x2000>",
             "-quality",
             "88",
             "jpg:-"
           ]) do
      conn
      |> put_resp_content_type("image/jpeg", nil)
      |> put_resp_header("cache-control", "private, no-store")
      |> send_resp(200, jpeg)
    else
      _ -> WebWeb.NotFound.render(conn)
    end
  end
end
