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

  # The print as it was scanned and developed — tens of megabytes, often a
  # TIFF. Never what a page loads, always what a download link points at.
  def serve_frame_original(conn, %{"roll" => roll, "frame" => frame}) do
    case Negatives.frame_path(roll, frame) do
      {:ok, path} ->
        conn
        |> put_resp_header("content-disposition", disposition(roll, frame, path))
        |> send_image(path)

      :error ->
        not_found(conn)
    end
  end

  defp disposition(roll, frame, path) do
    name =
      "roll#{String.pad_leading(digits(roll), 3, "0")}-frame-#{digits(frame)}" <>
        Path.extname(path)

    ~s(attachment; filename="#{name}")
  end

  # The route already matched, so these are digit tokens; this only normalises
  # them for the filename the browser will save.
  defp digits(token) do
    case Regex.run(~r/(\d+)/, to_string(token)) do
      [_, found] -> String.trim_leading(found, "0")
      _ -> "0"
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
    # No charset: these are image bytes, and Plug appends one by default.
    |> put_resp_content_type(content_type, nil)
    |> put_resp_header("cache-control", "public, max-age=86400")
    |> send_file(200, path)
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> text("Contact sheet image not found")
  end
end
