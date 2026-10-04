defmodule WebWeb.WebmentionControllerTest do
  use WebWeb.ConnCase
  use Oban.Testing, repo: Web.Repo

  @target "http://localhost:4000/blog/keyworded-post"

  test "a valid mention is accepted with a 202 and queued for checking", %{conn: conn} do
    conn = post(conn, "/webmention", %{"source" => "https://example.org/a", "target" => @target})

    assert response(conn, 202) =~ "Accepted"
    assert_enqueued(worker: Web.Workers.WebmentionVerifier)
  end

  test "a mention of something that isn't ours is a 400", %{conn: conn} do
    conn =
      post(conn, "/webmention", %{
        "source" => "https://example.org/a",
        "target" => "https://elsewhere.test/"
      })

    assert response(conn, 400) =~ "not on this site"
  end

  test "it needs no session or CSRF token", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post(
        "/webmention",
        "source=https%3A%2F%2Fexample.org%2Fb&target=#{URI.encode_www_form(@target)}"
      )

    assert response(conn, 202)
  end

  test "every page says where to send one", %{conn: conn} do
    assert conn |> get("/blog/keyworded-post") |> html_response(200) =~
             ~s(<link rel="webmention" href="http://localhost:4000/webmention">)
  end
end
