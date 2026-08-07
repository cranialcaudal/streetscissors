defmodule WebWeb.AdminLive.RidesManagerTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Web.Rides.LiveTracking

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/rides")
  end

  test "admin can start and end a live session", %{conn: conn} do
    {:ok, view, html} = live(admin_conn(conn), "/admin/rides")
    assert html =~ "live-tracking-panel"
    refute html =~ "Live now"

    view
    |> form("#live-tracking-panel form[phx-submit=start_live]", %{
      "url" => "https://www.komoot.com/live/abc",
      "note" => "Fred Whitton"
    })
    |> render_submit()

    html = render(view)
    assert html =~ "Live now"
    assert html =~ "https://www.komoot.com/live/abc"
    assert %{url: "https://www.komoot.com/live/abc"} = LiveTracking.current()

    view |> element("#stop-live-btn") |> render_click()
    assert render(view) =~ "Live session ended."
    assert LiveTracking.current() == nil
  end

  test "an invalid live link flashes an error and stores nothing", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/rides")

    view
    |> form("#live-tracking-panel form[phx-submit=start_live]", %{
      "url" => "https://evil.example/live",
      "note" => ""
    })
    |> render_submit()

    assert render(view) =~ "Live link must be an https komoot.com URL."
    assert LiveTracking.current() == nil
  end

  test "an expired session is shown as expired with a clear action", %{conn: conn} do
    {:ok, _info} = LiveTracking.start_live("https://www.komoot.com/live/old")

    stale = DateTime.utc_now() |> DateTime.add(-15 * 3600, :second) |> DateTime.to_iso8601()
    {:ok, _} = Web.SiteSettings.put_setting("live_ride_started_at", stale)

    {:ok, view, html} = live(admin_conn(conn), "/admin/rides")
    assert html =~ "expired"

    view |> element("#stop-live-btn") |> render_click()
    assert LiveTracking.raw().url == ""
  end

  test "admin can save the auto-expiry ttl", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/rides")

    view
    |> form("#live-tracking-panel form[phx-submit=save_live_ttl]", %{"hours" => "20"})
    |> render_submit()

    assert LiveTracking.ttl_hours() == 20
  end
end
