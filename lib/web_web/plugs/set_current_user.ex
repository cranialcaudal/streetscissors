defmodule WebWeb.Plugs.SetCurrentUser do
  @moduledoc """
  Plug to set the current user/admin status in assigns for all requests.
  This makes admin status available in templates globally.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    admin_mode = get_session(conn, "admin_user") == true
    assign(conn, :admin_mode, admin_mode)
  end
end
