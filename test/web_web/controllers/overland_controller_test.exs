defmodule WebWeb.OverlandControllerTest do
  use WebWeb.ConnCase

  import Web.RidesFixtures

  alias Web.Rides

  @token "test-overland-token"

  defp post_batch(conn, locations, token \\ @token) do
    post(conn, ~p"/api/overland?token=#{token}", %{"locations" => locations})
  end

  test "rejects a missing or wrong token", %{conn: conn} do
    conn = post(conn, ~p"/api/overland", %{"locations" => []})
    assert json_response(conn, 401) == %{"result" => "error"}

    conn = post_batch(build_conn(), [], "wrong-token")
    assert json_response(conn, 401) == %{"result" => "error"}
  end

  test "accepts a bearer token", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer #{@token}")
      |> post(~p"/api/overland", %{"locations" => []})

    assert json_response(conn, 200) == %{"result" => "ok"}
  end

  test "acknowledges batches even with no active ride", %{conn: conn} do
    conn = post_batch(conn, [overland_feature()])
    assert json_response(conn, 200) == %{"result" => "ok"}
    assert Rides.get_active_ride() == nil
  end

  test "ingests points into the active ride and dedupes retries", %{conn: conn} do
    {:ok, _ride} = Rides.start_ride(%{"name" => "Test"})
    batch = [overland_feature()]

    assert json_response(post_batch(conn, batch), 200) == %{"result" => "ok"}
    assert json_response(post_batch(build_conn(), batch), 200) == %{"result" => "ok"}

    assert Rides.get_active_ride().point_count == 1
  end
end
