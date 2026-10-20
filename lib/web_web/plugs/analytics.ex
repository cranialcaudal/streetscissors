defmodule WebWeb.Plugs.Analytics do
  @moduledoc """
  Records one hit per page view.

  **A prefetch is not a view.** The root layout's speculation rules have the
  browser fetch a page when a link is hovered, marked `Sec-Purpose: prefetch`,
  and it does not ask again when the link is followed. So a prefetch is not
  counted here; the page says so itself when it is actually shown
  (`WebWeb.SeenController`, which calls `record/2` with the page's path).

  Who counts is `WebWeb.Visitor.counted?/3`, the same rule log views use;
  which paths are pages is `Web.Analytics.sub_resource_path?/1` plus the
  prefixes below, so the historical purge applies the rules this plug does.
  """

  import Plug.Conn

  alias Web.Analytics
  alias WebWeb.Visitor

  def init(opts), do: opts

  def call(conn, _opts) do
    unless prefetch?(conn), do: record(conn, conn.request_path)
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
  #
  # Whether it counts is decided here, in the request; only the insert is left
  # to a supervised task, given three strings rather than the whole conn, so a
  # page never waits on SQLite's one writer and nothing is started for
  # /admin or /assets.
  def record(conn, path) do
    if not filtered?(path) do
      ip = Visitor.ip(conn)
      ua = Visitor.user_agent(conn) || "unknown"

      if Visitor.counted?(ip, ua, get_session(conn, "admin_user") == true) do
        hash = Analytics.hash_ip(ip)

        Task.Supervisor.start_child(Web.TaskSupervisor, fn ->
          Analytics.record_hit(path, ua, hash)
        end)
      end
    end

    :ok
  end

  defp filtered?(path) do
    String.starts_with?(path, ["/admin", "/assets", "/favicon", "/phoenix", "/live", "/dev"]) or
      Analytics.sub_resource_path?(path)
  end
end
