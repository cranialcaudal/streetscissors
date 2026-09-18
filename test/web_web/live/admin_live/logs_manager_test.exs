defmodule WebWeb.AdminLive.LogsManagerTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest
  import Web.AudioFixtures

  alias Web.Audio
  alias Web.Audio.Log
  alias Web.Uploads

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  # Stands in for the recorder handing LiveView a blob, or for a file dropped
  # onto the theater — both arrive through the same upload.
  defp attach(view, name \\ "take.webm", type \\ "video/webm") do
    file_input(view, "#log-form", :media, [
      %{name: name, content: File.read!(media_upload_fixture()), type: type}
    ])
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/logs")
  end

  describe "the theater" do
    test "renders a screen, a record control and both modes", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), "/admin/logs")

      assert html =~ ~s(class="theater-screen")
      assert html =~ ~s(data-role="record")
      assert html =~ ~s(data-mode="video")
      assert html =~ ~s(data-mode="audio")
    end

    test "the review controls start hidden — there is nothing to review yet", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")
      assert has_element?(view, ~s([data-role="review"][hidden]))
    end

    test "carries every element the recorder hook reaches for", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

      # The hook works entirely through these data-roles. The recorder this
      # replaced broke precisely this way — it reached for ids that had moved,
      # found nothing, and silently did nothing at all.
      for role <- ~w(record record-label placeholder placeholder-title tally elapsed meter
                     cameras mics camera-field device-error review trim-in trim-out
                     poster-at in-label out-label poster-label retake save-draft publish) do
        assert has_element?(view, ~s([data-role="#{role}"])),
               "the theater is missing [data-role=#{role}], which the recorder hook needs"
      end
    end

    test "the camera picker and the error line are their own elements", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

      # The picker is hidden in audio mode by the hook, so it needs a wrapper
      # of its own rather than the hook hiding the <select> and orphaning its
      # caption.
      assert has_element?(view, ~s([data-role="camera-field"] select[data-role="cameras"]))

      # A device failure is said here. It used to be written into the
      # placeholder with textContent, which replaced its children with a bare
      # string and lost the drop hint for good.
      assert has_element?(view, ~s([data-role="device-error"][hidden]))
      assert has_element?(view, ~s([data-role="placeholder"] [data-role="placeholder-title"]))
      assert has_element?(view, ~s([data-role="placeholder"] [data-role="placeholder-hint"]))
    end

    test "the file input sits inside the form, which is what makes uploads work",
         %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

      # Not decoration: `this.upload/2` puts the file on this input and relies
      # on the form's phx-change to allocate an entry. Outside a form it is
      # silently inert.
      assert has_element?(view, ~s(#log-form input[type="file"][name="media"]))
    end
  end

  describe "ingest" do
    test "an arriving recording is written down immediately, queued, and not yet public",
         %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

      render_upload(attach(view), "take.webm")

      assert [log] = Audio.list_logs()
      assert log.status == "pending"
      assert log.kind == "video"
      assert log.source_path =~ "staging/"
      assert File.regular?(log.source_path)
      # Pending, so it is not on the public page whatever its published flag.
      assert Audio.list_ready_logs() == []
    end

    test "it is titled and addressed by the day it arrived", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")
      render_upload(attach(view), "take.webm")

      [log] = Audio.list_logs()
      today = Web.Clock.local_today()

      assert log.recorded_on == today
      assert log.slug == Date.to_iso8601(today)
      assert Log.title(log) == Calendar.strftime(today, "%A, %-d %B %Y")
    end

    test "a second recording the same day gets the next address", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")
      render_upload(attach(view, "one.webm"), "one.webm")

      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")
      render_upload(attach(view, "two.webm"), "two.webm")

      today = Date.to_iso8601(Web.Clock.local_today())
      assert Enum.map(Audio.list_logs(), & &1.slug) |> Enum.sort() == [today, "#{today}-2"]
    end

    test "the recorder's trim and poster survive the change event the upload triggers",
         %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

      # What the hook pushes before it sends a single byte.
      render_hook(view, "stage", %{
        "trim_start_ms" => 800,
        "trim_duration_ms" => 2401,
        "poster_at_ms" => 1200,
        "published" => "true"
      })

      render_upload(attach(view), "take.webm")

      assert [log] = Audio.list_logs()
      assert log.trim_start_ms == 800
      assert log.trim_duration_ms == 2401
      assert log.poster_at_ms == 1200
      assert log.published
    end

    test "an audio file dropped in is filed as audio, whatever the form says", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

      render_upload(attach(view, "voice.m4a", "audio/mp4"), "voice.m4a")

      assert [%Log{kind: "audio"}] = Audio.list_logs()
    end

    test "metadata typed before the take travels with it", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

      view
      |> form("#log-form", log: %{caption: "Under way", keywords: "Ferry, Bowling Green"})
      |> render_change()

      render_upload(attach(view), "take.webm")

      assert [log] = Audio.list_logs()
      assert log.caption == "Under way"
      assert log.keywords == "ferry, bowling-green"
    end
  end

  describe "the archive" do
    test "shows what each entry is doing", %{conn: conn} do
      log_fixture(recorded_on: ~D[2026-09-18], status: "ready")

      log_fixture(
        recorded_on: ~D[2026-09-17],
        status: "failed",
        transcode_error: "ffmpeg exited 1"
      )

      {:ok, _view, html} = live(admin_conn(conn), "/admin/logs")

      assert html =~ "Ready"
      assert html =~ "Failed"
      assert html =~ "ffmpeg exited 1"
    end

    test "flags a finished entry with no keywords", %{conn: conn} do
      log_fixture(status: "ready", keywords: nil)

      {:ok, _view, html} = live(admin_conn(conn), "/admin/logs")

      assert html =~ "No keywords"
    end

    test "publishing is a separate decision that can be made while it encodes", %{conn: conn} do
      log = log_fixture(published: false)

      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

      view
      |> element(~s(button[phx-click="toggle_published"][phx-value-id="#{log.id}"]))
      |> render_click()

      assert Audio.get_log!(log.id).published
    end

    test "editing changes the metadata without touching the media", %{conn: conn} do
      log = log_fixture(media_dir: "2026-09-18-abc12345", caption: "First pass")

      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")
      view |> element(~s(button[phx-click="edit"][phx-value-id="#{log.id}"])) |> render_click()

      view
      |> form("#log-form", log: %{caption: "Second pass"})
      |> render_submit()

      updated = Audio.get_log!(log.id)
      assert updated.caption == "Second pass"
      assert updated.media_dir == "2026-09-18-abc12345"
    end

    test "deleting takes the media directory with it", %{conn: conn} do
      dir = Uploads.new_media_dir("2026-09-18")
      Uploads.create_entry_dir!(dir)
      File.write!(Path.join(Uploads.entry_dir!(dir), "poster.jpg"), "jpeg")
      log = log_fixture(media_dir: dir)

      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")
      view |> element(~s(button[phx-click="delete"][phx-value-id="#{log.id}"])) |> render_click()

      assert Audio.list_logs() == []
      refute File.dir?(Uploads.entry_dir!(dir))
    end

    test "a failed entry can be re-queued while its source is still on disk", %{conn: conn} do
      source = Uploads.stage_upload!(media_upload_fixture(), "take.webm")
      log = log_fixture(status: "failed", source_path: source)

      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

      html =
        view |> element(~s(button[phx-click="retry"][phx-value-id="#{log.id}"])) |> render_click()

      assert html =~ "Re-queued"
      Uploads.discard_staged(source)
    end

    test "a failed entry whose source is gone says so rather than silently doing nothing",
         %{conn: conn} do
      log = log_fixture(status: "failed", source_path: nil)

      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

      html =
        view |> element(~s(button[phx-click="retry"][phx-value-id="#{log.id}"])) |> render_click()

      assert html =~ "has to be re-recorded"
    end
  end

  describe "transcode progress" do
    test "a progress broadcast reaches the page", %{conn: conn} do
      log = log_fixture(status: "processing")

      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")
      send(view.pid, {:transcode_progress, log.id, 42})

      assert render(view) =~ "42%"
    end

    test "finishing clears the bar and reloads the row", %{conn: conn} do
      log = log_fixture(status: "processing")

      {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")
      send(view.pid, {:transcode_progress, log.id, 42})
      assert render(view) =~ "42%"

      {:ok, _} = Audio.mark_ready(log, %{media_dir: "done-12345678"})
      send(view.pid, {:transcode_done, log.id, :ready})

      html = render(view)
      refute html =~ "42%"
      assert html =~ "Ready"
    end
  end
end
