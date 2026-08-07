defmodule WebWeb.PageControllerTest do
  use WebWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "streetscissors"
    assert html =~ "Contact Sheets/Photos"
    assert html =~ ~s(href="/blog")
    refute html =~ "Another Blog"
    refute html =~ "César&#39;s Machine"
    refute html =~ "All Manuscripts"
  end

  test "GET / degrades gracefully when the negatives directory is missing", %{conn: conn} do
    original = Application.get_env(:web, :negatives_path)
    Application.put_env(:web, :negatives_path, "/nonexistent-negatives-path")

    try do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ "Contact Sheets/Photos"
      refute html =~ "bento-hero-image"
    after
      if original,
        do: Application.put_env(:web, :negatives_path, original),
        else: Application.delete_env(:web, :negatives_path)
    end
  end
end
