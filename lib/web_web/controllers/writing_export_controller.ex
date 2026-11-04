defmodule WebWeb.WritingExportController do
  @moduledoc """
  A paper or a post, as saved, through Pandoc (`Web.Writing.Export`) and downloaded: to the admin session alone.

  Anyone else, an unknown piece or format, gets the site's 404. When Pandoc
  fails the reply is its message as plain text, so the author can see which
  line it stopped at.
  """
  use WebWeb, :controller

  alias Web.Writing.{Export, Papers}

  def paper(conn, %{"slug" => slug, "format" => format}),
    do: export(conn, Papers, Papers.dir(), slug, format)

  def post(conn, %{"slug" => slug, "format" => format}),
    do: export(conn, Web.Blog, Web.Blog.base_path(), slug, format)

  defp export(conn, store, dir, slug, format) do
    with true <- get_session(conn, "admin_user") == true,
         {:ok, %{content: content}} <- store.read_source(slug) do
      case Export.export(content, slug, format, dir) do
        {:ok, binary, filename} ->
          conn
          |> put_resp_header("cache-control", "private, no-store")
          |> send_download({:binary, binary},
            filename: filename,
            content_type: Export.mime(format)
          )

        {:error, :unknown_format} ->
          WebWeb.NotFound.render(conn)

        {:error, :no_pandoc} ->
          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(503, "Pandoc is not installed on this machine.")

        {:error, {:pandoc, message}} ->
          conn
          |> put_resp_content_type("text/plain")
          |> send_resp(422, "Pandoc could not make the #{format}:\n\n" <> message)
      end
    else
      _ -> WebWeb.NotFound.render(conn)
    end
  end
end
