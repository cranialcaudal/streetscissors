defmodule WebWeb.Plugs.Analytics do
  import Plug.Conn

  # We need a schema for AnalyticsHits to insert, or we can use raw SQL/generic insert if we want to be fast.
  # But we should probably have a schema or specific module function. 
  # Since we didn't define a context for it yet, let's just do a quick schema-less insert or define a schema inline/elsewhere.
  # Actually, let's create a Web.Analytics context properly.

  def init(opts), do: opts

  def call(conn, _opts) do
    # Run asynchronously to not block request
    Task.start(fn ->
      record_hit(conn)
    end)

    conn
  end

  defp record_hit(conn) do
    # Simple privacy-friendly recording
    # We only care about path and generic UA
    path = conn.request_path

    real_ip = get_client_ip(conn)

    # Ignore admin/assets/favicon and skip if admin is logged in
    # Also ignore localhost to prevent dev noise, but valid if testing Caddy locally
    if !filtered?(path) and !admin_logged_in?(conn) and !ip_excluded?(real_ip) do
      ua = get_req_header(conn, "user-agent") |> List.first() || "unknown"

      # We Hash IP for basic unique visitor counting without storing PII
      ip_hash = :crypto.hash(:sha256, real_ip) |> Base.encode16()

      Web.Analytics.record_hit(path, ua, ip_hash)
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
    String.starts_with?(path, ["/admin", "/assets", "/favicon", "/phoenix", "/live", "/dev"])
  end
end
