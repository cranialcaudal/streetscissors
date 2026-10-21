defmodule WebWeb.AdminLive.SettingsTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Web.SiteSettings

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/settings")
  end

  # The admin layout's flash group wore the same never-generated utility
  # classes as the public one.
  test "saving the playlist is confirmed in a notice", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/settings")

    view
    |> form("form[phx-submit=save_settings]", spotify_playlist_id: "abc123")
    |> render_submit()

    assert has_element?(view, ".admin-layout #flash-info.flash-notice", "Playlist saved: abc123")
    assert SiteSettings.get_setting("spotify_playlist_id") == "abc123"
  end

  test "a pasted share link is reduced to its playlist id", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/settings")

    view
    |> form("form[phx-submit=save_settings]",
      spotify_playlist_id: "https://open.spotify.com/playlist/37i9dQ?si=xyz"
    )
    |> render_submit()

    assert SiteSettings.get_setting("spotify_playlist_id") == "37i9dQ"
  end

  test "the newsletter's test address is saved, and a bad one refused", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/settings")

    view
    |> form("form[phx-submit=save_test_email]", newsletter_test_email: "not an address")
    |> render_submit()

    assert SiteSettings.get_setting("newsletter_test_email") == nil

    view
    |> form("form[phx-submit=save_test_email]", newsletter_test_email: "me@example.com")
    |> render_submit()

    assert SiteSettings.get_setting("newsletter_test_email") == "me@example.com"
  end

  describe "alerts" do
    use Oban.Testing, repo: Web.Repo

    test "the address the site writes to is saved, and a bad one refused", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/settings")

      view |> form("#settings-alerts", notify_email: "not an address") |> render_submit()
      assert Web.Notify.address() == nil

      view |> form("#settings-alerts", notify_email: "me@example.com") |> render_submit()
      assert Web.Notify.address() == "me@example.com"
      assert has_element?(view, "#flash-info", "Alerts go to me@example.com.")
    end

    test "a test can be sent once there is an address, and not before", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/settings")
      refute has_element?(view, "#settings-alerts-test")

      view |> form("#settings-alerts", notify_email: "me@example.com") |> render_submit()
      view |> element("#settings-alerts-test") |> render_click()

      assert_enqueued(worker: Web.Workers.OwnerMail, args: %{"to" => "me@example.com"})
    end

    test "clearing either address works rather than crashing", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/settings")

      view |> form("#settings-alerts", notify_email: "me@example.com") |> render_submit()
      view |> form("#settings-alerts", notify_email: "") |> render_submit()
      assert Web.Notify.address() == nil

      view
      |> form("#settings-newsletter", newsletter_test_email: "me@example.com")
      |> render_submit()

      view |> form("#settings-newsletter", newsletter_test_email: "") |> render_submit()
      assert SiteSettings.get_setting("newsletter_test_email") == nil
    end
  end

  # They make real pictures with ImageMagick 7's `magick`; without it they skip.
  @no_magick is_nil(System.find_executable("magick")) && "ImageMagick 7 (magick) is not installed"

  describe "the About page's pictures" do
    @describetag skip: @no_magick

    setup do
      dir = Path.join(Web.Uploads.root(), "about")
      File.rm_rf!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      png =
        Path.join(
          System.tmp_dir!(),
          "settings-portrait-#{System.unique_integer([:positive])}.png"
        )

      {_, 0} = System.cmd("magick", ["-size", "40x50", "xc:gray", png])
      on_exit(fn -> File.rm(png) end)
      # a different picture each time: the same one sent twice is kept once
      picture = fn n ->
        other = png <> ".#{n}.png"
        {_, 0} = System.cmd("magick", ["-size", "40x50", "xc:gray#{n * 5}", other])
        bytes = File.read!(other)
        File.rm(other)
        bytes
      end

      %{png: File.read!(png), picture: picture}
    end

    test "a picture sent from the page is kept, listed, and shown on /about", %{
      conn: conn,
      png: png
    } do
      {:ok, view, html} = live(admin_conn(conn), "/admin/settings")
      assert html =~ "None yet"

      view
      |> file_input("#settings-portraits", :portrait, [
        %{name: "me.png", content: png, type: "image/png"}
      ])
      |> render_upload("me.png")

      assert [path] = Web.Author.portraits()
      assert has_element?(view, ~s(#settings-portrait-list img[src="#{path}"]))
      assert conn |> get(~p"/about") |> html_response(200) =~ path
    end

    test "any number may be sent, and one can be removed", %{conn: conn, picture: picture} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/settings")

      for n <- 1..12 do
        name = "p#{n}.png"

        view
        |> file_input("#settings-portraits", :portrait, [
          %{name: name, content: picture.(n), type: "image/png"}
        ])
        |> render_upload(name)
      end

      assert length(Web.Author.portraits()) == 12
      [first | _] = Web.Author.portraits()
      view |> element(~s(button[phx-value-path="#{first}"])) |> render_click()
      assert length(Web.Author.portraits()) == 11
      refute has_element?(view, ~s(img[src="#{first}"]))
    end
  end
end
