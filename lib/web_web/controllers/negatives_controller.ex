defmodule WebWeb.NegativesController do
  use WebWeb, :controller

  alias Web.Negatives

  def serve_image(conn, %{"filename" => filename}) do
    case Negatives.image_path(filename) do
      {:ok, path} -> send_image(conn, path)
      :error -> not_found(conn)
    end
  end

  def serve_preview(conn, %{"filename" => filename}) do
    case Negatives.preview_path(filename) do
      {:ok, path} -> send_image(conn, path)
      :error -> not_found(conn)
    end
  end

  def serve_frame(conn, %{"roll" => roll, "frame" => frame}) do
    case Negatives.frame_preview_path(roll, frame) do
      {:ok, path} -> send_image(conn, path)
      :error -> not_found(conn)
    end
  end

  defp send_image(conn, path) do
    content_type =
      case Path.extname(path) |> String.downcase() do
        ".png" -> "image/png"
        ".jpg" -> "image/jpeg"
        ".jpeg" -> "image/jpeg"
        ".webp" -> "image/webp"
        ".tif" -> "image/tiff"
        ".tiff" -> "image/tiff"
        _ -> "application/octet-stream"
      end

    conn
    |> put_resp_content_type(content_type)
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> send_file(200, path)
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> text("Contact sheet image not found")
  end
end
