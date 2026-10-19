defmodule WebWeb.AdminLive.DashboardTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  import Web.GeneralFixtures

  import Web.NegativesFixtures

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

  # What a card says, as one line of text.
  defp card_text(view, id) do
    view
    |> element("#" <> id)
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
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

  describe "the program cards" do
    test "each program has a card, with its first action filled in", %{conn: conn} do
      archive!()
      {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

      for {id, title, action, href} <- [
            {"program-darkroom", "Darkroom", "Scan", "/admin/scanner"},
            {"program-cuts", "Cutting room", "Record a log", "/admin/logs"},
            {"program-writing", "Writing", "New post", "/admin/blog#new-post-form"},
            {"program-training", "Training", "Fitness", "/admin/fitness"},
            {"program-mail", "Mail", "Inbox", "/admin/inbox"}
          ] do
        assert has_element?(view, "#" <> id <> " .st-card-title", title)
        assert has_element?(view, "#" <> id <> ~s( a.adm-btn--primary[href="#{href}"]), action)
      end
    end

    test "a darkroom with nothing in it says so and offers Scan", %{conn: conn} do
      archive!()
      {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

      assert card_text(view, "program-darkroom") =~
               "Nothing on the bench and no prints yet. Scan a roll to begin."

      refute has_element?(view, "#program-darkroom img")
    end

    test "the roll on the bench, its strips and the singles still owed", %{conn: conn} do
      root = archive!()
      put_roll!(root, roll: "065", format: "35mm", color: "color")
      dir = Web.Scanner.Pipeline.roll_dir("066", "2026-10-18", "35mm", "color")
      File.mkdir_p!(dir)

      put_strips!(dir, [
        {656, 2152, [{1, {0, 0, 656, 700}}, {2, {0, 726, 656, 700}}]},
        {656, 2152, [{3, {0, 0, 656, 700}}]},
        {656, 2152, [{4, {0, 0, 656, 700}}]}
      ])

      File.write!(
        Path.join(dir, "selects.json"),
        Jason.encode!(%{"frames" => %{"2" => %{"chosen" => true}}})
      )

      {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

      assert card_text(view, "program-darkroom") =~
               "Roll 066 on the bench, 3 strips, 1 single still to scan"

      refute card_text(view, "program-darkroom") =~ "Nothing on the bench"
    end

    test "an edited print is the darkroom's picture, with a way to its page", %{conn: conn} do
      root = archive!()
      folder = put_roll!(root, roll: "065", format: "35mm", color: "color")
      put_print!(folder, 6)
      File.mkdir_p!(Path.join(folder, "edits"))
      File.write!(Path.join([folder, "edits", "06.json"]), "{}")

      {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

      assert has_element?(view, ~s(#program-darkroom img[src^="/negatives/frame/65/6"]))
      assert card_text(view, "program-darkroom") =~ "1 print edited, the last just now"
      assert card_text(view, "program-darkroom") =~ "frame 6 of roll 065"
    end

    test "drafts and the last post are on the writing card", %{conn: conn} do
      blog = Path.join(System.tmp_dir!(), "blog-cards-#{System.unique_integer([:positive])}")
      File.mkdir_p!(blog)
      original = Application.get_env(:web, :blog_path)
      Application.put_env(:web, :blog_path, blog)

      on_exit(fn ->
        File.rm_rf!(blog)
        Application.put_env(:web, :blog_path, original)
      end)

      File.write!(
        Path.join(blog, "wip.md"),
        ~s(---\ntitle: "Half a thought"\ndate: "2026-10-10"\ndraft: true\n---\n\nText.\n)
      )

      File.write!(
        Path.join(blog, "done.md"),
        ~s(---\ntitle: "Finished"\ndate: "2026-10-03"\n---\n\nText.\n)
      )

      {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")
      text = card_text(view, "program-writing")

      assert text =~ "1 draft, the newest Half a thought"
      assert text =~ "Last published Finished, Oct 3"
      assert text =~ "1 post has no description"
      assert text =~ "1 post has no keywords"
      assert has_element?(view, ~s(#program-writing a[href="/admin/blog/wip/edit"]))
      # Content health renders every page: linked, never built here.
      assert has_element?(view, ~s(#program-writing a[href="/admin/health"]))
    end

    test "the mail card quotes the newest open message", %{conn: conn} do
      {:ok, _} =
        Contact.create_message(%{
          name: "Ada Reader",
          email: "ada@example.com",
          message: "Which film was that?\nAnd the camera?"
        })

      guestbook_entry_fixture(%{approved: false})

      {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")
      text = card_text(view, "program-mail")

      assert text =~ "1 message open"
      assert text =~ "1 signature held for approval"
      assert text =~ "Newest, from Ada Reader"
      assert text =~ "Which film was that?"
      refute text =~ "And the camera?"
    end

    test "a cut and a log waiting are on the cutting room's card", %{conn: conn} do
      {:ok, cut} = Web.Cuts.create_cut("Sunday log")
      on_exit(fn -> File.rm_rf(Web.Cuts.bin(cut.id)) end)
      Web.AudioFixtures.log_fixture(%{published: false})

      {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")
      text = card_text(view, "program-cuts")

      assert text =~ "Sunday log, nothing on the timeline yet"
      assert text =~ "1 log ready, not yet published"

      assert has_element?(
               view,
               ~s(#program-cuts a[href="/admin/cuts/#{cut.id}"]),
               "Open the last cut"
             )
    end
  end

  describe "the figures" do
    setup :quiet_site

    test "one item says all is well once the monitor has looked", %{conn: conn} do
      Web.SiteSettings.put_setting(
        "monitor_state",
        Jason.encode!(%{
          "at" => DateTime.to_iso8601(DateTime.utc_now()),
          "checks" => [
            %{"key" => "disk", "label" => "Disk", "state" => "ok", "detail" => "26% free"}
          ],
          "failing" => %{}
        })
      )

      {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

      assert has_element?(view, "#figures", "all well")
      refute has_element?(view, "#figures .st-strip-item--warn")
      refute has_element?(view, "#figures .st-strip-item--fail")
    end

    test "a failing check tones the machine once, and is named under Needs you", %{conn: conn} do
      Web.SiteSettings.put_setting(
        "monitor_state",
        Jason.encode!(%{
          "at" => DateTime.to_iso8601(DateTime.utc_now()),
          "checks" => [
            %{
              "key" => "certificate",
              "label" => "Certificate",
              "state" => "fail",
              "detail" => "6 days left"
            }
          ],
          "failing" => %{}
        })
      )

      {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")

      # The strip says so once, in the failing tone; the check itself is named
      # under "Needs you", not repeated in the strip.
      assert has_element?(view, "#figures .st-strip-item--fail", "Machine")
      refute has_element?(view, "#figures", "Certificate")
      refute has_element?(view, "#figures", "all well")
      assert has_element?(view, "#needs-you", "Certificate: 6 days left")
    end

    test "the counts on file are links, and traffic arrives after the page is up", %{conn: conn} do
      {:ok, view, html} = live(admin_conn(conn), "/admin/dashboard")

      assert has_element?(view, ~s(#figures a[href="/admin/blog"]), "Posts")
      assert has_element?(view, ~s(#figures a[href="/admin/guestbook"]), "Signatures")
      refute html =~ "Visitors today"

      render_async(view)

      assert has_element?(view, "#figures", "Visitors today")
      assert has_element?(view, "#figures", "Views today")
      assert has_element?(view, "#figures", "Views in 56 weeks")
    end

    test "the full machine and the most viewed are there, closed", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/dashboard")
      render_async(view)

      assert has_element?(view, "details#machine > summary", "The machine in full")
      assert has_element?(view, "details#machine #system", "Database snapshots")
      assert has_element?(view, "details#most-viewed > summary", "Most viewed")
      assert has_element?(view, "details#most-viewed", "No views recorded yet.")
      refute has_element?(view, "details[open]")
    end
  end
end
