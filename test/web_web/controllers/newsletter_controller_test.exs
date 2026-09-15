defmodule WebWeb.NewsletterControllerTest do
  use WebWeb.ConnCase

  alias Web.Newsletter.Subscriber
  alias Web.Repo

  test "admin can export subscribers as CSV", %{conn: conn} do
    Repo.insert!(%Subscriber{email: "export@example.com", active: true})

    conn = init_test_session(conn, %{"admin_user" => "true"})
    conn = get(conn, "/admin/subscribers/export")

    assert response_content_type(conn, :csv)
    assert conn.resp_body =~ "email,status,joined"
    assert conn.resp_body =~ "export@example.com,active"
  end

  test "a non-admin is redirected instead of getting the export", %{conn: conn} do
    conn = get(conn, "/admin/subscribers/export")
    assert redirected_to(conn) == "/"
  end
end
