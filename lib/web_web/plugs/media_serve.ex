defmodule WebWeb.Plugs.MediaServe do
  @moduledoc """
  Serves uploaded media out of the uploads directory with the headers a
  player needs: Range for seeking, an ETag so a reload costs one 304, and the
  right content type for HLS.

  **In production this plug does not run.** Caddy answers `/uploads/*` off
  disk before the request ever reaches Phoenix, which keeps the BEAM out of
  the byte path entirely — a page of video segments is hundreds of requests,
  and none of them should occupy a scheduler. This is the dev-time equivalent,
  and the fallback if that Caddy block is ever removed.

  Everything under an entry directory is immutable: a re-transcode writes a
  new directory and swaps the pointer (see `Web.Uploads`), so nothing at a
  given path ever changes and the long cache lifetime is honest.
  """

  import Plug.Conn

  @cache_control "public, max-age=31536000, immutable"

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["uploads" | rest]} = conn, _opts) when rest != [] do
    # Path.safe_relative rejects any path that would traverse outside the
    # uploads directory (e.g. "../../etc/passwd"), guarding against
    # directory-traversal attacks via the URL.
    case Path.safe_relative(Path.join(rest)) do
      {:ok, filename} ->
        file_path = Path.join(Web.Uploads.root(), filename)

        case File.stat(file_path) do
          {:ok, %{type: :regular} = stat} -> serve_file(conn, file_path, filename, stat)
          _ -> conn
        end

      :error ->
        conn
    end
  end

  def call(conn, _opts), do: conn

  defp serve_file(conn, file_path, filename, %{size: file_size} = stat) do
    etag = etag(stat)

    conn =
      conn
      |> put_resp_header("content-type", mime_type(filename))
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_header("cache-control", @cache_control)
      |> put_resp_header("etag", etag)

    cond do
      # A reload of a page full of segments should cost one small response
      # each, not the segments over again.
      fresh?(conn, etag) ->
        conn |> send_resp(304, "") |> halt()

      conn.method == "HEAD" ->
        conn
        |> put_resp_header("content-length", to_string(file_size))
        |> send_resp(200, "")
        |> halt()

      true ->
        case get_req_header(conn, "range") do
          ["bytes=" <> range_spec] -> serve_partial(conn, file_path, file_size, range_spec)
          _ -> serve_full(conn, file_path, file_size)
        end
    end
  end

  # Size and mtime are enough: the contents at a path never change, so this
  # only has to distinguish one file from another.
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

  defp serve_full(conn, file_path, file_size) do
    conn
    |> put_resp_header("content-length", to_string(file_size))
    |> send_file(200, file_path)
    |> halt()
  end

  defp serve_partial(conn, file_path, file_size, range_spec) do
    {start_byte, end_byte} = parse_range(range_spec, file_size)

    if start_byte >= file_size or start_byte < 0 or end_byte < start_byte do
      conn
      |> put_resp_header("content-range", "bytes */#{file_size}")
      |> send_resp(416, "Range Not Satisfiable")
      |> halt()
    else
      length = end_byte - start_byte + 1

      conn
      |> put_resp_header("content-length", to_string(length))
      |> put_resp_header("content-range", "bytes #{start_byte}-#{end_byte}/#{file_size}")
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
        # Last N bytes, never reaching back past the start of the file.
        suffix_length = String.to_integer(end_str)
        {max(file_size - suffix_length, 0), file_size - 1}

      [start_str, end_str] ->
        {String.to_integer(start_str), min(String.to_integer(end_str), file_size - 1)}
    end
  rescue
    _ -> {0, file_size - 1}
  end

  defp mime_type(filename) do
    case Path.extname(filename) |> String.downcase() do
      # HLS. Neither of these is in Go's or Erlang's mime table, so both ends
      # — this plug and the Caddy block in production — have to say them
      # explicitly, or hls.js refuses the playlist.
      ".m3u8" -> "application/vnd.apple.mpegurl"
      ".m4s" -> "video/iso.segment"
      ".mp4" -> "video/mp4"
      ".webm" -> "video/webm"
      ".m4a" -> "audio/mp4"
      ".mp3" -> "audio/mpeg"
      ".wav" -> "audio/wav"
      ".ogg" -> "audio/ogg"
      ".aac" -> "audio/aac"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end
end
