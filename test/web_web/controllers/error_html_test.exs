defmodule WebWeb.ErrorHTMLTest do
  use WebWeb.ConnCase

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    assert render_to_string(WebWeb.ErrorHTML, "404", "html", []) =~ "Lost in the cut."
  end

  test "renders 500.html" do
    assert render_to_string(WebWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end

  # The same page whoever is asking and however the miss came about. Before,
  # two of these three went out as a bare <div> with no stylesheet.
  describe "a 404 is one whole, styled document" do
    defp whole_document?(body) do
      assert body =~ "<!DOCTYPE html>"
      assert length(String.split(body, "<html")) == 2, "one document, not one inside another"
      assert body =~ ~r{<link rel="stylesheet" href="/assets/css/app[^"]*\.css"}
      assert body =~ "Lost in the cut."
      assert body =~ ~s(<meta name="robots" content="noindex")
      assert body =~ ~s(href="/blog")
      true
    end

    test "for an address no route matches", %{conn: conn} do
      body = conn |> get("/no/such/page") |> html_response(404)
      assert whole_document?(body)
      assert body =~ "<code>/no/such/page</code>"
    end

    test "for a page a controller looked for and did not find", %{conn: conn} do
      conn = get(conn, "/blog/no-such-post")
      assert whole_document?(html_response(conn, 404))
    end

    test "for a LiveView that raises on mount", %{conn: conn} do
      {404, _headers, body} = assert_error_sent 404, fn -> get(conn, "/logs/2030-01-01") end
      assert whole_document?(body)
    end

    # A route that exists but will not say so answers exactly as one that
    # does not exist.
    test "for an admin page asked for without a session", %{conn: conn} do
      body = conn |> get("/admin/fitness/calendar") |> html_response(404)
      assert whole_document?(body)
      refute body =~ "Calendar"
    end
  end

  describe "what it offers" do
    test "the nearest real pages, for a section it recognises", %{conn: conn} do
      body = conn |> get("/blog/keyworded-pots") |> html_response(404)

      assert body =~ "Closest to what you asked for"
      assert body =~ ~s(href="/blog/keyworded-post")
      assert body =~ "Fixture Post With Keywords"
      assert body =~ "Or start from"
    end

    test "only the ways in, for an address that is nothing of the site's", %{conn: conn} do
      body = conn |> get("/wp-login.php") |> html_response(404)

      refute body =~ "Closest to what you asked for"
      assert body =~ "Start from"
    end

    test "the address back, escaped and cut to a readable length", %{conn: conn} do
      probe = "/<script>alert(1)</script>/" <> String.duplicate("a", 400)
      body = conn |> get(probe) |> html_response(404)

      refute body =~ "<script>alert(1)</script>"
      assert body =~ "&lt;script&gt;"
      assert body =~ "…</code>"
    end
  end
end
