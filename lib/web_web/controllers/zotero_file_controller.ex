defmodule WebWeb.ZoteroFileController do
  @moduledoc """
  A Zotero attachment's file (`Web.Writing.Zotero.Reader`), to the admin session alone, with byte ranges for the reader.

  `/admin/zotero/file/:key/:md5` serves the cached copy for that MD5, fetching
  it from Zotero's storage the first time. PDF.js asks for byte ranges of a
  long file rather than the whole of it, so a single `Range: bytes=a-b` is
  answered with 206. Anyone else, an unknown key, or an attachment with no
  file in Zotero gets the site's 404. Never cached by the browser or a proxy.
  """
  use WebWeb, :controller

  alias Web.Writing.Zotero.Reader

  @types %{pdf: "application/pdf", epub: "application/epub+zip"}

  def show(conn, %{"key" => key, "md5" => md5}) do
    with true <- get_session(conn, "admin_user") == true,
         true <- Reader.key?(key) and (Reader.md5?(md5) or md5 == "none"),
         {:ok, path, kind} <- locate(key, md5) do
      serve(conn, path, kind)
    else
      _ -> WebWeb.NotFound.render(conn)
    end
  end

  defp locate(key, md5) do
    case Reader.cached_file(key, md5) do
      {path, kind} ->
        {:ok, path, kind}

      nil ->
        with {:ok, attachment} <- Reader.attachment(key),
             {:ok, path} <- Reader.file(attachment) do
          {:ok, path, attachment.kind}
        end
    end
  end

  defp serve(conn, path, kind) do
    size = File.stat!(path).size

    conn =
      conn
      |> put_resp_content_type(Map.fetch!(@types, kind), nil)
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-robots-tag", "noindex, nofollow")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-disposition", "inline")

    case range(get_req_header(conn, "range"), size) do
      :all ->
        send_file(conn, 200, path)

      {:ok, first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)

      :unsatisfiable ->
        conn
        |> put_resp_header("content-range", "bytes */#{size}")
        |> send_resp(416, "")
    end
  end

  # One range, `bytes=a-b`, `bytes=a-` or `bytes=-n`; anything else is the whole file.
  defp range(["bytes=" <> spec], size) do
    case Regex.run(~r/^(\d*)-(\d*)$/, String.trim(spec)) do
      [_, "", ""] -> :all
      [_, "", n] -> clamp(size - String.to_integer(n), size - 1, size)
      [_, a, ""] -> clamp(String.to_integer(a), size - 1, size)
      [_, a, b] -> clamp(String.to_integer(a), String.to_integer(b), size)
      nil -> :all
    end
  end

  defp range(_, _size), do: :all

  defp clamp(first, last, size) do
    first = max(first, 0)
    last = min(last, size - 1)
    if size > 0 and first <= last, do: {:ok, first, last}, else: :unsatisfiable
  end
end
