defmodule WebWeb.NewsletterControllerTest do
  use WebWeb.ConnCase

  alias Web.Newsletter.Subscriber
  alias Web.Repo

  test "admin can export subscribers as CSV", %{conn: conn} do
    Repo.insert!(%Subscriber{email: "export@example.com", active: true})

    conn = log_in_admin(conn)
    conn = get(conn, "/admin/subscribers/export")

    assert response_content_type(conn, :csv)
    assert conn.resp_body =~ "email,status,joined"
    assert conn.resp_body =~ "export@example.com,active"
  end

  test "anyone else gets the site's 404 and not one address", %{conn: conn} do
    Repo.insert!(%Subscriber{email: "export@example.com", active: true})

    body = conn |> get("/admin/subscribers/export") |> html_response(404)

    assert body =~ "Lost in the cut."
    refute body =~ "export@example.com"
  end
end
