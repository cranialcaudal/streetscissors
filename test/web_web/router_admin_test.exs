defmodule WebWeb.RouterAdminTest do
  @moduledoc """
  Every admin address is guarded by the router, and by nothing an action has to remember.

  An admin page is a `live` route in `live_session :admin`, whose `on_mount`
  hook (`WebWeb.AdminAuth`) sends anyone else home. An admin controller route
  is piped through `:admin_only` (`WebWeb.Plugs.RequireAdmin`), which answers
  the site's 404. This walks the router the way `Web.SearchTest` does and
  fails for an admin address that is neither, so a new one is closed from the
  day it is added.

  The `/dev` scope is piped through `:admin_only` too, but it is compiled only
  where `dev_routes` is on, which is not here.
  """
  use WebWeb.ConnCase

  # Under /admin and open on purpose, each with the reason.
  @open %{
    "/admin/login" => "the door: its form, and where the form posts",
    "/admin/logout" => "ends a session, and there is nothing behind it to guard",
    "/admin/content" => "an old address, moved to /admin/blog, which is guarded"
  }

  # Admin only, and not under /admin.
  @elsewhere ["/food", "/fitness/export/csv"]

  test "every admin address is a page in live_session :admin or a route behind :admin_only" do
    paths = Enum.map(admin_routes(), & &1.path)

    # The walk sees a page, a download and an address outside /admin.
    assert "/admin/dashboard" in paths
    assert "/admin/subscribers/export" in paths
    assert "/food" in paths

    open = for route <- admin_routes(), not guarded?(info(route)), do: label(route)

    assert open == [], """
    these admin addresses are open to anyone: #{Enum.join(open, ", ")}

    In lib/web_web/router.ex an admin page (`live`) goes inside
    `live_session :admin`, and an admin controller route goes in the scope
    piped through `:admin_only`.
    """

    # Nothing stays on the open list after its route has gone.
    every_path = Enum.map(WebWeb.Router.__routes__(), & &1.path)
    assert Enum.reject(Map.keys(@open), &(&1 in every_path)) == []
  end

  test "without the admin's session a page sends the visitor home and a route answers the site's 404" do
    for route <- admin_routes() do
      expected = if page?(info(route)), do: {:sent_to, "/"}, else: :not_found_page
      answer = anonymous(route)

      assert answer == expected,
             "#{label(route)} answered a visitor with #{inspect(answer)}, not #{inspect(expected)}"
    end
  end

  # With the route guarded, a check in the action is a second place to get it
  # wrong: three spellings of this one were in use, and they did not agree.
  test "no controller asks the session for the admin flag itself" do
    asking =
      for file <- Path.wildcard("lib/web_web/controllers/**/*.ex"),
          Path.basename(file) != "admin_session_controller.ex",
          File.read!(file) =~ "admin_user",
          do: file

    assert asking == [], """
    these controllers read "admin_user" from the session: #{Enum.join(asking, ", ")}

    An admin-only route goes in the router's `:admin_only` scope. An action
    anyone may reach that shows the admin more reads `conn.assigns.admin_mode`
    (`WebWeb.Plugs.SetCurrentUser`).
    """
  end

  defp admin_routes do
    for route <- WebWeb.Router.__routes__(),
        admin_address?(route.path),
        not is_map_key(@open, route.path),
        do: route
  end

  defp admin_address?(path) do
    path in @elsewhere or match?(["", "admin" | _], String.split(path, "/"))
  end

  # What the router does with a request for this route. The address asked for
  # is the route's own with a stand-in for each parameter, and the answer has
  # to be about this route: were an earlier one to match the address first,
  # its pipelines would be read here in this one's place.
  defp info(route) do
    path = route.path
    info = Phoenix.Router.route_info(WebWeb.Router, method(route), sample(path), "localhost")

    assert %{route: ^path} = info,
           "#{label(route)} is not the route that answers #{sample(path)}: #{inspect(info)}"

    info
  end

  # A page is guarded by its live_session and by that alone: going from one
  # page to the next over the socket passes through no plug.
  defp guarded?(%{phoenix_live_view: {_view, _action, _opts, live_session}}),
    do: live_session.name == :admin

  defp guarded?(%{pipe_through: pipes}), do: :admin_only in pipes

  defp page?(info), do: is_map_key(info, :phoenix_live_view)

  # What someone with no session is given: where they are sent, the site's own
  # 404 page, or whatever else came back.
  defp anonymous(route) do
    conn = dispatch(build_conn(), @endpoint, method(route), sample(route.path))

    cond do
      conn.status == 302 -> {:sent_to, redirected_to(conn)}
      conn.status == 404 and conn.resp_body =~ "Lost in the cut." -> :not_found_page
      true -> {:status, conn.status}
    end
  end

  defp sample(path), do: String.replace(path, ~r/[:*]\w+/, "x")

  # A `forward` answers every method.
  defp method(%{verb: :*}), do: "GET"
  defp method(%{verb: verb}), do: verb |> Atom.to_string() |> String.upcase()

  defp label(route), do: "#{method(route)} #{route.path}"
end
