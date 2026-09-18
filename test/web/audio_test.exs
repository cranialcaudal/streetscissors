defmodule Web.AudioTest do
  use Web.DataCase, async: true

  import Web.AudioFixtures

  alias Web.Audio
  alias Web.Audio.Log
  alias Web.Uploads

  describe "titles and addresses" do
    test "an entry is titled by the day it was recorded" do
      log = log_fixture(recorded_on: ~D[2026-09-18])
      assert Log.title(log) == "Friday, 18 September 2026"
    end

    test "the address is the date" do
      assert %Log{slug: "2026-09-18"} = log_fixture(recorded_on: ~D[2026-09-18])
    end

    test "a second recording the same day takes the next ordinal and its own address" do
      first = log_fixture(recorded_on: ~D[2026-09-18])
      second = log_fixture(recorded_on: ~D[2026-09-18])
      third = log_fixture(recorded_on: ~D[2026-09-18])

      assert {first.seq, first.slug} == {1, "2026-09-18"}
      assert {second.seq, second.slug} == {2, "2026-09-18-2"}
      assert {third.seq, third.slug} == {3, "2026-09-18-3"}
    end

    test "only entries after the first are marked with an ordinal" do
      assert Log.ordinal(log_fixture(recorded_on: ~D[2026-09-18])) == nil
      assert Log.ordinal(log_fixture(recorded_on: ~D[2026-09-18])) == "02"
    end

    test "the ordinal restarts the next day" do
      log_fixture(recorded_on: ~D[2026-09-18])
      assert %Log{seq: 1, slug: "2026-09-19"} = log_fixture(recorded_on: ~D[2026-09-19])
    end

    test "the address follows the date when the date is corrected" do
      log = log_fixture(recorded_on: ~D[2026-09-18])
      {:ok, moved} = Audio.update_log(log, %{"recorded_on" => "2026-09-20"})

      assert moved.slug == "2026-09-20"
      assert moved.stardate == Log.stardate(~D[2026-09-20])
    end
  end

  describe "changeset" do
    test "keywords are normalized to the shared vocabulary" do
      log = log_fixture(keywords: "  Ferry ,  Bowling Green ")
      assert log.keywords == "ferry, bowling-green"
      assert Log.keyword_list(log) == ["ferry", "bowling-green"]
    end

    test "a stardate is derived from the recording date, never taken as input" do
      log = log_fixture(recorded_on: ~D[2026-09-18], stardate: "nonsense")
      assert log.stardate == Log.stardate(~D[2026-09-18])
    end

    test "kind and status are constrained" do
      assert {:error, changeset} =
               Audio.create_log(%{recorded_on: ~D[2026-09-18], kind: "hologram"})

      assert "is invalid" in errors_on(changeset).kind

      assert {:error, changeset} =
               Audio.create_log(%{recorded_on: ~D[2026-09-18], status: "whenever"})

      assert "is invalid" in errors_on(changeset).status
    end

    test "a recording date is required" do
      assert {:error, changeset} = Audio.create_log(%{kind: "video"})
      assert "can't be blank" in errors_on(changeset).recorded_on
    end

    test "a caption is optional — the date is the title" do
      assert %Log{caption: nil} = log_fixture()
    end
  end

  describe "what the public may see" do
    test "an entry still transcoding is not listed, however published it is" do
      ready = log_fixture(recorded_on: ~D[2026-09-18], published: true, status: "ready")
      _pending = log_fixture(recorded_on: ~D[2026-09-19], published: true, status: "pending")

      assert [%Log{id: id}] = Audio.list_ready_logs()
      assert id == ready.id
    end

    test "an entry still transcoding 404s at its own address rather than leaking" do
      log = log_fixture(published: true, status: "processing")
      assert {:error, :not_found} = Audio.get_ready_log_by_slug(log.slug)
    end

    test "a draft 404s at its own address" do
      log = log_fixture(published: false, status: "ready")
      assert {:error, :not_found} = Audio.get_ready_log_by_slug(log.slug)
    end

    test "a failed transcode is invisible too" do
      log = log_fixture(published: true, status: "failed")
      assert Audio.list_ready_logs() == []
      assert {:error, :not_found} = Audio.get_ready_log_by_slug(log.slug)
    end

    test "keywords are tallied across public entries only" do
      log_fixture(recorded_on: ~D[2026-09-18], keywords: "ferry", published: true)
      log_fixture(recorded_on: ~D[2026-09-19], keywords: "ferry", published: false)

      assert Audio.list_keywords() == [{"ferry", 1}]
    end

    test "a slug that is not a string is simply not found" do
      assert {:error, :not_found} = Audio.get_ready_log_by_slug(nil)
    end
  end

  describe "media urls" do
    test "a ready video plays from its HLS master playlist" do
      log = log_fixture(kind: "video", status: "ready", media_dir: "2026-09-18-abc123")
      assert Log.media_url(log) == "/uploads/logs/2026-09-18-abc123/master.m3u8"
    end

    test "a ready audio entry plays from a progressive rendition" do
      log = log_fixture(kind: "audio", status: "ready", media_dir: "2026-09-18-abc123")
      assert Log.media_url(log) == "/uploads/logs/2026-09-18-abc123/audio.m4a"
    end

    test "an entry with nothing playable yet has no url to point at" do
      assert Log.media_url(log_fixture(status: "pending")) == nil
    end
  end

  describe "transcode state" do
    test "unfinished entries are the ones a restart has to pick up again" do
      pending = log_fixture(recorded_on: ~D[2026-09-18], status: "pending")
      processing = log_fixture(recorded_on: ~D[2026-09-19], status: "processing")
      _ready = log_fixture(recorded_on: ~D[2026-09-20], status: "ready")
      _failed = log_fixture(recorded_on: ~D[2026-09-21], status: "failed")

      assert Enum.map(Audio.list_unfinished_logs(), & &1.id) == [pending.id, processing.id]
    end

    test "marking a failure keeps the reason for the admin to read" do
      log = log_fixture(status: "processing")
      {:ok, failed} = Audio.mark_failed(log, "ffmpeg exited 1")

      assert failed.status == "failed"
      assert failed.transcode_error == "ffmpeg exited 1"
    end

    test "marking ready clears a previous attempt's error" do
      log = log_fixture(status: "failed", transcode_error: "boom")
      {:ok, ready} = Audio.mark_ready(log, %{media_dir: "new-dir"})

      assert ready.status == "ready"
      assert ready.transcode_error == nil
      assert ready.media_dir == "new-dir"
    end

    test "re-transcoding destroys the directory it replaced, but only after the swap" do
      old = Uploads.new_media_dir("2026-09-18")
      Uploads.create_entry_dir!(old)
      File.write!(Path.join(Uploads.entry_dir!(old), "master.m3u8"), "#EXTM3U")

      log = log_fixture(status: "ready", media_dir: old)
      new = Uploads.new_media_dir("2026-09-18")
      Uploads.create_entry_dir!(new)

      {:ok, updated} = Audio.mark_ready(log, %{media_dir: new})

      assert updated.media_dir == new
      refute File.dir?(Uploads.entry_dir!(old))
      assert File.dir?(Uploads.entry_dir!(new))
    end
  end

  describe "deletion" do
    test "deleting a log takes its media directory with it" do
      dir = Uploads.new_media_dir("2026-09-18")
      Uploads.create_entry_dir!(dir)
      File.write!(Path.join(Uploads.entry_dir!(dir), "poster.jpg"), "jpeg")

      log = log_fixture(media_dir: dir)
      {:ok, _} = Audio.delete_log(log)

      refute File.dir?(Uploads.entry_dir!(dir))
    end

    test "a log with no media directory deletes cleanly" do
      log = log_fixture(status: "pending")
      assert {:ok, _} = Audio.delete_log(log)
    end
  end

  describe "uploads" do
    test "a media directory name is the slug plus a suffix, so a re-cut never reuses a path" do
      first = Uploads.new_media_dir("2026-09-18")
      second = Uploads.new_media_dir("2026-09-18")

      assert first =~ ~r/^2026-09-18-[0-9a-f]{8}$/
      refute first == second
    end

    test "a directory name that this module did not write is refused" do
      assert Uploads.entry_dir("../../etc") == :error
      assert Uploads.entry_dir("/etc/passwd") == :error
      assert Uploads.entry_dir(nil) == :error
      assert {:ok, _} = Uploads.entry_dir("2026-09-18-abc12345")
    end

    test "destroying an entry refuses a traversing name rather than following it" do
      canary = Path.join(System.tmp_dir!(), "canary-#{System.unique_integer([:positive])}")
      File.write!(canary, "do not delete me")

      assert Uploads.destroy_entry("../../#{Path.basename(canary)}") == :ok
      assert File.regular?(canary)

      File.rm(canary)
    end

    test "staging moves an upload out of the temp dir and keeps its extension" do
      source = media_upload_fixture(".webm")
      staged = Uploads.stage_upload!(source, "A Take.webm")

      assert Path.extname(staged) == ".webm"
      assert File.read!(staged) == "fake recording bytes"

      Uploads.discard_staged(staged)
      refute File.regular?(staged)
    end

    test "discarding refuses a path outside staging" do
      outside = Path.join(System.tmp_dir!(), "outside-#{System.unique_integer([:positive])}")
      File.write!(outside, "keep")

      assert Uploads.discard_staged(outside) == :ok
      assert File.regular?(outside)

      File.rm(outside)
    end
  end

  describe "totals" do
    test "years are Pacific-local, so a late-evening recording counts to the right year" do
      # 07:30 UTC on 1 January is still the evening of 31 December in California.
      newyear =
        log_fixture(
          recorded_on: ~D[2026-01-01],
          recorded_at: ~U[2026-01-01 07:30:00Z],
          duration: 60
        )

      assert [%{year: 2025, entries: 1, seconds: 60}] = Audio.yearly_totals([newyear])
    end

    test "totals group by year, newest first" do
      a =
        log_fixture(
          recorded_on: ~D[2026-03-01],
          recorded_at: ~U[2026-03-01 20:00:00Z],
          duration: 100
        )

      b =
        log_fixture(
          recorded_on: ~D[2026-04-01],
          recorded_at: ~U[2026-04-01 20:00:00Z],
          duration: 200
        )

      c =
        log_fixture(
          recorded_on: ~D[2025-04-01],
          recorded_at: ~U[2025-04-01 20:00:00Z],
          duration: 50
        )

      assert [
               %{year: 2026, entries: 2, seconds: 300},
               %{year: 2025, entries: 1, seconds: 50}
             ] = Audio.yearly_totals([a, b, c])
    end

    test "an entry with no duration does not poison the sum" do
      a = log_fixture(recorded_on: ~D[2026-03-01], duration: 100)
      b = log_fixture(recorded_on: ~D[2026-03-02], duration: nil)

      assert Audio.total_runtime([a, b]) == 100
    end
  end

  describe "play tracking" do
    test "plays are counted per log" do
      log = log_fixture()
      Audio.record_play(log.id, "127.0.0.1")
      Audio.record_play(log.id, "127.0.0.2")

      assert Audio.get_play_count(log.id) == 2
      assert Audio.get_all_play_counts() == %{log.id => 2}
    end
  end
end
