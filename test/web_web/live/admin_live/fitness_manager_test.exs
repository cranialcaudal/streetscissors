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
    assert has_element?(view, "#editor-form .adm-ed[hidden] textarea[name='exercise[content]']")
  end

  test "the editor is the document editor, and its preview reads [[wiki]] links as the site does",
       %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/fitness")

    view
    |> element(~s(button[phx-click=edit_exercise][phx-value-slug="push-ups"]))
    |> render_click()

    assert has_element?(
             view,
             "#wiki-exercise-push-ups[phx-hook=DocumentEditor][data-complete=fitness]"
           )

    assert_push_event(view, "editor:set", %{id: "wiki-exercise-push-ups"})

    view
    |> form("#editor-form", exercise: %{content: "Pair it with [[push-ups|Push-ups]]."})
    |> render_change()

    html = view |> element("button", "Preview") |> render_click()
    assert html =~ ~s(href="/fitness/wiki/push-ups")

    render_hook(view, "editor_complete", %{"q" => "push", "kind" => "link", "scope" => "fitness"})
    assert_reply(view, %{items: [%{insert: "[[push-ups|Push-ups]]"}]})
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

  test "the check-in tab is gone, and its old address lands on the wiki", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/fitness?tab=checkin")

    refute has_element?(view, ~s(a[href="/admin/fitness?tab=checkin"]))
    refute has_element?(view, "#checkin-form")
    assert has_element?(view, "#exercise-filter")
  end

  test "the vault's files open whole, and a block that would not read is not saved",
       %{conn: conn} do
    file = Path.join([Web.Fitness.Vault.base_path(), "blocks", "test-block.md"])
    before = File.read!(file)

    {:ok, view, html} = live(admin_conn(conn), "/admin/fitness?tab=files")
    assert html =~ "Reads as:"
    assert has_element?(view, ~s(a[href="/admin/fitness?tab=files&file=block%3Atest-block"]))

    broken = String.replace(before, "weeks: 520", "weeks: many")
    view |> form("#source-form", source: %{content: broken}) |> render_change()
    assert has_element?(view, "#source-check", "Will not be saved")

    view |> form("#source-form", source: %{content: broken}) |> render_submit()
    assert has_element?(view, "#flash-error", "Not saved")
    assert File.read!(file) == before
  end
end
