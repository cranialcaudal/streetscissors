defmodule WebWeb.AdminLive.QuickAddTest do
  # Notes are appended to a scratch file shared by the suite: not async.
  use WebWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  setup do
    File.rm(Web.Notes.inbox_path())
    :ok
  end

  test "nobody but the admin reaches it", %{conn: conn} do
    assert {:error, {:redirect, _}} = live(conn, ~p"/admin/quick")
  end

  test "a set is logged by the exercise's name, under today", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/quick")

    view
    |> form("#quick-log", log: %{exercise: "Push-ups", sets: "3", reps: "12"})
    |> render_submit()

    assert has_element?(view, "#flash-info", "Logged Push-ups: 3 x 12.")

    assert [%{date: date, metrics: %{"sets" => "3", "reps" => "12"}}] =
             Web.Fitness.list_exercise_logs()

    assert date == Web.Clock.local_today()
  end

  test "a name the wiki does not have is refused", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/quick")
    view |> form("#quick-log", log: %{exercise: "Juggling", sets: "3"}) |> render_submit()

    assert has_element?(view, "#flash-error", "no exercise by that name")
    assert Web.Fitness.list_exercise_logs() == []
  end

  test "today's check-in is saved from its tab", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/quick?tab=checkin")

    view
    |> form("#quick-checkin", checkin: %{answers: %{shoulder: "sore"}})
    |> render_submit()

    assert has_element?(view, "#flash-info", "Check-in saved.")
    assert %{answers: %{"shoulder" => "sore"}} = Web.Fitness.checkin_on(Web.Clock.local_today())
  end

  test "a note becomes one dated line in the private inbox", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/quick?tab=note")

    view
    |> form("#quick-note", note: %{text: "Try the 400\nat box speed", keywords: "Film, New York"})
    |> render_submit()

    assert has_element?(view, "#flash-info", "Noted.")
    today = Date.to_iso8601(Web.Clock.local_today())

    assert File.read!(Web.Notes.inbox_path()) ==
             "- #{today} Try the 400 — at box speed #film #new-york\n"
  end
end
