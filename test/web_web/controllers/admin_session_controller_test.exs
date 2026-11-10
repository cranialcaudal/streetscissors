defmodule WebWeb.AdminSessionControllerTest do
  @moduledoc """
  The admin's door: one password in, and out again in every tab of the browser that asked.
  """
  use WebWeb.ConnCase, async: false

  setup do
    Web.RateLimit.reset_all()
    on_exit(&Web.RateLimit.reset_all/0)
  end

  defp password, do: Application.fetch_env!(:web, :admin_password)

  # A login comes the way a real one does: through the proxy, from an address
  # of its own, which is what the attempts are counted against. The browser
  # brings the cookies it was last given.
  defp log_in(conn, password \\ password(), ip \\ "203.0.113.20") do
    conn
    |> recycle()
    |> put_req_header("x-forwarded-for", ip)
    |> post(~p"/admin/login", %{"password" => password})
  end

  # The name LiveView gives every socket opened with this session's cookie,
  # asked of LiveView itself so the key cannot be misspelled here and there.
  defp socket_name(conn) do
    Phoenix.LiveView.Socket.id(%Phoenix.Socket{
      private: %{connect_info: %{session: get_session(conn)}}
    })
  end

  defp flash(conn, kind), do: Phoenix.Flash.get(conn.assigns.flash, kind)

  describe "logging in" do
    test "the password opens the admin's pages and its downloads", %{conn: conn} do
      conn = log_in(conn)

      assert redirected_to(conn) == "/admin/dashboard"
      assert get_session(conn, "admin_user") == true
      assert "admin_sessions:" <> _ = socket_name(conn)

      assert conn |> get(~p"/admin/dashboard") |> html_response(200)
      assert conn |> get(~p"/admin/subscribers/export") |> response(200) =~ "email,status,joined"
    end

    test "it marks the browser as the author's", %{conn: conn} do
      conn = log_in(conn)

      assert get_session(conn, "owner") == true
      assert get(conn, ~p"/").assigns.mine?
    end

    test "a wrong password opens nothing and says so", %{conn: conn} do
      conn = log_in(conn, "not-the-password")

      assert redirected_to(conn) == "/admin/login"
      assert flash(conn, :error) == "Wrong password"
      refute get_session(conn, "admin_user")
      refute socket_name(conn)

      assert conn |> get(~p"/admin/dashboard") |> redirected_to() == "/"
      assert conn |> get(~p"/admin/subscribers/export") |> html_response(404)
    end

    test "with no password configured, nothing opens it, an empty one least of all",
         %{conn: conn} do
      real = password()
      Application.put_env(:web, :admin_password, "")
      on_exit(fn -> Application.put_env(:web, :admin_password, real) end)

      for attempt <- ["", real] do
        conn = log_in(conn, attempt)

        assert redirected_to(conn) == "/admin/login"
        refute get_session(conn, "admin_user")
      end
    end

    test "the eleventh attempt from one address is refused, right password or not" do
      for _ <- 1..10 do
        assert build_conn() |> log_in("a-guess") |> flash(:error) == "Wrong password"
      end

      conn = log_in(build_conn())

      assert redirected_to(conn) == "/admin/login"
      assert flash(conn, :error) =~ "Too many attempts"
      refute get_session(conn, "admin_user")

      # Another address has attempts of its own.
      assert build_conn() |> log_in(password(), "203.0.113.21") |> redirected_to() ==
               "/admin/dashboard"
    end

    test "a second login from the same browser keeps the name its tabs already have",
         %{conn: conn} do
      first = log_in(conn)
      second = log_in(first)

      assert get_session(second, "admin_user") == true
      assert socket_name(second) == socket_name(first)
    end
  end

  describe "logging out" do
    test "takes the admin out of the session and sends the browser home", %{conn: conn} do
      conn = conn |> log_in() |> delete(~p"/admin/logout")

      assert redirected_to(conn) == "/"
      assert flash(conn, :info) == "Logged out successfully."
      refute get_session(conn, "admin_user")
      refute socket_name(conn)

      assert conn |> get(~p"/admin/dashboard") |> redirected_to() == "/"
      assert conn |> get(~p"/admin/subscribers/export") |> html_response(404)
    end

    test "tells the pages open in the browser's other tabs to disconnect", %{conn: conn} do
      conn = log_in(conn)
      name = socket_name(conn)
      WebWeb.Endpoint.subscribe(name)

      delete(conn, ~p"/admin/logout")

      assert_received %Phoenix.Socket.Broadcast{topic: ^name, event: "disconnect"}
    end

    # The cookie is all there is: nothing on the server knows of the other
    # browser, so nothing here can end its session.
    test "is one browser's, and another that is logged in stays in", %{conn: conn} do
      here = log_in(conn)
      there = log_in(build_conn())

      assert socket_name(here) != socket_name(there)
      WebWeb.Endpoint.subscribe(socket_name(there))

      delete(here, ~p"/admin/logout")

      refute_received %Phoenix.Socket.Broadcast{event: "disconnect"}
      assert there |> get(~p"/admin/dashboard") |> html_response(200)
    end

    test "does not unmark the browser: its reading stays uncounted", %{conn: conn} do
      conn = conn |> log_in() |> delete(~p"/admin/logout")

      assert get(conn, ~p"/").assigns.mine?
    end

    test "works for a session from before logins carried a name", %{conn: conn} do
      conn = conn |> log_in_admin() |> delete(~p"/admin/logout")

      assert redirected_to(conn) == "/"
      refute get_session(conn, "admin_user")
    end

    # A GET would let any page log the admin out with a link or a picture.
    test "is a DELETE and nothing else", %{conn: conn} do
      conn = conn |> log_in() |> get("/admin/logout")

      assert html_response(conn, 404) =~ "Lost in the cut."
      assert conn |> get(~p"/admin/dashboard") |> html_response(200)
    end

    test "goes home, whatever address it is handed", %{conn: conn} do
      conn =
        conn
        |> log_in()
        |> delete("/admin/logout", %{"redirect_to" => "https://elsewhere.example/"})

      assert redirected_to(conn) == "/"
    end
  end
end
