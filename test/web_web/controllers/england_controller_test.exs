defmodule WebWeb.EnglandControllerTest do
  use WebWeb.ConnCase

  # The trip comes from test/support/fixtures/england (config/test.exs) — an
  # invented one, so nothing here describes a real trip.

  describe "GET /england2026" do
    test "builds the calendar, routes and call link from trip.json", %{conn: conn} do
      html = conn |> get(~p"/england2026") |> html_response(200)

      assert html =~ "Fixture Trip"
      assert html =~ "The Coast · 2–4 March 2030"
      assert html =~ "March 2030"
      assert Regex.scan(~r/class="cal-cell trip"/, html) |> length() == 3
      assert html =~ "Harbour Walk"
      assert html =~ "Coast Loop"
      assert html =~ ~s(href="/england2026/call")
      assert html =~ "Call times for home"
    end

    test "renders the itinerary, and the packing list as real checkboxes", %{conn: conn} do
      html = conn |> get(~p"/england2026") |> html_response(200)

      assert html =~ "Pack light and leave early."
      assert html =~ ~s(<input type="checkbox" checked>)
      refute html =~ "[x]"
    end

    test "still renders, empty, without a trip directory", %{conn: conn} do
      with_england_path(Path.join(System.tmp_dir!(), "no-trip-here"), fn ->
        html = conn |> get(~p"/england2026") |> html_response(200)

        refute html =~ "Fixture Trip"
        refute html =~ ~s(class="cal-cell trip")
        refute html =~ ~s(href="/england2026/call")
      end)
    end
  end

  describe "GET /england2026/call" do
    test "takes the window, time zones and wording from trip.json and call.md", %{conn: conn} do
      html = conn |> get(~p"/england2026/call") |> html_response(200)

      assert html =~ "When to Call the Traveller"
      assert html =~ "Your time (Home)"
      assert html =~ "Traveller&#39;s time (Away)"
      assert html =~ ~s(data-home-tz="America/New_York")
      assert html =~ ~s(data-away-tz="Asia/Tokyo")
      assert html =~ ~s(data-window-start="7")
      assert html =~ ~s(data-window-end="10")
      assert html =~ "Mornings only."
    end
  end

  defp with_england_path(path, fun) do
    prev = Application.get_env(:web, :england_path)
    Application.put_env(:web, :england_path, path)

    try do
      fun.()
    after
      Application.put_env(:web, :england_path, prev)
    end
  end
end
