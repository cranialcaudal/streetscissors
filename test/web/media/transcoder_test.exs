defmodule Web.Media.TranscoderTest do
  # Not async: the queue is driven directly, and one case sets an environment
  # variable that the stubbed ffmpeg reads.
  use Web.DataCase, async: false

  import Web.AudioFixtures

  alias Web.Audio
  alias Web.Media
  alias Web.Media.Transcoder
  alias Web.Uploads

  setup do
    name = :"transcoder_#{System.unique_integer([:positive])}"
    {:ok, pid} = Transcoder.start_link(name: name, requeue_on_boot: false)
    # The queue is its own process, so the sandbox has to lend it the test's
    # connection explicitly.
    Ecto.Adapters.SQL.Sandbox.allow(Web.Repo, self(), pid)

    %{queue: pid}
  end

  defp pending_log(attrs) do
    source = Uploads.stage_upload!(media_upload_fixture(), Map.get(attrs, :name, "take.webm"))

    attrs
    |> Map.delete(:name)
    |> Map.merge(%{status: "pending", source_path: source, media_dir: nil, poster_path: nil})
    |> log_fixture()
  end

  defp run(queue, log) do
    Transcoder.enqueue(queue, log.id)
    Transcoder.await_idle(queue)
    Audio.get_log!(log.id)
  end

  describe "a video entry" do
    test "becomes one progressive MP4 and is marked ready", %{queue: queue} do
      log = run(queue, pending_log(%{kind: "video"}))

      assert log.status == "ready"
      assert log.transcode_error == nil
      assert log.media_dir =~ ~r/^#{log.slug}-[0-9a-f]{8}$/
      assert Audio.Log.media_url(log) =~ ~r{/video\.mp4$}

      dir = Uploads.entry_dir!(log.media_dir)
      assert File.regular?(Path.join(dir, Media.video_rendition()))
      assert File.regular?(Path.join(dir, Media.poster()))
      refute File.exists?(Path.join(dir, "master.m3u8"))
    end

    test "the staged source is deleted once there is a rendition to keep instead",
         %{queue: queue} do
      pending = pending_log(%{kind: "video"})
      source = pending.source_path

      log = run(queue, pending)

      assert log.source_path == nil
      refute File.regular?(source)
    end

    test "size and dimensions are recorded from the output", %{queue: queue} do
      log = run(queue, pending_log(%{kind: "video"}))

      assert log.size_bytes > 0
      assert log.width == 1280
      assert log.height == 720
    end
  end

  # The source is gone once an entry is ready, so a change to the encode is
  # applied by re-encoding the entry from its own rendition.
  describe "re-encoding a finished entry" do
    test "runs again from its own rendition, into a fresh directory", %{queue: queue} do
      first = run(queue, pending_log(%{kind: "video"}))

      {:ok, _} =
        Audio.update_log(first, %{trim_start_ms: 1500, trim_duration_ms: 9000, poster_at_ms: 4000})

      old_dir = Uploads.entry_dir!(first.media_dir)

      {:ok, queued} = Media.reencode(Audio.get_log!(first.id))

      # The trims are already in the rendition; applying them again would cut twice.
      assert queued.source_path == Path.join(old_dir, Media.video_rendition())
      assert queued.trim_start_ms == nil
      assert queued.trim_duration_ms == nil
      assert queued.poster_at_ms == 4000

      Transcoder.enqueue(queue, queued.id)
      Transcoder.await_idle(queue)
      log = Audio.get_log!(first.id)

      assert log.status == "ready"
      assert log.source_path == nil
      assert log.media_dir != first.media_dir
      assert File.regular?(Path.join(Uploads.entry_dir!(log.media_dir), Media.video_rendition()))
      refute File.dir?(old_dir)
    end

    test "reads the top rung of a legacy HLS ladder when there is no MP4" do
      dir = Uploads.new_media_dir("2026-09-18")
      Uploads.create_entry_dir!(dir)
      root = Uploads.entry_dir!(dir)
      File.mkdir_p!(Path.join(root, "v0"))
      File.write!(Path.join(root, "v0/index.m3u8"), "#EXTM3U")

      log = log_fixture(kind: "video", status: "ready", media_dir: dir)

      assert {:ok, queued} = Media.reencode(log)
      assert queued.source_path == Path.join(root, "v0/index.m3u8")
      assert queued.status == "pending"
    end

    test "refuses an entry that is not finished" do
      assert {:error, _} = Media.reencode(log_fixture(status: "pending"))
    end
  end

  describe "an audio entry" do
    test "gets an audio rendition and a waveform rather than a video", %{queue: queue} do
      log = run(queue, pending_log(%{kind: "audio", name: "voice.m4a"}))

      assert log.status == "ready"

      dir = Uploads.entry_dir!(log.media_dir)
      assert File.regular?(Path.join(dir, Media.audio_rendition()))
      assert File.regular?(Path.join(dir, Media.poster()))
      refute File.regular?(Path.join(dir, Media.video_rendition()))
    end
  end

  describe "a source that is not what the form claimed" do
    test "a 'video' with no video track is corrected to audio, so its url points at something",
         %{queue: queue} do
      # The stub probe reports audio-only for an audio extension.
      log = run(queue, pending_log(%{kind: "video", name: "actually-audio.m4a"}))

      assert log.kind == "audio"
      assert log.status == "ready"

      url = Web.Audio.Log.media_url(log)
      assert url =~ Media.audio_rendition()
      assert File.regular?(Path.join(Uploads.root(), String.replace_prefix(url, "/uploads/", "")))
    end
  end

  describe "failure" do
    test "is recorded with ffmpeg's own words, and leaves nothing behind", %{queue: queue} do
      System.put_env("STUB_FFMPEG_FAIL", "1")
      on_exit(fn -> System.delete_env("STUB_FFMPEG_FAIL") end)

      pending = pending_log(%{kind: "video"})
      log = run(queue, pending)

      assert log.status == "failed"
      assert log.transcode_error =~ "ffmpeg exited 1"
      assert log.transcode_error =~ "Invalid data"
      # No half-written directory left on disk.
      assert log.media_dir == nil
      # The source is kept, which is what makes a retry possible at all.
      assert File.regular?(pending.source_path)

      Uploads.discard_staged(pending.source_path)
    end

    test "a log whose source vanished fails rather than hanging the queue", %{queue: queue} do
      pending = pending_log(%{kind: "video"})
      File.rm!(pending.source_path)

      log = run(queue, pending)

      assert log.status == "failed"
      assert log.transcode_error =~ "source file is gone"
    end

    test "a log deleted between enqueue and dequeue is skipped, not crashed on", %{queue: queue} do
      pending = pending_log(%{kind: "video"})
      {:ok, _} = Audio.delete_log(pending)

      Transcoder.enqueue(queue, pending.id)
      assert Transcoder.await_idle(queue) == :ok
      assert Process.alive?(queue)
    end
  end

  describe "progress" do
    test "is broadcast to whoever is watching that log", %{queue: queue} do
      log = pending_log(%{kind: "video"})
      Transcoder.subscribe(log.id)

      Transcoder.enqueue(queue, log.id)
      Transcoder.await_idle(queue)

      log_id = log.id
      assert_received {:transcode_progress, ^log_id, percent}
      assert percent > 0 and percent <= 99
      assert_received {:transcode_done, ^log_id, :ready}
    end
  end

  describe "the queue" do
    test "runs one job at a time", %{queue: queue} do
      a = pending_log(%{kind: "video", recorded_on: ~D[2026-09-18]})
      b = pending_log(%{kind: "video", recorded_on: ~D[2026-09-19]})

      Transcoder.enqueue(queue, a.id)
      Transcoder.enqueue(queue, b.id)
      Transcoder.await_idle(queue)

      assert Audio.get_log!(a.id).status == "ready"
      assert Audio.get_log!(b.id).status == "ready"
    end

    test "reports what it is doing" do
      assert %{current: nil, queued: []} = Transcoder.status(Web.Media.Transcoder)
    end
  end

  describe "resuming after a restart" do
    test "every unfinished entry is picked up again on boot" do
      stranded = pending_log(%{kind: "video", recorded_on: ~D[2026-09-18]})
      {:ok, _} = Audio.update_log(stranded, %{status: "processing"})

      name = :"resume_#{System.unique_integer([:positive])}"
      {:ok, pid} = Transcoder.start_link(name: name, requeue_on_boot: false)
      Ecto.Adapters.SQL.Sandbox.allow(Web.Repo, self(), pid)

      # What handle_continue(:requeue, …) does on a real boot, once the
      # sandbox has lent this process a connection.
      send(pid, {:"$gen_cast", {:enqueue, stranded.id}})
      Transcoder.await_idle(pid)

      assert Audio.get_log!(stranded.id).status == "ready"
    end

    test "list_unfinished_logs is what the boot requeue reads" do
      a = pending_log(%{kind: "video", recorded_on: ~D[2026-09-18]})

      {:ok, b} =
        Audio.update_log(pending_log(%{recorded_on: ~D[2026-09-19]}), %{status: "processing"})

      _done = log_fixture(recorded_on: ~D[2026-09-20], status: "ready")

      assert Enum.map(Audio.list_unfinished_logs(), & &1.id) |> Enum.sort() ==
               Enum.sort([a.id, b.id])
    end
  end
end
