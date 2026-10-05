defmodule WebWeb.AdminLive.DashboardTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  import Web.GeneralFixtures

  alias Web.Backup
  alias Web.Contact

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  # The queue lists posts without keywords, and the committed fixture posts
  # are not all keyworded, so tests that need an empty queue use an empty
  # blog. They also need a fresh database snapshot and a content backup that
  # has just run, since an overdue one of either is a queue row of its own.
  defp quiet_site(_context) do
    blog = Path.join(System.tmp_dir!(), "blog-empty-#{System.unique_integer([:positive])}")
    File.mkdir_p!(blog)
    original_blog = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, blog)

    File.mkdir_p!(Backup.backup_dir())
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    snapshot = Path.join(Backup.backup_dir(), "web-#{stamp}.db")
    File.write!(snapshot, "")

    {:ok, _} = Backup.Content.run()
    # And somewhere for the monitor to write to, or that is a row as well.
    Web.Notify.put_address("author@example.com")

    on_exit(fn ->
      File.rm_rf!(blog)
      File.rm(snapshot)
      File.rm_rf!(Backup.Content.backup_dir())
      Application.put_env(:web, :blog_path, original_blog)
    end)

    :ok
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/dashboard")
  end

  test "each waiting thing is a link to the page where it gets done", %{conn: conn} do
    guestbook_entry_fixture(%{approved: false})
    {:ok, _} = Contact.create_message(%{name: "Ada", email: "ada@example.com", message: "Hi"})

    {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

    assert has_element?(
             view,
             ~s(#needs-you a[href="/admin/guestbook?show=held"]),
             "signature waits for approval"
           )

    assert has_element?(view, ~s(#needs-you a[href="/admin/inbox?box=inbox"]), "in the inbox")
  end

  describe "on a quiet site" do
    setup :quiet_site

    test "the queue says so when nothing is waiting", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), "/admin/dashboard")
      assert html =~ "Nothing needs you."
    end
  end

  test "the machine panel reports the backups and the sync", %{conn: conn} do
    {:ok, _} = Backup.Content.run()
    on_exit(fn -> File.rm_rf!(Backup.Content.backup_dir()) end)

    {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

    assert has_element?(view, "#system", "Database snapshots")
    assert has_element?(view, "#system", "Written content")
    assert has_element?(view, "#system", "1 version kept")
    assert has_element?(view, "#system", "Komoot sync")
  end

  test "a fault the monitor found is in the queue, in its own words", %{conn: conn} do
    Web.SiteSettings.put_setting(
      "monitor_state",
      Jason.encode!(%{
        "at" => DateTime.to_iso8601(DateTime.utc_now()),
        "checks" => [
          %{
            "key" => "certificate",
            "label" => "Certificate",
            "state" => "fail",
            "detail" => "6 days left — renewal is failing"
          },
          %{"key" => "disk", "label" => "Disk", "state" => "ok", "detail" => "26% free (252 GB)"}
        ],
        "failing" => %{}
      })
    )

    {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

    assert has_element?(view, "#needs-you", "Certificate: 6 days left — renewal is failing")
    refute has_element?(view, "#needs-you", "Disk")
    assert has_element?(view, "#system", "26% free (252 GB)")
  end

  # The one fault here that means a stranger could see where the rides start.
  test "an activity that shows a private place is at the top of what needs you", %{conn: conn} do
    Application.put_env(:web, :ride_privacy_zones, "45.12345,7.54321")
    on_exit(fn -> Application.delete_env(:web, :ride_privacy_zones) end)
    Web.RidesFixtures.ride_fixture(%{stranger_view: "exposed"})

    {:ok, view, html} = live(admin_conn(conn), "/admin/dashboard")

    assert has_element?(
             view,
             "#needs-you a[href='/admin/rides']",
             "Ride privacy: 1 activity begins or ends at a private place as a stranger is shown it"
           )

    assert has_element?(view, "#system", "Ride privacy")
    refute html =~ "45.12345"
  end

  test "having no address for alerts is itself something to fix", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

    assert has_element?(
             view,
             ~s(#needs-you a[href="/admin/settings"]),
             "Faults have nobody to write to yet"
           )
  end

  test "an overdue content backup is something that needs you", %{conn: conn} do
    File.rm_rf!(Backup.Content.backup_dir())
    {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

    assert has_element?(view, "#needs-you", "The content backup is overdue")
  end

  test "the rail marks the page you're on and counts what's waiting", %{conn: conn} do
    guestbook_entry_fixture(%{approved: false})
    guestbook_entry_fixture(%{approved: false})

    {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

    assert has_element?(view, ~s(#adm-rail a[href="/admin/dashboard"][aria-current="page"]))
    refute has_element?(view, ~s(#adm-rail a[href="/admin/blog"][aria-current="page"]))
    assert has_element?(view, ~s(#adm-rail a[href="/admin/guestbook"] .adm-badge), "2")
  end

  # The indicator is in the root layout, so these read the dead render. The
  # login sets the flag to a real `true`, which is what SetCurrentUser checks.
  test "the admin indicator shows on public pages but not in the admin", %{conn: conn} do
    conn = init_test_session(conn, %{"admin_user" => true})

    assert conn |> get("/blog") |> html_response(200) =~ ~s(id="admin-indicator")
    refute conn |> get("/admin/dashboard") |> html_response(200) =~ ~s(id="admin-indicator")
  end
end
