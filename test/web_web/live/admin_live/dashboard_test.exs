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
end
