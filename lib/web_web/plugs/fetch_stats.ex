defmodule WebWeb.Plugs.FetchStats do
  @moduledoc """
  Puts today's visitor count on every page request, for the small figure in the
  site's header (`@header_daily_hits`). One of the four plugs every browser
  request passes through (see the `:browser` pipeline in `WebWeb.Router`).
  """

  import Plug.Conn
  alias Web.Analytics

  def init(opts), do: opts

  def call(conn, _opts) do
    # Only meaningful for GET requests to HTML pages
    if conn.method == "GET" and not (conn.request_path =~ ~r/^\/(api|live|phoenix)/) do
      hits = Analytics.count_unique_visitors_today()
      assign(conn, :header_daily_hits, hits)
    else
      assign(conn, :header_daily_hits, 0)
    end
  end
end
