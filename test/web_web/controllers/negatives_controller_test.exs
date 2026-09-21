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

  # The page shows a downscaled copy; the download button hands over the print
  # itself, which is the whole point of having scanned it at high resolution.
  describe "serve_frame_original" do
    test "hands over the print with a filename the browser can save", %{conn: conn} do
      case Web.Negatives.frame_path("1", "1") do
        {:ok, _path} ->
          conn = get(conn, "/negatives/frame/roll001/1/original")

          assert response(conn, 200)
          assert get_resp_header(conn, "content-type") |> hd() =~ "image/"

          assert get_resp_header(conn, "content-disposition") |> hd() ==
                   ~s(attachment; filename="roll001-frame-1.png")

        :error ->
          flunk("the committed fixture archive should have a print for roll 1, frame 1")
      end
    end

    test "404s an unknown frame, and refuses traversal", %{conn: conn} do
      assert response(get(conn, "/negatives/frame/roll999/1/original"), 404)
      assert response(get(build_conn(), "/negatives/frame/roll001/99/original"), 404)
      assert response(get(build_conn(), "/negatives/frame/..%2F..%2Fetc/1/original"), 404)

      assert response(
               get(build_conn(), "/negatives/frame/roll001/..%2F..%2Fpasswd/original"),
               404
             )
    end
  end

  # A host without ImageMagick should serve the original rather than 500 — the
  # preview is an optimisation, not a requirement. Runs against its own
  # throwaway archive, so a failed conversion cannot overwrite a committed one.
  test "a preview that cannot be generated falls back to the original" do
    root = Web.NegativesFixtures.archive!()
    Web.NegativesFixtures.put_sheet!(root, "roll044_2026-01-01_120_bw", 2400, 3000)

    previous = System.get_env("STUB_MAGICK_FAIL")
    System.put_env("STUB_MAGICK_FAIL", "1")

    on_exit(fn ->
      if previous,
        do: System.put_env("STUB_MAGICK_FAIL", previous),
        else: System.delete_env("STUB_MAGICK_FAIL")
    end)

    conn = get(build_conn(), "/negatives/preview/roll044_2026-01-01_120_bw.png")

    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") |> hd() =~ "image/"
  end
end
