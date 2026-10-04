defmodule WebWeb.AlmanacControllerTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  import Web.AudioFixtures

  test "a day shows its work and steps to its neighbours", %{conn: conn} do
    html = conn |> get("/day/2026-07-10") |> html_response(200)

    assert html =~ "Fixture Post With A Block List"
    assert html =~ ~s(href="/day/2026-07-01")
    assert html =~ ~s(href="/day/2026-07-15")
    assert html =~ ~s(href="/almanac/2026")
  end

  test "an empty day, a bad date and an empty year are 404s", %{conn: conn} do
    assert conn |> get("/day/2026-07-02") |> html_response(404)
    assert conn |> get("/day/not-a-date") |> html_response(404)
    assert conn |> get("/almanac/1999") |> html_response(404)
  end

  test "/almanac goes to the newest year with work", %{conn: conn} do
    assert redirected_to(get(conn, "/almanac")) == "/almanac/2026"
  end

  test "the year links every day with work and prints on request", %{conn: conn} do
    html = conn |> get("/almanac/2026") |> html_response(200)

    assert html =~ ~s(href="/day/2026-07-15")
    assert html =~ ~s(href="/day/2026-01-01")
    refute html =~ ~s(href="/day/2026-07-02")
    assert html =~ "data-print"
  end

  test "a piece's date links to its day", %{conn: conn} do
    assert conn |> get("/blog/keyworded-post") |> html_response(200) =~ ~s(href="/day/2026-07-15")

    log = log_fixture(%{recorded_on: ~D[2026-07-20]})
    {:ok, _view, html} = live(conn, "/logs/#{log.slug}")
    assert html =~ ~s(href="/day/2026-07-20")
  end

  test "the sitemap lists years and days with work, and no empty ones", %{conn: conn} do
    xml = conn |> get("/sitemap.xml") |> response(200)

    assert xml =~ "/almanac/2026"
    assert xml =~ "/day/2026-07-15"
    refute xml =~ "/day/2026-07-02"
  end
end
