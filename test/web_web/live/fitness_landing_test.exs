defmodule WebWeb.FitnessLandingTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Web.Rides

  defp ride_points(start) do
    Enum.map(0..2, fn i ->
      %{
        lat: 54.54 + i / 100,
        lon: -3.15,
        altitude_m: 100.0,
        recorded_at: DateTime.add(start, i * 60, :second)
      }
    end)
  end

  test "landing renders the regimen accordion with today expanded", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/fitness")
    assert html =~ "weekly-routine"
    assert html =~ "Weekly Regimen"
    assert html =~ "Additional Modules"
    assert html =~ ~s(data-day="#{Web.Clock.today_slug()}" open)
  end

  describe "rotating days" do
    test "Friday offers both options with exactly one open", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")

      # The fartlek used to exist only as prose, which checklist_only/1 strips —
      # so the page showed the swim and nothing else.
      assert html =~ "Office Swim"
      assert html =~ "Remote Fartlek Run"

      assert open_count(html, "friday") == 1
    end

    test "Saturday offers all four weeks with exactly one open", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")

      # Assert on the week prefixes rather than the full labels: the labels are
      # content and get reworded, and a test that pins their exact wording just
      # breaks every time the vault is edited.
      for week <- ["Week 1", "Week 2", "Week 3", "Week 4"] do
        assert html =~ week
      end

      assert option_count(html, "saturday") == 4
      assert open_count(html, "saturday") == 1
    end

    test "the option in rotation is the one the ISO week says", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")

      expected = Web.Fitness.Rotation.index(2, Web.Clock.local_today()) + 1
      assert html =~ ~s(data-option="friday_option_#{expected}" open)
    end

    test "a non-rotating day renders no option dropdowns", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")
      assert option_count(html, "tuesday") == 0
    end

    test "the active option is badged so it reads at a glance", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")
      assert html =~ "this week"
    end
  end

  # `data-option` is "<day>_option_<n>"; `open` follows it when that option is
  # the one in rotation.
  defp option_count(html, day) do
    Regex.scan(~r/data-option="#{day}_option_\d+"/, html) |> length()
  end

  defp open_count(html, day) do
    Regex.scan(~r/data-option="#{day}_option_\d+" open/, html) |> length()
  end

  # The landing used to sit the regimen beside a latest-ride card; it is now
  # regimen-only, and rides are reachable solely through the subnav tab.
  test "landing shows no ride card, only the GPX Action tab", %{conn: conn} do
    {:ok, ride} =
      Rides.create_imported_ride(ride_points(~U[2026-07-08 08:00:00Z]), %{
        "name" => "Morning spin"
      })

    {:ok, _view, html} = live(conn, ~p"/fitness")

    refute html =~ "Latest Ride"
    refute html =~ "Morning spin"
    refute html =~ "/fitness/rides/#{ride.id}"
    assert html =~ "GPX Action"
    assert html =~ ~s(href="/fitness/rides")
  end
end
