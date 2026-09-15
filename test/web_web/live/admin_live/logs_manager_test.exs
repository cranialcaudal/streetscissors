defmodule WebWeb.AdminLive.LogsManagerTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  import Web.AudioFixtures

  alias Web.Audio

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  defp attach_audio(view, name \\ "ferry notes.mp3") do
    file_input(view, "#log-form", :audio, [
      %{name: name, content: File.read!(audio_upload_fixture()), type: "audio/mpeg"}
    ])
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/logs")
  end

  test "a log is described first, then the file is attached to that description", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

    attach_audio(view) |> render_upload("ferry notes.mp3")

    # The AudioDuration hook fills the hidden duration input from the file's
    # own metadata and fires a change; that is what puts a real length on a log.
    render_change(view, "validate", %{
      "log" => %{
        "title" => "Ferry To Bowling Green",
        "recorded_on" => "2026-03-15",
        "keywords" => "Ferry, Bowling Green",
        "description" => "Notes from the water.",
        "duration" => "252",
        "published" => "true"
      }
    })

    view |> form("#log-form") |> render_submit()

    assert [log] = Audio.list_logs()
    assert log.title == "Ferry To Bowling Green"
    assert log.slug == "ferry-to-bowling-green"
    assert log.keywords == "ferry, bowling-green"
    assert log.recorded_on == ~D[2026-03-15]
    assert log.duration == 252
    assert log.published
    assert log.file_path =~ ~r"^/uploads/logs/ferry-notes-\d+\.mp3$"

    # The stored file really is on disk where the public page will look for it
    on_disk = Path.join(Web.Uploads.root(), String.replace_prefix(log.file_path, "/uploads/", ""))
    assert File.exists?(on_disk)

    Audio.delete_log(log)
  end

  test "submitting without a file saves nothing and says so", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

    html =
      view
      |> form("#log-form", %{
        "log" => %{"title" => "No File", "recorded_on" => "2026-03-15", "keywords" => "x"}
      })
      |> render_submit()

    assert html =~ "Choose an audio file to upload."
    assert Audio.list_logs() == []
  end

  test "an invalid form leaves nothing on disk", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

    before = uploaded_files()

    attach_audio(view) |> render_upload("ferry notes.mp3")

    # No title — the changeset is checked before the file is copied into place
    view
    |> form("#log-form", %{"log" => %{"title" => "", "recorded_on" => "2026-03-15"}})
    |> render_submit()

    assert Audio.list_logs() == []
    assert uploaded_files() == before
  end

  test "a log can be edited without re-uploading its recording", %{conn: conn} do
    log = log_fixture(title: "Original Title", keywords: "old")
    {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

    view |> element("button[phx-click=edit][phx-value-id='#{log.id}']") |> render_click()

    view
    |> form("#log-form", %{
      "log" => %{
        "title" => "Revised Title",
        "recorded_on" => Date.to_iso8601(log.recorded_on),
        "keywords" => "ferry, new",
        "published" => "true"
      }
    })
    |> render_submit()

    updated = Audio.get_log!(log.id)
    assert updated.title == "Revised Title"
    assert updated.keywords == "ferry, new"
    # The recording, and the address it was published at, both survive the edit
    assert updated.file_path == log.file_path
    assert updated.slug == log.slug
  end

  test "publish state can be toggled from the archive", %{conn: conn} do
    log = log_fixture(title: "Toggle Me", published: true)
    {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")

    view
    |> element("button[phx-click=toggle_published][phx-value-id='#{log.id}']")
    |> render_click()

    refute Audio.get_log!(log.id).published
  end

  test "the archive flags a log that cannot be filtered", %{conn: conn} do
    log_fixture(title: "Unfiled", keywords: "")
    {:ok, _view, html} = live(admin_conn(conn), "/admin/logs")

    assert html =~ "no keywords"
  end

  test "deleting a log removes the row and its file", %{conn: conn} do
    web_path = Audio.store_upload(audio_upload_fixture(), "doomed.mp3")
    on_disk = Path.join(Web.Uploads.root(), String.replace_prefix(web_path, "/uploads/", ""))
    log = log_fixture(title: "Doomed", file_path: web_path)

    {:ok, view, _html} = live(admin_conn(conn), "/admin/logs")
    view |> element("button[phx-click=delete][phx-value-id='#{log.id}']") |> render_click()

    assert Audio.list_logs() == []
    refute File.exists?(on_disk)
  end

  defp uploaded_files do
    case File.ls(Path.join(Web.Uploads.root(), "logs")) do
      {:ok, files} -> Enum.sort(files)
      _ -> []
    end
  end
end
