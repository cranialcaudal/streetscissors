defmodule WebWeb.FitnessLandingTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest
  import Web.RidesFixtures

  # Runs against the invented vault in test/support/fixtures/fitness (see
  # config/test.exs). Checks on the author's real regimen live in the
  # gitignored test/private/.

  @weekdays ~w[monday tuesday wednesday thursday friday saturday sunday]

  describe "a day to a page" do
    test "/fitness is today, and only today", %{conn: conn} do
      today = Web.Clock.today_slug()
      {:ok, _view, html} = live(conn, ~p"/fitness")

      assert html =~ "weekly-routine"
      assert html =~ ~s(class="day-details day-page" data-day="#{today}")
      assert html =~ "Additional Modules"

      for other <- @weekdays -- [today] do
        refute html =~ ~s(data-day="#{other}")
      end
    end

    # The day being looked at is in the address, so a reload keeps it.
    test "another day has its own address, and says it is not today", %{conn: conn} do
      other = hd(@weekdays -- [Web.Clock.today_slug()])
      {:ok, _view, html} = live(conn, ~p"/fitness/day/#{other}")

      assert html =~ ~s(class="day-details day-page" data-day="#{other}")
      assert html =~ "Not today"
      assert html =~ "Today is #{String.capitalize(Web.Clock.today_slug())}"
    end

    test "the days link to each other, today by the address that follows the clock",
         %{conn: conn} do
      today = Web.Clock.today_slug()
      {:ok, view, _html} = live(conn, ~p"/fitness")

      assert has_element?(
               view,
               ~s(nav.day-strip a.is-today[href="/fitness"][aria-current="page"])
             )

      for other <- @weekdays -- [today] do
        assert has_element?(view, ~s(nav.day-strip a[href="/fitness/day/#{other}"]))
      end
    end

    # `theme:` in a day's file is the one word under its name in the strip.
    test "each day in the strip carries its one-word theme", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/fitness/day/sunday")

      assert has_element?(view, ~s(nav.day-strip a[title="Tuesday"] .day-strip-theme), "arms")
      assert has_element?(view, ~s(nav.day-strip a[title="Thursday"] .day-strip-theme), "legs")
      # A day whose file gives none shows only its name.
      assert has_element?(view, ~s(nav.day-strip a[title="Monday"] .day-strip-name), "Mon")
      refute has_element?(view, ~s(nav.day-strip a[title="Monday"] .day-strip-theme))
    end

    test "the workout comes before the week and the section's tabs", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness/day/sunday")

      {day, _} = :binary.match(html, ~s(data-day="sunday"))
      {week, _} = :binary.match(html, ~s(id="the-week"))
      {tabs, _} = :binary.match(html, ~s(href="/fitness/wiki"))

      assert day < week
      assert week < tabs
    end

    test "a day that is not a weekday goes to today", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/fitness"}}} = live(conn, ~p"/fitness/day/someday")
    end

    test "a day renders its checklist, modules included", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness/day/sunday")
      assert html =~ "Sunday — Long Run"
      assert html =~ "Easy run"

      # Tuesday's exercises come from its `modules:` line, wiki links resolved.
      {:ok, _view, html} = live(conn, ~p"/fitness/day/tuesday")
      assert html =~ "Band rows"
      assert html =~ "/fitness/wiki/push-ups"
      assert option_count(html, "tuesday") == 0
      # Its line of week.md leads the page, with no clock times for a visitor.
      [head] = Regex.run(~r{<header class="day-page-head">.*?</header>}s, html)
      assert head =~ "Morning Spin"
      refute head =~ ~r/\d{1,2}:\d{2}/
    end

    test "a rotating day renders each option as a dropdown, one marked this week",
         %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness/day/friday")

      assert option_count(html, "friday") == 2
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

    # The day's workout comes first. Fuelling is a daily reference, so it
    # rides open in a side rail — after the workout in the markup, which is
    # where it lands when the rail folds on a narrow screen.
    test "fuelling sits open in a side rail after the workout", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")

      assert html =~ ~s(class="fuelling-rail")
      assert html =~ ~s(data-day="nutrition-module" open)

      {weekly, _} = :binary.match(html, ~s(class="day-details day-page"))
      {additional, _} = :binary.match(html, "Additional Modules")
      {rail, _} = :binary.match(html, ~s(class="fuelling-rail"))
      {fuelling, _} = :binary.match(html, ~s(data-day="nutrition-module"))

      assert weekly < rail
      assert additional < rail
      assert rail < fuelling
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
    # Push-ups is a file in the fixture wiki and nothing else: an exercise
    # needs no database row to be logged.
    setup %{conn: conn} do
      {:ok, view, _html} =
        conn |> init_test_session(%{"admin_user" => true}) |> live(~p"/fitness/day/tuesday")

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

    test "weight, sets and reps are kept as numbers, and shown the next time", %{view: view} do
      view
      |> form("form[phx-submit=save_log]", log: %{weight: "135", sets: "3", reps: "8"})
      |> render_submit()

      assert [%{slug: "push-ups", weight: 135.0, sets: 3, reps: 8}] =
               Web.Fitness.list_exercise_logs()

      view |> element("button.log-trigger[phx-value-slug='push-ups']") |> render_click()

      assert has_element?(view, ".log-history li", "135 lb · 3 × 8")
      assert has_element?(view, ".log-history-best", "135 lb")
      assert has_element?(view, "input[name='log[weight]'][placeholder='135']")
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

  # The page is public; the log is not. A visitor's socket can still be sent
  # the events by hand.
  describe "logging, as a visitor" do
    test "the events write nothing and show nothing", %{conn: conn} do
      {:ok, _} = Web.Fitness.log_exercise("push-ups", %{"weight" => "135"})
      {:ok, view, _html} = live(conn, ~p"/fitness/day/tuesday")

      html = render_click(view, "open_log", %{"slug" => "push-ups"})
      refute has_element?(view, ".log-modal")
      refute html =~ "135 lb"

      render_submit(view, "save_log", %{"log" => %{"weight" => "500"}})
      assert [%{weight: 135.0}] = Web.Fitness.list_exercise_logs()
    end
  end

  describe "The Week" do
    test "renders every day, each a link to its page, with today marked", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/fitness")

      assert Regex.scan(~r/data-week-day="/, html) |> length() == 7
      assert html =~ ~s(data-week-day="#{Web.Clock.today_slug()}" class="week-row is-today")
      assert week_section(html) =~ ~s(href="/fitness/day/thursday")
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
        conn |> init_test_session(%{"admin_user" => true}) |> live(~p"/fitness/day/tuesday")

      [head] = Regex.run(~r{<header class="day-page-head">.*?</header>}s, html)
      assert head =~ "6:45–7:30"

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
