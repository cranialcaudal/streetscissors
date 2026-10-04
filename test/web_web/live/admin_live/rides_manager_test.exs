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
    assert html =~ ~s(class="adm-pill adm-pill--quiet ride-private")
    # Nothing to draw until the sync has read its track.
    assert html =~ "No track yet"
    # With no zone set, the page says routes go out whole.
    assert html =~ "routes are published whole"
  end

  test "the page says when the sync last ran", %{conn: conn} do
    Web.Rides.KomootSync.record_run({:error, :auth_failed})

    {:ok, _view, html} = live(admin_conn(conn), "/admin/rides")
    assert html =~ ":auth_failed"
  end
end
