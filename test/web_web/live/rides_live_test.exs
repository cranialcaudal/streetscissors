defmodule WebWeb.RidesLiveTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest
  import Web.RidesFixtures

  alias Web.Rides

  test "index shows the empty state when nothing is tracked", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/rides")
    assert html =~ "No rides logged yet"
  end

  test "index shows the live map while a ride is active", %{conn: conn} do
    {:ok, _ride} = Rides.start_ride(%{"name" => "Morning spin"})

    {:ok, _view, html} = live(conn, ~p"/rides")
    assert html =~ "live-ride-map"
    assert html =~ "Morning spin"
  end

  test "index lists completed rides with stats", %{conn: conn} do
    {:ok, ride} = Rides.import_gpx(gpx_fixture(), %{"name" => "Lakes loop"})

    {:ok, _view, html} = live(conn, ~p"/rides")
    assert html =~ "Lakes loop"
    assert html =~ ~p"/rides/#{ride.id}"
  end

  test "show renders the ride detail with map and stats", %{conn: conn} do
    {:ok, ride} = Rides.import_gpx(gpx_fixture(), %{"name" => "Lakes loop"})

    {:ok, _view, html} = live(conn, ~p"/rides/#{ride.id}")
    assert html =~ "Lakes loop"
    assert html =~ "ride-map-#{ride.id}"
    assert html =~ "ride-elevation-#{ride.id}"
    assert html =~ "moving time"
  end
end
