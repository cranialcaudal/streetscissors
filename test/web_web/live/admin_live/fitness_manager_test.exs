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
end
