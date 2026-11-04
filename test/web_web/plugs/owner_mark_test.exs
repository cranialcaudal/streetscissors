defmodule WebWeb.Plugs.OwnerMarkTest do
  use WebWeb.ConnCase, async: false

  alias Web.Analytics.Hit
  alias Web.Repo

  # The salt is repeated here on purpose: changing it invalidates every mark
  # already in a browser, which is a decision and not a refactor, and this
  # test is where that shows up.
  @salt "owner marker v1"
  @cookie "_ss_mine"

  # A loopback visitor is excluded whatever else is true, so every request
  # here arrives the way a real one does: through the proxy, from outside.
  defp from_outside(conn, ip \\ "203.0.113.77") do
    put_req_header(conn, "x-forwarded-for", ip)
  end

  defp hits, do: Repo.aggregate(Hit, :count, :id)

  describe "the mark" do
    test "an admin session marks the browser", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{"admin_user" => true})
        |> from_outside()
        |> get("/")

      assert %{value: token} = conn.resp_cookies[@cookie]
      assert {:ok, %{at: _}} = Phoenix.Token.verify(WebWeb.Endpoint, @salt, token, max_age: 60)
    end

    test "a browser with no mark and no session is not marked", %{conn: conn} do
      conn = conn |> from_outside() |> get("/")

      refute Map.has_key?(conn.resp_cookies, @cookie)
      assert conn.assigns.mine? == false
    end

    test "the mark is slid forward on a later visit, because browsers cap its life",
         %{conn: conn} do
      token = mark_a_browser(conn)

      later =
        build_conn()
        |> put_req_cookie(@cookie, token)
        |> from_outside()
        |> get("/")

      assert %{value: fresh} = later.resp_cookies[@cookie]
      assert {:ok, _} = Phoenix.Token.verify(WebWeb.Endpoint, @salt, fresh, max_age: 60)
    end
  end

  describe "what is counted" do
    test "a marked browser is not counted, logged out, with no session at all", %{conn: conn} do
      token = mark_a_browser(conn)
      before = hits()

      build_conn()
      |> put_req_cookie(@cookie, token)
      |> from_outside()
      |> get("/")

      assert hits() == before
    end

    test "the same request without the mark is counted", %{conn: conn} do
      before = hits()

      conn |> from_outside() |> get("/")

      assert hits() == before + 1
    end

    test "a forged or stale mark is ignored", %{conn: conn} do
      before = hits()

      conn
      |> put_req_cookie(@cookie, "not-a-token")
      |> from_outside()
      |> get("/")

      assert hits() == before + 1
    end

    test "a mark older than the window it is believed for is ignored" do
      eleven_years_ago = System.os_time(:second) - 11 * 365 * 24 * 60 * 60

      stale =
        Phoenix.Token.sign(WebWeb.Endpoint, @salt, %{at: eleven_years_ago},
          signed_at: eleven_years_ago
        )

      before = hits()

      build_conn()
      |> put_req_cookie(@cookie, stale)
      |> from_outside()
      |> get("/")

      assert hits() == before + 1
    end

    # init_test_session/2 stores the string "true", while the plug used to
    # compare == true. So the suite counted the author where the site did not,
    # and any test asserting "the author is not counted" passed for the wrong
    # reason — or failed for one.
    test "an admin session suppresses the count whether the flag is true or \"true\"",
         %{conn: conn} do
      before = hits()

      conn |> init_test_session(%{"admin_user" => true}) |> from_outside() |> get("/")
      build_conn() |> init_test_session(%{"admin_user" => "true"}) |> from_outside() |> get("/")

      assert hits() == before
    end
  end

  describe "OwnerMark.mine?/1 for a LiveView's session" do
    test "reads the mirror the plug leaves in the session" do
      assert WebWeb.OwnerMark.mine?(%{"owner" => true})
      assert WebWeb.OwnerMark.mine?(%{"admin_user" => "true"})
      refute WebWeb.OwnerMark.mine?(%{})
      refute WebWeb.OwnerMark.mine?(%{"owner" => false})
    end
  end

  defp mark_a_browser(conn) do
    conn
    |> init_test_session(%{"admin_user" => true})
    |> from_outside()
    |> get("/")
    |> then(& &1.resp_cookies[@cookie].value)
  end
end
