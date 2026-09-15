defmodule WebWeb.AdminLive.DashboardTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Web.Newsletter.Subscriber
  alias Web.Repo

  test "admin can remove a subscriber from the dashboard", %{conn: conn} do
    sub = Repo.insert!(%Subscriber{email: "gone@example.com", active: true})

    conn = init_test_session(conn, %{"admin_user" => "true"})
    {:ok, view, html} = live(conn, "/admin/dashboard")

    assert html =~ "gone@example.com"

    view
    |> element("button[phx-click='delete_subscriber'][phx-value-id='#{sub.id}']")
    |> render_click()

    refute render(view) =~ "gone@example.com"
    refute Repo.get(Subscriber, sub.id)
  end

  # The admin layout's flash group wore the same never-generated utility
  # classes as the public one.
  test "saving a setting is confirmed in a notice", %{conn: conn} do
    conn = init_test_session(conn, %{"admin_user" => "true"})
    {:ok, view, _html} = live(conn, "/admin/dashboard")

    view
    |> form("form[phx-submit=save_settings]", spotify_playlist_id: "abc123")
    |> render_submit()

    assert has_element?(
             view,
             ".admin-layout #flash-info.flash-notice",
             "Settings saved! Playlist ID: abc123"
           )
  end
end
