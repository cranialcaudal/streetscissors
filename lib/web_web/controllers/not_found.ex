defmodule WebWeb.NotFound do
  @moduledoc """
  The one way a controller or a plug says "there is nothing here".

  `render/1` answers 404 with the page `WebWeb.ErrorHTML` draws for an address
  no route matches, and with the layouts off, because that page is a whole
  document. Going through here matters for two reasons. A post that is not
  there and a route that is not there now look the same to a visitor. And a
  route that exists but will not admit it — an admin page asked for without a
  session, a draft — is indistinguishable from one that does not, which is
  the point of answering 404 rather than 403.
  """

  import Plug.Conn
  import Phoenix.Controller

  @spec render(Plug.Conn.t()) :: Plug.Conn.t()
  def render(conn) do
    conn
    |> put_status(:not_found)
    |> put_root_layout(false)
    |> put_layout(false)
    |> put_view(WebWeb.ErrorHTML)
    |> render("404.html")
  end
end
