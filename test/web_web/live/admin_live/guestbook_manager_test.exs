defmodule WebWeb.AdminLive.GuestbookManagerTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  import Web.GeneralFixtures

  alias Web.General

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/guestbook")
  end

  test "opens on the signatures waiting for approval", %{conn: conn} do
    guestbook_entry_fixture(%{name: "Waiting Walt", approved: false})
    guestbook_entry_fixture(%{name: "Live Lou", approved: true})

    {:ok, view, html} = live(admin_conn(conn), "/admin/guestbook")
    assert html =~ "Waiting Walt"
    refute html =~ "Live Lou"

    html = view |> element(~s(.adm-tabs a[href="/admin/guestbook?show=live"])) |> render_click()
    assert html =~ "Live Lou"
    refute html =~ "Waiting Walt"
  end

  test "approving publishes the signature once and clears the badge", %{conn: conn} do
    entry = guestbook_entry_fixture(%{name: "Waiting Walt", approved: false})

    {:ok, view, _html} = live(admin_conn(conn), "/admin/guestbook?show=all")
    assert has_element?(view, ~s(#adm-rail a[href="/admin/guestbook"] .adm-badge), "1")

    view |> element("#signature-#{entry.id} button[phx-click=toggle_approved]") |> render_click()

    assert General.get_guestbook_entry!(entry.id).approved
    refute has_element?(view, ~s(#adm-rail a[href="/admin/guestbook"] .adm-badge))
    # The approval broadcast used to prepend a second copy of the entry.
    assert view |> render() |> String.split("Waiting Walt") |> length() == 2
  end

  test "a signature arriving while the page is open joins the queue", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/guestbook")
    refute render(view) =~ "Late Arrival"

    guestbook_entry_fixture(%{name: "Late Arrival", approved: false})
    assert render(view) =~ "Late Arrival"
  end

  test "a signature can be deleted", %{conn: conn} do
    entry = guestbook_entry_fixture(%{approved: false})

    {:ok, view, _html} = live(admin_conn(conn), "/admin/guestbook")
    view |> element("#signature-#{entry.id} button[phx-click=delete]") |> render_click()

    assert General.list_all_guestbook_entries() == []
  end
end
