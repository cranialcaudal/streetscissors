defmodule WebWeb.HealthControllerTest do
  use WebWeb.ConnCase

  test "GET /health says ok, and says nothing else", %{conn: conn} do
    conn = get(conn, "/health")

    assert json_response(conn, 200) == %{"status" => "ok"}
    assert get_resp_header(conn, "cache-control") == ["no-store"]
  end

  # It is asked every few minutes by a machine. It must not set a session
  # cookie or count as a visit.
  test "leaves no trace: no cookie, no analytics hit", %{conn: conn} do
    before = Web.Repo.aggregate(Web.Analytics.Hit, :count)

    conn = get(conn, "/health")

    assert get_resp_header(conn, "set-cookie") == []
    assert Web.Repo.aggregate(Web.Analytics.Hit, :count) == before
  end
end
