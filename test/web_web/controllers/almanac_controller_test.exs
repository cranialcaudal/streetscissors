defmodule WebWeb.AlmanacControllerTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  import Web.AudioFixtures

  test "a day shows its work and steps to its neighbours", %{conn: conn} do
    html = conn |> get("/day/2026-07-10") |> html_response(200)

    assert html =~ "Fixture Post With A Block List"
    assert html =~ ~s(href="/day/2026-07-01")
    assert html =~ ~s(href="/day/2026-07-15")
    assert html =~ ~s(href="/daybook/2026")
    # And back to the week it is in.
    assert html =~ ~s(href="/daybook/2026/week/28")
  end

  test "an empty day, a bad date and an empty year are 404s", %{conn: conn} do
    assert conn |> get("/day/2026-07-02") |> html_response(404)
    assert conn |> get("/day/not-a-date") |> html_response(404)
    assert conn |> get("/daybook/1999") |> html_response(404)
  end

  test "the old /almanac addresses follow to the daybook", %{conn: conn} do
    for {old, new} <- [
          {"/almanac", "/daybook"},
          {"/almanac/2026", "/daybook/2026"},
          {"/almanac/2026/week/29", "/daybook/2026/week/29"}
        ] do
      assert redirected_to(get(conn, old), 301) == new
    end
  end

  describe "the week, as an engagement calendar opens to it" do
    test "/daybook is this week, whatever is in it", %{conn: conn} do
      today = Web.Clock.local_today()
      html = conn |> get("/daybook") |> html_response(200)

      assert html =~ "almanac-week"
      assert html =~ WebWeb.AlmanacHTML.week_span(Date.beginning_of_week(today))
      # Seven ruled days, today marked, and no "This week" link to itself.
      assert length(Regex.scan(~r/class="almanac-diary-day[ "]/, html)) == 7
      assert html =~ ~s(<span class="almanac-diary-today">Today</span>)
      refute html =~ "almanac-this-week"
      assert html =~ ~s(href="/daybook/#{today.year}")
    end

    test "a week shows each day's work on its day and steps to its neighbours", %{conn: conn} do
      # Monday 13 to Sunday 19 July 2026; a fixture post is dated the 15th.
      html = conn |> get("/daybook/2026/week/29") |> html_response(200)

      assert html =~ "13–19 July 2026"
      assert html =~ "Week 29"
      assert html =~ "Fixture Post With Keywords"
      assert html =~ ~s(href="/day/2026-07-15" class="almanac-diary-num")
      # The 16th has nothing: a number and its lines, not a link.
      refute html =~ ~s(href="/day/2026-07-16")
      # Neighbours are the nearest weeks with work, not the adjacent ones.
      assert html =~ ~s(href="/daybook/2026/week/28" rel="prev")
      refute html =~ ~s(href="/daybook/2026/week/30")
      assert html =~ ~s(class="almanac-this-week")
      # The Sunday is named as a printed calendar names it.
      assert html =~ "Sunday in Ordinary Time"
      # A week gone by carries no training: that is only pencilled in ahead.
      refute html =~ "almanac-diary-training"
    end

    test "an empty week and a week that does not exist are 404s", %{conn: conn} do
      assert conn |> get("/daybook/2026/week/20") |> html_response(404)
      assert conn |> get("/daybook/2026/week/54") |> html_response(404)
      assert conn |> get("/daybook/2026/week/0") |> html_response(404)
      assert conn |> get("/daybook/2026/week/x") |> html_response(404)
      # 2026 has 53 ISO weeks; 2027 does not.
      assert conn |> get("/daybook/2027/week/53") |> html_response(404)
    end
  end

  test "the year links every day with work and prints on request", %{conn: conn} do
    html = conn |> get("/daybook/2026") |> html_response(200)

    assert html =~ ~s(href="/day/2026-07-15")
    assert html =~ ~s(href="/day/2026-01-01")
    refute html =~ ~s(href="/day/2026-07-02")
    assert html =~ "data-print"
    assert html =~ ~s(<a href="/daybook" class="almanac-print">This week</a>)
  end

  test "a piece's date links to its day", %{conn: conn} do
    assert conn |> get("/blog/keyworded-post") |> html_response(200) =~ ~s(href="/day/2026-07-15")

    log = log_fixture(%{recorded_on: ~D[2026-07-20]})
    {:ok, _view, html} = live(conn, "/logs/#{log.slug}")
    assert html =~ ~s(href="/day/2026-07-20")
  end

  test "the sitemap lists years and days with work, and no empty ones", %{conn: conn} do
    xml = conn |> get("/sitemap.xml") |> response(200)

    assert xml =~ "/daybook/2026"
    assert xml =~ "/daybook/2026/week/29"
    refute xml =~ "/daybook/2026/week/20<"
    assert xml =~ "/day/2026-07-15"
    refute xml =~ "/day/2026-07-02"
  end
end
