defmodule WebWeb.LiveRideLiveTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Web.Rides
  alias Web.Rides.LiveTracking

  @live_url "https://www.komoot.com/live/test123"

  defp planned_fixture do
    points = [
      %{lat: 54.54, lon: -3.15, altitude_m: 100.0, recorded_at: ~U[2026-07-08 08:00:00Z]},
      %{lat: 54.55, lon: -3.15, altitude_m: 110.0, recorded_at: ~U[2026-07-08 08:00:01Z]}
    ]

    {:ok, ride} = Rides.create_imported_ride(points, %{"name" => "Fred Whitton"}, kind: "planned")
    ride
  end

  test "/live redirects (302) to the live page", %{conn: conn} do
    conn = get(conn, "/live")
    assert redirected_to(conn, 302) == "/fitness/rides/live"
  end

  test "idle state shows planned routes and no iframe", %{conn: conn} do
    planned_fixture()

    {:ok, _view, html} = live(conn, ~p"/fitness/rides/live")
    assert html =~ "live-ride-idle"
    assert html =~ "Not riding right now"
    assert html =~ "Fred Whitton"
    refute html =~ "live-ride-frame"
    assert html =~ "bento-fitness-sub-row"
  end

  test "active session renders the CTA link", %{conn: conn} do
    {:ok, _info} = LiveTracking.start_live(@live_url, "day 4")

    {:ok, _view, html} = live(conn, ~p"/fitness/rides/live")
    assert html =~ "live-ride-active"
    assert html =~ "LIVE — riding now"
    assert html =~ "day 4"
    assert html =~ ~s(id="live-komoot-cta")
    assert html =~ ~s(href="#{@live_url}")
    refute html =~ ~s(id="live-ride-frame")
  end

  test "an expired session renders the idle state", %{conn: conn} do
    {:ok, _info} = LiveTracking.start_live(@live_url)

    stale = DateTime.utc_now() |> DateTime.add(-15 * 3600, :second) |> DateTime.to_iso8601()
    {:ok, _} = Web.SiteSettings.put_setting("live_ride_started_at", stale)

    {:ok, _view, html} = live(conn, ~p"/fitness/rides/live")
    assert html =~ "live-ride-idle"
    refute html =~ "live-ride-frame"
  end

  test "an open page flips live without refresh on start and stop", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/fitness/rides/live")
    assert html =~ "live-ride-idle"

    {:ok, _info} = LiveTracking.start_live(@live_url)
    assert render(view) =~ "live-ride-active"

    :ok = LiveTracking.stop_live()
    assert render(view) =~ "live-ride-idle"
  end

  test "rides index shows the live banner only when live", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/fitness/rides")
    refute html =~ "rides-live-banner"

    {:ok, _info} = LiveTracking.start_live(@live_url)

    {:ok, _view, html} = live(conn, ~p"/fitness/rides")
    assert html =~ "rides-live-banner"
    assert html =~ "follow the ride"
  end

  test "rides index banner appears live via pubsub", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/fitness/rides")
    refute html =~ "rides-live-banner"

    {:ok, _info} = LiveTracking.start_live(@live_url)
    assert render(view) =~ "rides-live-banner"
  end
end
