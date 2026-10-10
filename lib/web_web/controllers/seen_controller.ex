defmodule WebWeb.SeenController do
  @moduledoc """
  `POST /seen?p=/blog/a-post`: a page that was fetched ahead of time saying
  it has now actually been shown.

  The speculation rules in the root layout prefetch a page when its link is
  hovered. `WebWeb.Plugs.Analytics` does not count a prefetch, and the browser
  makes no second request when the link is followed, so app.js sends this
  beacon from the page itself, once, when it was delivered from a prefetch.

  A beacon carries no CSRF token, so this sits outside `:browser`. What keeps
  it honest: it must come from this site (`Origin`), it can only name a page
  the router knows, and it is counted by exactly the rules a normal request
  is (`Analytics.record/2`), which means once per address per page for the
  figures anyone sees. The worst a forged one can do is what loading the page
  would have done.
  """

  use WebWeb, :controller

  alias WebWeb.Plugs.Analytics

  def create(conn, params) do
    with path when is_binary(path) <- params["p"],
         true <- same_origin?(conn),
         true <- page?(path) do
      Analytics.record(conn, path)
    end

    send_resp(conn, 204, "")
  end

  defp same_origin?(conn) do
    case get_req_header(conn, "origin") do
      [origin] -> URI.parse(origin).host == conn.host
      _ -> false
    end
  end

  defp page?("/" <> _ = path) do
    String.length(path) <= 300 and not String.contains?(path, ["?", "#", ".."]) and
      match?(%{}, Phoenix.Router.route_info(WebWeb.Router, "GET", path, "localhost"))
  end

  defp page?(_path), do: false
end
