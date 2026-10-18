defmodule WebWeb.CutMediaController do
  @moduledoc """
  The cutting room's proxies (`Web.Cuts`), to the admin session alone, with
  Range so the browser can seek in them. Only a proxy of a file in that
  cut's bin can be named: the originals stay on the server.
  """

  use WebWeb, :controller

  alias Web.Cuts
  alias WebWeb.Plugs.MediaServe

  def show(conn, %{"id" => id, "file" => file}) do
    with true <- !!get_session(conn, "admin_user"),
         {id, ""} <- Integer.parse(id),
         %{} = cut <- Cuts.get_cut(id),
         %{} = media <- Enum.find(cut.media, &(&1.proxy == file and &1.status == "ready")) do
      MediaServe.send_media(conn, Cuts.proxy_path(media), "private, max-age=3600")
    else
      _ -> WebWeb.NotFound.render(conn)
    end
  end
end
