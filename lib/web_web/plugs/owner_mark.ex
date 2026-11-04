defmodule WebWeb.Plugs.OwnerMark do
  @moduledoc """
  Keeps the author's browser marked, and tells the rest of the request.

  Runs before `WebWeb.Plugs.Analytics`, so the hit it decides not to record is
  decided on what this found. It sets the mark whenever the request already
  belongs to the author — by an admin session, by the session mirror, or by the
  cookie — which both marks a browser the first time the author logs in on it
  and slides the cookie forward on every read afterwards
  (`WebWeb.OwnerMark`: browsers cap a cookie's life at about thirteen months
  however long it asks for).

  `@mine?` is assigned either way, because a template may want to say so.
  """

  import Plug.Conn

  alias WebWeb.OwnerMark

  def init(opts), do: opts

  def call(conn, _opts) do
    if OwnerMark.mine?(conn) do
      conn |> OwnerMark.mark() |> assign(:mine?, true)
    else
      assign(conn, :mine?, false)
    end
  end
end
