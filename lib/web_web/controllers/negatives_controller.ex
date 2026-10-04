defmodule WebWeb.NegativesController do
  use WebWeb, :controller

  alias Web.Negatives

  def serve_image(conn, %{"filename" => filename}) do
    case Negatives.image_path(filename) do
      {:ok, path} -> send_image(conn, path)
      :error -> not_found(conn)
    end
  end

  def serve_preview(conn, %{"filename" => filename} = params) do
    case Negatives.preview_path(filename, width(params)) do
      {:ok, path} -> send_image(conn, path)
      :error -> not_found(conn)
    end
  end

  def serve_frame(conn, %{"roll" => roll, "frame" => frame} = params) do
    case Negatives.frame_preview_path(roll, frame, width(params)) do
      {:ok, path} -> send_image(conn, path)
      :error -> not_found(conn)
    end
  end

  # `?w=` asks for a narrower copy. Only the widths Negatives keeps are
  # honoured; anything else is the full preview, not a new file on disk.
  defp width(%{"w" => w}) do
    case Integer.parse(w) do
      {width, ""} -> if width in Negatives.widths(), do: width
      _ -> nil
    end
  end

  defp width(_params), do: nil

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

  # A sheet is a few hundred kilobytes and the archive is 31 of them. Without a
  # validator every visit after the cache expires refetches all of it in full,
  # so this mirrors WebWeb.Plugs.MediaServe: size and mtime are enough, because
  # the contents at a path only change when the file does.
  defp send_image(conn, path) do
    case File.stat(path) do
      {:ok, stat} -> send_validated(conn, path, etag(stat))
      _ -> send_body(conn, path)
    end
  end

  defp send_validated(conn, path, etag) do
    conn = put_resp_header(conn, "etag", etag)

    if fresh?(conn, etag) do
      send_resp(conn, 304, "")
    else
      send_body(conn, path)
    end
  end

  defp etag(%{size: size, mtime: mtime}) do
    hash = :erlang.phash2({size, mtime}, 4_294_967_296)
    ~s("#{Integer.to_string(hash, 16)}-#{Integer.to_string(size, 16)}")
  end

  defp fresh?(conn, etag) do
    case get_req_header(conn, "if-none-match") do
      [] -> false
      values -> Enum.any?(values, &(String.trim(&1) == etag or String.trim(&1) == "*"))
    end
  end

  defp send_body(conn, path) do
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
