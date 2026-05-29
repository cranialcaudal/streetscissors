defmodule WebWeb.Plugs.MediaServe do
  @moduledoc """
  A plug to serve media files from the uploads directory with proper headers
  for streaming, seeking, and mobile compatibility.

  Supports HTTP Range requests for accurate scrubbing/seeking.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["uploads" | rest]} = conn, _opts) do
    # Build the file path
    filename = Path.join(rest)
    file_path = Path.join(["priv", "static", "uploads", filename])

    if File.exists?(file_path) do
      serve_file(conn, file_path, filename)
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp serve_file(conn, file_path, filename) do
    %{size: file_size} = File.stat!(file_path)
    content_type = mime_type(filename)

    # Check for Range header
    case get_req_header(conn, "range") do
      ["bytes=" <> range_spec] ->
        serve_partial(conn, file_path, file_size, content_type, range_spec)

      _ ->
        serve_full(conn, file_path, file_size, content_type)
    end
  end

  defp serve_full(conn, file_path, file_size, content_type) do
    conn
    |> put_resp_header("content-type", content_type)
    |> put_resp_header("content-length", to_string(file_size))
    |> put_resp_header("accept-ranges", "bytes")
    |> put_resp_header("cache-control", "public, max-age=31536000")
    |> send_file(200, file_path)
    |> halt()
  end

  defp serve_partial(conn, file_path, file_size, content_type, range_spec) do
    # Parse range like "0-" or "0-1024" or "1024-"
    {start_byte, end_byte} = parse_range(range_spec, file_size)

    # Validate range
    if start_byte >= file_size or start_byte < 0 or end_byte < start_byte do
      conn
      |> put_resp_header("content-range", "bytes */#{file_size}")
      |> send_resp(416, "Range Not Satisfiable")
      |> halt()
    else
      length = end_byte - start_byte + 1

      conn
      |> put_resp_header("content-type", content_type)
      |> put_resp_header("content-length", to_string(length))
      |> put_resp_header("content-range", "bytes #{start_byte}-#{end_byte}/#{file_size}")
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_header("cache-control", "public, max-age=31536000")
      |> send_file(206, file_path, start_byte, length)
      |> halt()
    end
  end

  defp parse_range(range_spec, file_size) do
    case String.split(range_spec, "-", parts: 2) do
      [start_str, ""] ->
        start = String.to_integer(start_str)
        {start, file_size - 1}

      ["", end_str] ->
        # Last N bytes
        suffix_length = String.to_integer(end_str)
        {file_size - suffix_length, file_size - 1}

      [start_str, end_str] ->
        {String.to_integer(start_str), min(String.to_integer(end_str), file_size - 1)}
    end
  rescue
    _ -> {0, file_size - 1}
  end

  defp mime_type(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".webm" -> "audio/webm"
      ".mp3" -> "audio/mpeg"
      ".wav" -> "audio/wav"
      ".ogg" -> "audio/ogg"
      ".m4a" -> "audio/mp4"
      ".aac" -> "audio/aac"
      ".mp4" -> "video/mp4"
      _ -> "application/octet-stream"
    end
  end
end
