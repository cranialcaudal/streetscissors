defmodule WebWeb.AdminLive.RidesManagerTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  import Web.RidesFixtures

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/rides")
  end

  test "admin sees the sync control and every synced ride", %{conn: conn} do
    ride_fixture(%{name: "Home loop", visibility: "private"})

    {:ok, _view, html} = live(admin_conn(conn), "/admin/rides")
    assert html =~ "Sync now"
    assert html =~ "Home loop"
    assert html =~ "rides-admin-private"
  end
end
