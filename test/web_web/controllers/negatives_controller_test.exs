defmodule WebWeb.NegativesControllerTest do
  use WebWeb.ConnCase

  test "serve_image returns 200 for existing sheet or 404 for non-existent", %{conn: conn} do
    conn = get(conn, "/negatives/image/non_existent_file_123.png")
    assert response(conn, 404) =~ "not found"

    sheets = Web.Negatives.list_contact_sheets()

    case sheets do
      [first | _] ->
        conn2 = get(build_conn(), "/negatives/image/#{first.filename}")
        assert response(conn2, 200)
        assert get_resp_header(conn2, "content-type") |> hd() =~ "image/"

      [] ->
        :ok
    end
  end

  test "serve_preview returns a downscaled image or 404 for non-existent", %{conn: conn} do
    conn = get(conn, "/negatives/preview/non_existent_file_123.png")
    assert response(conn, 404) =~ "not found"

    sheets = Web.Negatives.list_contact_sheets()

    case sheets do
      [first | _] ->
        conn2 = get(build_conn(), "/negatives/preview/#{first.filename}")
        assert response(conn2, 200)
        assert get_resp_header(conn2, "content-type") |> hd() =~ "image/"

      [] ->
        :ok
    end
  end

  test "prevents directory traversal", %{conn: conn} do
    conn = get(conn, "/negatives/image/..%2F..%2F..%2Fetc%2Fpasswd")
    assert response(conn, 404)

    conn = get(build_conn(), "/negatives/preview/..%2F..%2F..%2Fetc%2Fpasswd")
    assert response(conn, 404)
  end

  test "serve_frame serves catalogued frames and 404s everything else", %{conn: conn} do
    conn = get(conn, "/negatives/frame/roll999/1")
    assert response(conn, 404)

    conn2 = get(build_conn(), "/negatives/frame/..%2F..%2Fetc/1")
    assert response(conn2, 404)

    conn3 = get(build_conn(), "/negatives/frame/roll001/..%2F..%2Fpasswd")
    assert response(conn3, 404)

    case Web.Negatives.frame_path("1", "1") do
      {:ok, _path} ->
        conn4 = get(build_conn(), "/negatives/frame/roll001/1")
        assert response(conn4, 200)
        assert get_resp_header(conn4, "content-type") |> hd() =~ "image/"

      :error ->
        :ok
    end
  end
end
