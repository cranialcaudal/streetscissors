defmodule WebWeb.AdminLive.RidesManagerTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest
  import Web.RidesFixtures

  alias Web.Rides.KomootSync

  setup do
    on_exit(fn -> Application.delete_env(:web, :ride_privacy_zones) end)
  end

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  defp text(view, selector) do
    view
    |> element(selector)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/rides")
  end

  describe "the archive" do
    test "lists every activity with what Komoot has for it", %{conn: conn} do
      ride_fixture(%{name: "Lakes loop", started_at: ~U[2026-07-08 18:00:00Z]})

      shared =
        ride_fixture(%{
          name: "Home loop",
          visibility: "private",
          share_token: "sharetoken9f3",
          started_at: ~U[2026-07-01 18:00:00Z]
        })

      waiting =
        ride_fixture(%{
          name: "New loop",
          visibility: "private",
          stranger_view: nil,
          started_at: ~U[2026-06-20 18:00:00Z]
        })

      inside =
        ride_fixture(%{
          name: "Round the block",
          visibility: "private",
          share_token: "another9f3",
          stranger_view: "hidden",
          started_at: ~U[2026-06-10 18:00:00Z]
        })

      {:ok, view, html} = live(admin_conn(conn), "/admin/rides")

      assert has_element?(view, "button[phx-click='sync_komoot']", "Sync now")
      assert has_element?(view, "#rides tr", "Lakes loop")

      assert has_element?(view, "#ride-#{shared.id} .ride-private", "Private")
      refute has_element?(view, "#ride-#{shared.id}", "Not checked yet")
      refute has_element?(view, "#ride-#{shared.id}", "Hidden by Komoot")
      # A tour the sync has not yet read as a stranger shows nothing of Komoot's.
      assert has_element?(view, "#ride-#{waiting.id}", "Not checked yet")
      # One that never leaves the privacy zone: Komoot shows a stranger none of it.
      assert has_element?(view, "#ride-#{inside.id}", "Hidden by Komoot")

      # The link is what lets a stranger open a private tour. It is not shown.
      refute html =~ "sharetoken9f3"

      # With no place on file nothing is checked, and the two quieter states
      # are still said.
      status = text(view, "#privacy-status")
      assert status =~ "Not checked."
      assert status =~ "1 lies wholly inside Komoot's zone"
      assert status =~ "1 activity not checked yet"
    end

    test "says when the last pass ran and what came of it", %{conn: conn} do
      KomootSync.record_run({:error, :auth_failed})

      {:ok, _view, html} = live(admin_conn(conn), "/admin/rides")
      assert html =~ ":auth_failed"
    end
  end

  # The tripwire's verdict, said in numbers and never in places.
  describe "what strangers see" do
    test "with no place on file, Komoot is trusted and the page says so", %{conn: conn} do
      ride_fixture()

      {:ok, view, _html} = live(admin_conn(conn), "/admin/rides")
      assert text(view, "#privacy-status") =~ "Not checked."
      assert has_element?(view, "#privacy-status .adm-status-dot--warn")
    end

    test "with a place on file and nothing near it", %{conn: conn} do
      Application.put_env(:web, :ride_privacy_zones, "45.12345,7.54321")
      ride_fixture()

      {:ok, view, html} = live(admin_conn(conn), "/admin/rides")

      assert text(view, "#privacy-status") =~
               "No activity begins or ends near the private place on file as a stranger is shown it."

      assert has_element?(view, "#privacy-status .adm-status-dot--ok")
      refute text(view, "#privacy-status") =~ "mid-tour"
      refute text(view, "#privacy-status") =~ "wholly inside"
      refute text(view, "#privacy-status") =~ "not checked yet"
      refute html =~ "45.12345"
      refute html =~ "7.54321"
    end

    # Hidden is Komoot's zone at work, not a fault: the light stays green.
    test "tours Komoot hides altogether are counted, and are not a fault", %{conn: conn} do
      Application.put_env(:web, :ride_privacy_zones, "45.12345,7.54321")
      ride_fixture()
      ride_fixture(%{stranger_view: "hidden"})
      ride_fixture(%{stranger_view: "hidden"})

      {:ok, view, _html} = live(admin_conn(conn), "/admin/rides")

      status = text(view, "#privacy-status")
      assert status =~ "No activity begins or ends near the private place on file"

      assert status =~
               "2 lie wholly inside Komoot's zone, and Komoot shows a stranger nothing of them."

      assert has_element?(view, "#privacy-status .adm-status-dot--ok")
    end

    # Out, home for lunch, out again: a zone trims a tour's ends and nothing
    # else. Held back, said, marked in the archive, and no alarm.
    test "a tour that passes home mid-way is held back without the alarm", %{conn: conn} do
      Application.put_env(:web, :ride_privacy_zones, "45.12345,7.54321")
      ride_fixture()
      passing = ride_fixture(%{name: "Home for lunch", stranger_view: "passing"})

      {:ok, view, _html} = live(admin_conn(conn), "/admin/rides")

      status = text(view, "#privacy-status")
      assert status =~ "No activity begins or ends near the private place on file"

      assert status =~
               "1 passes it mid-tour, which a zone does not trim, and is shown without Komoot's map"

      assert has_element?(view, "#privacy-status .adm-status-dot--ok")
      assert has_element?(view, "#ride-#{passing.id} .adm-pill", "Passes home")
      refute has_element?(view, "#rides .adm-pill", "Exposed")
    end

    test "an exposed activity is counted, flagged, and marked in the archive", %{conn: conn} do
      Application.put_env(:web, :ride_privacy_zones, "45.12345,7.54321;46.5,8.5")
      ride_fixture(%{name: "Clear"})
      exposed = ride_fixture(%{name: "Past the door", stranger_view: "exposed"})

      {:ok, view, html} = live(admin_conn(conn), "/admin/rides")

      assert text(view, "#privacy-status") =~
               "1 activity still begins or ends at a private place as a stranger is shown it: " <>
                 "Komoot's privacy zone is not hiding it. Its embed and map are withheld."

      assert has_element?(view, "#privacy-status .adm-status-dot--fail")
      assert has_element?(view, "#ride-#{exposed.id} .adm-pill", "Exposed")
      refute has_element?(view, "#rides .adm-pill", "Not checked yet")
      refute html =~ "45.12345"
    end

    test "a setting that cannot be read is said plainly", %{conn: conn} do
      Application.put_env(:web, :ride_privacy_zones, "somewhere nice")
      ride_fixture()

      {:ok, view, _html} = live(admin_conn(conn), "/admin/rides")
      assert text(view, "#privacy-status") =~ "RIDE_PRIVACY_ZONES can't be read"
      assert has_element?(view, "#privacy-status .adm-status-dot--fail")
    end
  end
end
