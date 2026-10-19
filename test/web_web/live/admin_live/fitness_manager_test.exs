defmodule WebWeb.AdminLive.FitnessManagerTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  # Runs against the invented vault in test/support/fixtures/fitness. Nothing
  # here saves, so the committed fixtures are never rewritten.

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/fitness")
  end

  test "the wiki and the regimen are each an address", %{conn: conn} do
    {:ok, view, html} = live(admin_conn(conn), "/admin/fitness")
    assert html =~ "Push-ups"

    html = view |> element(~s(.adm-tabs a[href="/admin/fitness?tab=regimen"])) |> render_click()
    assert_patch(view, "/admin/fitness?tab=regimen")
    assert html =~ "Monday — Pool Laps"
    refute html =~ "Push-ups"
  end

  test "the name filter narrows the wiki", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/fitness")

    html = view |> form("#exercise-filter", query: "squat") |> render_change()
    refute html =~ "Push-ups"
    assert html =~ "No exercise matches"

    html = view |> form("#exercise-filter", query: "push") |> render_change()
    assert html =~ "Push-ups"
  end

  test "an exercise opens in the page, and its markdown previews", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/fitness")

    view
    |> element(~s(button[phx-click=edit_exercise][phx-value-slug="push-ups"]))
    |> render_click()

    assert has_element?(view, "#editor-form textarea[name='exercise[content]']")

    html = view |> element("button", "Preview") |> render_click()
    assert html =~ ~s(class="adm-prose")
    assert html =~ "A fixture exercise page."
    # Still in the form while previewing, so a save carries the body.
    assert has_element?(view, "#editor-form textarea[name='exercise[content]'][hidden]")
  end

  test "deleting asks first", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/fitness")
    assert has_element?(view, "button[phx-click=delete_exercise][data-confirm]")
  end

  test "the progress tab draws the block's charts", %{conn: conn} do
    {:ok, exercise} = Web.Fitness.loggable_exercise("push-ups")

    {:ok, _} =
      Web.Fitness.create_exercise_log(%{
        exercise_id: exercise.id,
        date: Web.Clock.local_today(),
        metrics: %{"weight" => "20 lbs", "sets" => "3", "reps" => "10"}
      })

    {:ok, _view, html} = live(admin_conn(conn), "/admin/fitness?tab=progress")

    assert html =~ "Test Block"
    assert html =~ ~s(id="chart-e1rm")
    assert html =~ ~s(id="chart-compliance")
    # One lift, one dot this week; one series needs no legend.
    [e1rm] = Regex.run(~r{<figure class="fc-chart" id="chart-e1rm">.*?</figure>}s, html)
    assert e1rm =~ "<circle"
  end

  test "a check-in is saved for the day, and a second one replaces it", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/fitness?tab=checkin")
    today = Date.to_iso8601(Web.Clock.local_today())

    view
    |> form("#checkin-form", checkin: %{date: today, pain: "3", sleep_hours: "7.5", energy: "6"})
    |> render_submit()

    assert has_element?(view, "#flash-info", "Check-in saved.")
    assert has_element?(view, "#checkin-guard", "Hold: pain 3 of 10")

    view |> form("#checkin-form", checkin: %{date: today, pain: "1"}) |> render_submit()

    assert [%{pain: 1}] = Web.Fitness.recent_checkins(Web.Clock.local_today())
    refute has_element?(view, "#checkin-guard")
  end

  test "a check-in out of range is refused", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/fitness?tab=checkin")

    html =
      view
      |> form("#checkin-form",
        checkin: %{date: Date.to_iso8601(Web.Clock.local_today()), pain: "11"}
      )
      |> render_submit()

    assert html =~ "Pain must be less than or equal to 10"
    assert Web.Fitness.recent_checkins(Web.Clock.local_today()) == []
  end
end
