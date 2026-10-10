defmodule WebWeb.Plugs.Analytics do
  @moduledoc """
  Records one hit per page view.

  **A prefetch is not a view.** The root layout's speculation rules have the
  browser fetch a page when a link is hovered, marked `Sec-Purpose: prefetch`,
  and it does not ask again when the link is followed. So a prefetch is not
  counted here; the page says so itself when it is actually shown
  (`WebWeb.SeenController`, which calls `record/2` with the page's path).

  What counts as a hit lives in `Web.Analytics` (`bot_user_agent?/1`,
  `sub_resource_path?/1`, `hash_ip/1`) rather than here, so the historical
  purge applies exactly the same rules this plug does going forward.
  """

  import Plug.Conn

  alias Web.Analytics

  def init(opts), do: opts

  def call(conn, _opts) do
    unless prefetch?(conn) do
      # Run asynchronously to not block request
      Task.start(fn -> record(conn, conn.request_path) end)
    end

    conn
  end

  @doc "Whether the browser is fetching this ahead of anyone asking to see it."
  def prefetch?(conn) do
    Enum.any?(
      get_req_header(conn, "sec-purpose") ++ get_req_header(conn, "purpose"),
      &String.contains?(&1, "prefetch")
    )
  end

  @doc """
  Counts one view of `path` by whoever sent `conn`, under the same rules
  whichever way it is reported: no bots, no admin, no excluded address, no
  sub-resource.
  """
  def record(conn, path) do
    real_ip = get_client_ip(conn)
    ua = get_req_header(conn, "user-agent") |> List.first() || "unknown"

    if !filtered?(path) and !Analytics.bot_user_agent?(ua) and !admin_logged_in?(conn) and
         !ip_excluded?(real_ip) do
      Analytics.record_hit(path, ua, Analytics.hash_ip(real_ip))
    end
  end

  defp get_client_ip(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ips | _] ->
        # X-Forwarded-For can be "client, proxy1, proxy2"
        ips |> String.split(",") |> List.first() |> String.trim()

      _ ->
        conn.remote_ip |> :inet.ntoa() |> to_string()
    end
  end

  defp admin_logged_in?(conn) do
    get_session(conn, "admin_user") == true
  end

  defp ip_excluded?(ip) do
    excluded_env = System.get_env("EXCLUDED_IPS") || ""
    excluded_ips = excluded_env |> String.split(",") |> Enum.map(&String.trim/1)

    # Always exclude localhost for debugging
    # Note: If accessing via Caddy from same machine, XFF might be 127.0.0.1 or LAN IP.
    # We'll validly exclude loopback.
    ip in ["127.0.0.1", "::1"] or ip in excluded_ips
  end

  defp filtered?(path) do
    String.starts_with?(path, ["/admin", "/assets", "/favicon", "/phoenix", "/live", "/dev"]) or
      Analytics.sub_resource_path?(path)
  end
end
