defmodule WebWeb.RidesLiveTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest
  import Web.RidesFixtures

  alias Web.Rides

  test "old /rides paths redirect permanently to /fitness/rides", %{conn: conn} do
    conn1 = get(conn, "/rides")
    assert redirected_to(conn1, 301) == "/fitness/rides"

    conn2 = get(conn, "/rides/123")
    assert redirected_to(conn2, 301) == "/fitness/rides/123"
  end

  test "index shows the empty state when nothing is imported", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/fitness/rides")
    assert html =~ "No rides logged yet"
  end

  test "index lists recorded rides with stats", %{conn: conn} do
    {:ok, ride} = Rides.import_gpx(gpx_fixture(), %{"name" => "Lakes loop"})

    {:ok, _view, html} = live(conn, ~p"/fitness/rides")
    assert html =~ "Lakes loop"
    assert html =~ ~p"/fitness/rides/#{ride.id}"
  end

  test "index shows planned routes beside completed rides", %{conn: conn} do
    points = [
      %{lat: 54.54, lon: -3.15, altitude_m: 100.0, recorded_at: ~U[2026-07-08 08:00:00Z]},
      %{lat: 54.55, lon: -3.15, altitude_m: 110.0, recorded_at: ~U[2026-07-08 08:00:01Z]}
    ]

    {:ok, _ride} =
      Rides.create_imported_ride(points, %{"name" => "Fred Whitton"}, kind: "planned")

    {:ok, _view, html} = live(conn, ~p"/fitness/rides")
    assert html =~ "rides-columns--split"
    assert html =~ "Planned routes"
    assert html =~ "Completed"
    assert html =~ "Fred Whitton"
  end

  test "index stays single-column with nothing planned", %{conn: conn} do
    {:ok, _ride} = Rides.import_gpx(gpx_fixture(), %{"name" => "Lakes loop"})

    {:ok, _view, html} = live(conn, ~p"/fitness/rides")
    refute html =~ "rides-columns--split"
  end

  test "index renders the komoot profile embed only when configured", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/fitness/rides")
    refute html =~ "ride-komoot-embed"

    {:ok, _setting} =
      Web.SiteSettings.put_setting("komoot_embed_url", "https://www.komoot.com/user/x/embed")

    {:ok, _view, html} = live(conn, ~p"/fitness/rides")
    assert html =~ "ride-komoot-embed"
    assert html =~ "https://www.komoot.com/user/x/embed"
  end

  test "index ignores a non-komoot embed URL", %{conn: conn} do
    {:ok, _setting} =
      Web.SiteSettings.put_setting("komoot_embed_url", "https://evil.example/embed")

    {:ok, _view, html} = live(conn, ~p"/fitness/rides")
    refute html =~ "evil.example"
  end

  test "index includes the fitness sub-nav", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/fitness/rides")
    assert html =~ "bento-fitness-sub-row"
    assert html =~ "/fitness/wiki"
  end

  test "fitness pages link to rides in the sub-nav", %{conn: conn} do
    for path <- ["/fitness", "/fitness/wiki", "/fitness/regimen"] do
      {:ok, _view, html} = live(conn, path)
      assert html =~ "/fitness/rides", "expected #{path} to link to /fitness/rides"
    end
  end

  test "show renders the ride detail with map and stats", %{conn: conn} do
    {:ok, ride} = Rides.import_gpx(gpx_fixture(), %{"name" => "Lakes loop"})

    {:ok, _view, html} = live(conn, ~p"/fitness/rides/#{ride.id}")
    assert html =~ "Lakes loop"
    assert html =~ "ride-map-#{ride.id}"
    assert html =~ "ride-elevation-#{ride.id}"
    assert html =~ "moving time"
    refute html =~ "ride-komoot-embed"
  end

  test "show renders the komoot tour embed when attached", %{conn: conn} do
    {:ok, ride} = Rides.import_gpx(gpx_fixture(), %{"name" => "Lakes loop"})
    {:ok, ride} = Rides.attach_komoot(ride, "987654321")

    {:ok, _view, html} = live(conn, ~p"/fitness/rides/#{ride.id}")
    assert html =~ "https://www.komoot.com/tour/987654321/embed?profile=1"
  end

  test "show hides speed stats for planned routes", %{conn: conn} do
    points = [
      %{lat: 54.54, lon: -3.15, altitude_m: 100.0, recorded_at: ~U[2026-07-08 08:00:00Z]},
      %{lat: 54.55, lon: -3.15, altitude_m: 110.0, recorded_at: ~U[2026-07-08 08:00:01Z]}
    ]

    {:ok, ride} =
      Rides.create_imported_ride(points, %{"name" => "Fred Whitton"}, kind: "planned")

    {:ok, _view, html} = live(conn, ~p"/fitness/rides/#{ride.id}")
    assert html =~ "planned route"
    refute html =~ "moving time"
  end
end
