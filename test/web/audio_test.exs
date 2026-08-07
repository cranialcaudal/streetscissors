defmodule Web.AudioTest do
  use Web.DataCase

  import Web.AudioFixtures

  alias Web.Audio
  alias Web.Audio.Log

  describe "changeset" do
    test "derives a slug from the title" do
      log = log_fixture(title: "Ferry to Bowling Green")
      assert log.slug == "ferry-to-bowling-green"
    end

    test "keeps its slug when the title is later edited, so the URL survives" do
      log = log_fixture(title: "First Title")
      {:ok, updated} = Audio.update_log(log, %{"title" => "A Completely Different Title"})

      assert updated.slug == "first-title"
      assert updated.title == "A Completely Different Title"
    end

    test "normalizes keywords into canonical storage" do
      log = log_fixture(keywords: "Film, Bowling Green , film")

      assert log.keywords == "film, bowling-green"
      assert Log.keyword_list(log) == ["film", "bowling-green"]
    end

    test "derives the stardate from the recording date, not from today" do
      log = log_fixture(recorded_on: ~D[2026-03-15])
      assert log.stardate == Log.stardate(~D[2026-03-15])
      refute log.stardate == Log.stardate(Date.utc_today())
    end

    test "requires a title, a file and a recording date" do
      assert {:error, changeset} = Audio.create_log(%{})
      errors = errors_on(changeset)

      assert errors[:title]
      assert errors[:file_path]
      assert errors[:recorded_on]
    end

    test "rejects a duplicate slug" do
      log_fixture(title: "Same Name")

      assert {:error, changeset} =
               Audio.create_log(%{
                 "title" => "Same Name",
                 "file_path" => "/uploads/logs/other.mp3",
                 "recorded_on" => Date.utc_today()
               })

      assert errors_on(changeset)[:slug]
    end
  end

  describe "publishing" do
    test "list_published_logs hides drafts" do
      published = log_fixture(title: "Published", published: true)
      log_fixture(title: "Draft", published: false)

      assert [%Log{id: id}] = Audio.list_published_logs()
      assert id == published.id
    end

    test "get_published_log_by_slug 404s a draft rather than leaking it" do
      log_fixture(title: "Secret Draft", published: false)
      assert {:error, :not_found} = Audio.get_published_log_by_slug("secret-draft")
    end

    test "list_keywords tallies published logs only" do
      log_fixture(title: "A", keywords: "film, nyc", published: true)
      log_fixture(title: "B", keywords: "film", published: true)
      log_fixture(title: "C", keywords: "hidden-keyword", published: false)

      assert Audio.list_keywords() == [{"film", 2}, {"nyc", 1}]
    end
  end

  describe "uploads" do
    test "store_upload copies the file and returns its public path" do
      source = audio_upload_fixture()
      web_path = Audio.store_upload(source, "Ferry Notes.mp3")

      assert web_path =~ ~r"^/uploads/logs/ferry-notes-\d+\.mp3$"

      assert File.exists?(
               Path.join(Web.Uploads.root(), String.replace_prefix(web_path, "/uploads/", ""))
             )

      Audio.discard_upload(web_path)
    end

    test "deleting a log removes its audio file too" do
      source = audio_upload_fixture()
      web_path = Audio.store_upload(source, "throwaway.mp3")
      on_disk = Path.join(Web.Uploads.root(), String.replace_prefix(web_path, "/uploads/", ""))

      log = log_fixture(title: "Throwaway", file_path: web_path)
      assert File.exists?(on_disk)

      {:ok, _} = Audio.delete_log(log)
      refute File.exists?(on_disk)
    end

    test "discard_upload refuses paths outside the logs upload dir" do
      outside = Path.join(System.tmp_dir!(), "not-ours-#{System.unique_integer([:positive])}.mp3")
      File.write!(outside, "keep me")

      Audio.discard_upload("/uploads/../../#{Path.basename(outside)}")
      Audio.discard_upload("/images/uploads/#{Path.basename(outside)}")

      assert File.exists?(outside)
      File.rm!(outside)
    end
  end

  describe "play tracking" do
    test "records plays and counts them per log" do
      log = log_fixture(title: "Counted")

      Audio.record_play(log.id, "127.0.0.1")
      Audio.record_play(log.id, "127.0.0.2")

      assert Audio.get_play_count(log.id) == 2
      assert Audio.get_all_play_counts() == %{log.id => 2}
    end
  end
end
