defmodule WebWeb.Plugs.FetchStats do
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
