defmodule WebWeb.ShareController do
  @moduledoc """
  Serves the share cards `Web.ShareCard` draws: `/share/post/<slug>.png`,
  `/share/frame/<roll>/<n>.jpg` and `/share/roll/<roll>.jpg`.

  The first request for a card draws it; every one after reads the file. The
  page that names a card puts a fingerprint of its source in `?v=`, so the
  response can be cached for a year: a card that changes has a new address.

  A card exists only for a piece that is public. A draft, a frame that was
  never printed and a roll that is not in the archive are all 404, as is a
  card ImageMagick could not draw.
  """

  use WebWeb, :controller

  alias Web.Blog
  alias Web.Negatives
  alias Web.ShareCard

  def post(conn, %{"file" => file}) do
    with {:ok, post} <- Blog.get_post(Path.rootname(file)),
         {:ok, path} <- ShareCard.post(post) do
      send_card(conn, path, "image/png")
    else
      _ -> not_found(conn)
    end
  end

  def frame(conn, %{"roll" => roll, "file" => file}) do
    case ShareCard.frame(roll, Path.rootname(file)) do
      {:ok, path} -> send_card(conn, path, "image/jpeg")
      :error -> not_found(conn)
    end
  end

  def roll(conn, %{"file" => file}) do
    with {:ok, filename} <- Negatives.sheet_for_roll(Path.rootname(file)),
         {:ok, path} <- ShareCard.sheet(%{filename: filename, roll: Path.rootname(file)}) do
      send_card(conn, path, "image/jpeg")
    else
      _ -> not_found(conn)
    end
  end

  defp send_card(conn, path, type) do
    conn
    |> put_resp_content_type(type, nil)
    |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
    |> send_file(200, path)
  end

  defp not_found(conn), do: send_resp(conn, 404, "Not found")
end
