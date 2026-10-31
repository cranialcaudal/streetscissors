defmodule WebWeb.AdminLive.FuelingTest do
  # Not async: one test points the vault at an empty folder.
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  # The plan is the invented test/support/fixtures/fitness/fueling.json.

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/fitness/fueling")
  end

  test "a day's targets, meals, supplements and staples come from the vault's plan", %{
    conn: conn
  } do
    {:ok, view, html} = live(admin_conn(conn), "/admin/fitness/fueling?day=tuesday")

    assert html =~ "An invented plan for the tests."
    assert has_element?(view, "#fueling-day-summary", "Tuesday — Intervals")
    assert has_element?(view, "#fueling-day-summary", "2600 kcal")
    assert has_element?(view, "#fueling-slots", "Rice bowl with eggs")
    assert has_element?(view, "#fueling-slots", "Totals for the fixture.")

    assert has_element?(
             view,
             ~s(#fueling-supplements-morning a[href="https://example.com/vitamin-d"]),
             "Vitamin D"
           )

    assert has_element?(view, "#fueling-supplements-morning", "Electrolyte tab")
    assert has_element?(view, "#fueling-supplements-evening", "Magnesium")
    assert has_element?(view, "#fueling-staples", "Oatmeal")
  end

  test "the tabs are the plan's days, in week order, and switch the day", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/fitness/fueling?day=monday")

    assert has_element?(view, ~s(.adm-tabs a[href="/admin/fitness/fueling?day=saturday"]))
    refute has_element?(view, ~s(.adm-tabs a[href="/admin/fitness/fueling?day=sunday"]))

    view
    |> element(~s(.adm-tabs a[href="/admin/fitness/fueling?day=saturday"]))
    |> render_click()

    assert_patch(view, "/admin/fitness/fueling?day=saturday")
    assert has_element?(view, "#fueling-day-summary", "3100 kcal")
    assert has_element?(view, "#fueling-slots", "Pancakes and fruit")
  end

  test "a day the plan does not have opens one it does", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/fitness/fueling?day=nonsense")
    assert has_element?(view, "#fueling-day-summary")
  end

  test "with no plan in the vault the page says where to write one", %{conn: conn} do
    empty = Path.join(System.tmp_dir!(), "fueling_none_#{System.unique_integer([:positive])}")
    File.mkdir_p!(empty)
    prev = Application.get_env(:web, :fitness_path)
    Application.put_env(:web, :fitness_path, empty)

    on_exit(fn ->
      Application.put_env(:web, :fitness_path, prev)
      File.rm_rf(empty)
    end)

    {:ok, view, _html} = live(admin_conn(conn), "/admin/fitness/fueling")
    assert has_element?(view, "#fueling-none", "content/fitness/fueling.json")
    refute has_element?(view, "#fueling-day-summary")
  end
end
