defmodule WebWeb.FitnessLandingTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest
  import Web.RidesFixtures

  # Runs against the invented vault in test/support/fixtures/fitness (see
  # config/test.exs). Checks on the author's real regimen live in the
  # gitignored test/private/.

  test "landing renders the regimen accordion with today expanded", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/fitness")
    assert html =~ "weekly-routine"
    assert html =~ "Weekly Regimen"
    assert html =~ "Additional Modules"
    assert html =~ ~s(data-day="#{Web.Clock.today_slug()}" open)
  end

  describe "the week" do
    test "each day renders its checklist, modules included", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")

      assert html =~ "Sunday — Long Run"
      assert html =~ "Easy run"
      # Tuesday's exercises come from its `modules:` line, wiki links resolved.
      assert html =~ "Band rows"
      assert html =~ "/fitness/wiki/push-ups"
    end

    test "a rotating day renders each option as a dropdown, one marked this week",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")

      assert option_count(html, "friday") == 2
      assert option_count(html, "tuesday") == 0
      assert html =~ "Pool Swim"
      assert html =~ "Tempo Run"
      assert Regex.scan(~r/class="option-badge"/, html) |> length() == 1
    end
  end

  describe "fuelling" do
    test "the fuelling module renders its targets", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")

      assert html =~ ~s(data-day="nutrition-module")
      assert html =~ "Fuelling"
      assert html =~ "Daily Targets"
      assert html =~ "100 g protein"
    end

    # It is a daily reference, so it sits above the week and open — not
    # collapsed among the Additional Modules, where it went unnoticed.
    test "fuelling is pinned open above the weekly regimen", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")

      assert html =~ ~s(data-day="nutrition-module" open)

      {fuelling, _} = :binary.match(html, ~s(data-day="nutrition-module"))
      {weekly, _} = :binary.match(html, "Weekly Regimen")
      {additional, _} = :binary.match(html, "Additional Modules")

      assert fuelling < weekly
      assert fuelling < additional
    end

    # GymRoutine keys saved ticks on `vault_gym_<data-day>_<index>` scoped to
    # #weekly-routine. Pinning it outside that element would detach every one.
    test "fuelling stays inside the checkbox-persistence scope", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")

      {hook, _} = :binary.match(html, ~s(id="weekly-routine"))
      {fuelling, _} = :binary.match(html, ~s(data-day="nutrition-module"))

      assert hook < fuelling
      assert html =~ ~s(class="day-details" data-day="nutrition-module")
    end

    # The page is public and checklist_only/1 is the only thing keeping it that
    # way. The derivation in the day body must never reach the HTML.
    test "the fuelling derivation stays out of the public page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")

      refute html =~ "Maintenance estimate"
      refute html =~ "fixture bodyweight"
    end
  end

  # Logging is admin-only. Its notices were always in the HTML — bare text under
  # the whole page, dark on the steel ground — so these check for the styled
  # notice, not just the words.
  describe "logging an exercise, as the admin" do
    setup %{conn: conn} do
      {:ok, _} = Web.Fitness.create_exercise(%{name: "Push-ups", slug: "push-ups"})

      {:ok, view, _html} =
        conn |> init_test_session(%{"admin_user" => true}) |> live(~p"/fitness")

      view |> element("button.log-trigger[phx-value-slug='push-ups']") |> render_click()

      %{view: view}
    end

    test "a saved entry is confirmed in a notice", %{view: view} do
      view
      |> form("form[phx-submit=save_log]", log: %{result: "3 x 12"})
      |> render_submit()

      assert has_element?(view, "#flash-info.flash-notice[role=status]", "Logged Push-ups.")
      refute has_element?(view, "form[phx-submit=save_log]")
    end

    test "an empty entry is refused in an alert, with the form still open", %{view: view} do
      view |> form("form[phx-submit=save_log]") |> render_submit()

      assert has_element?(
               view,
               "#flash-error.flash-notice[role=alert]",
               "Enter at least one value to log."
             )

      assert has_element?(view, "form[phx-submit=save_log]")
    end
  end

  describe "The Week" do
    test "renders every day above the fuelling panel and the regimen", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")

      assert Regex.scan(~r/data-week-day="/, html) |> length() == 7

      {week, _} = :binary.match(html, ~s(id="the-week"))
      {fuelling, _} = :binary.match(html, ~s(data-day="nutrition-module"))
      {regimen, _} = :binary.match(html, "Weekly Regimen")

      assert week < fuelling
      assert week < regimen

      assert html =~ ~s(data-week-day="#{Web.Clock.today_slug()}" class="week-row is-today")
    end

    # /fitness is public: visitors get the shape of each day, never when.
    test "visitors see no clock times", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")
      section = week_section(html)

      assert section =~ "Morning Spin"
      refute section =~ ~r/\d{1,2}:\d{2}/
      refute section =~ "week-track"
      refute section =~ "week-axis"
    end

    test "the admin sees the timed view", %{conn: conn} do
      {:ok, _view, html} =
        conn |> init_test_session(%{"admin_user" => true}) |> live(~p"/fitness")

      section = week_section(html)

      assert section =~ "week-track"
      assert section =~ "week-axis"
      assert section =~ "6:45–7:30"
    end
  end

  defp week_section(html) do
    [section] = Regex.run(~r{<section id="the-week".*?</section>}s, html)
    section
  end

  # `data-option` is "<day>_option_<n>".
  defp option_count(html, day) do
    Regex.scan(~r/data-option="#{day}_option_\d+"/, html) |> length()
  end

  # The landing used to sit the regimen beside a latest-ride card; it is now
  # regimen-only, and rides are reachable solely through the subnav tab.
  test "landing shows no ride card, only the Activities tab", %{conn: conn} do
    ride = ride_fixture(%{name: "Morning spin"})

    {:ok, _view, html} = live(conn, ~p"/fitness")

    refute html =~ "Latest Ride"
    refute html =~ "Morning spin"
    refute html =~ "/fitness/rides/#{ride.id}"
    assert html =~ "Activities"
    assert html =~ ~s(href="/fitness/rides")
  end
end
