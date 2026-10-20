defmodule Web.CutsTest do
  use Web.DataCase, async: false

  import Web.NegativesFixtures

  alias Web.Logs
  alias Web.Cuts
  alias Web.Cuts.Timeline

  setup do
    root = archive!()
    folder = put_roll!(root, roll: "065", format: "35mm", color: "color")
    File.mkdir_p!(Path.join(folder, "frames"))
    File.write!(Path.join([folder, "frames", "06.png"]), png_bytes(30, 20))

    {:ok, cut} = Cuts.create_cut("Ferry")
    on_exit(fn -> File.rm_rf(Cuts.bin(cut.id)) end)
    %{cut: cut}
  end

  defp upload(name) do
    path = Path.join(System.tmp_dir!(), "upload_#{System.unique_integer([:positive])}_#{name}")
    File.write!(path, "a recording")
    path
  end

  test "a file dropped in the bin is kept, read and given a proxy", %{cut: cut} do
    source = upload("take.mov")
    {:ok, media} = Cuts.add_media(cut, source, "Take one.mov")

    refute File.exists?(source)
    media = Repo.reload!(media)

    assert %{
             kind: "video",
             status: "ready",
             duration_ms: 12_000,
             has_audio: true,
             name: "Take one.mov"
           } = media

    assert File.read!(Cuts.media_path(media)) == "a recording"
    assert File.regular?(Cuts.proxy_path(media))
    assert String.ends_with?(media.proxy, ".proxy.mp4")

    {:ok, sound} = Cuts.add_media(cut, upload("song.mp3"), "Song.mp3")
    assert %{kind: "audio", proxy: "m" <> _} = Repo.reload!(sound)
  end

  test "the bin is beside the uploads root, never under it", %{cut: cut} do
    uploads = Path.expand(Web.Uploads.root())
    refute String.starts_with?(Cuts.bin(cut.id), uploads <> "/")
  end

  test "a timeline is kept as the bin allows it", %{cut: cut} do
    {:ok, take} = Cuts.add_media(cut, upload("take.mov"), "take.mov")
    cut = Cuts.get_cut(cut.id)

    timeline =
      Timeline.empty()
      |> Timeline.add_take(Repo.reload!(take))
      |> Map.update!(
        "clips",
        &(&1 ++ [%{"kind" => "take", "media" => 999, "in" => 0, "out" => 100}])
      )

    {:ok, cut} = Cuts.save_timeline(cut, timeline)
    assert [%{"media" => id, "out" => 12_000}] = cut.timeline["clips"]
    assert id == take.id

    # Taking the file out of the bin takes it off the timeline.
    {:ok, cut} = Cuts.remove_media(cut, Repo.reload!(take))
    assert cut.timeline["clips"] == []
    refute File.exists?(Cuts.media_path(take))
  end

  test "an empty cut is not rendered", %{cut: cut} do
    assert {:error, reason} = Cuts.publish(cut, %{})
    assert reason =~ "nothing on the main track"
  end

  test "a cut renders into a new log, then the same log when it is cut again", %{cut: cut} do
    {:ok, take} = Cuts.add_media(cut, upload("take.mov"), "take.mov")
    cut = Cuts.get_cut(cut.id)

    timeline =
      Timeline.empty()
      |> Timeline.add_take(Repo.reload!(take))
      |> Timeline.add_still("065/6")
      |> Timeline.add_title(1_000)

    {:ok, cut} = Cuts.save_timeline(cut, timeline)
    Cuts.subscribe(cut.id)

    assert {:ok, _} = Cuts.publish(cut, %{"recorded_on" => "2026-10-12", "caption" => "Ferry"})
    assert_received {:cut_render, _percent}
    assert_received {:cut_rendered, %{status: "done", audio_log_id: log_id}}

    log = Logs.get_log!(log_id)

    assert %{
             status: "pending",
             kind: "video",
             caption: "Ferry",
             recorded_on: ~D[2026-10-12],
             published: false
           } = log

    assert File.read!(log.source_path) == "stub-media"
    assert String.contains?(log.source_path, "/staging/")
    # The work folder goes once the film is handed over; the bin stays.
    refute File.exists?(Path.join(Cuts.bin(cut.id), "render"))
    assert File.regular?(Cuts.media_path(take))

    # Again: the same log is given the new film, and keeps what it had.
    cut = Cuts.get_cut(cut.id)
    {:ok, log} = Logs.update_log(log, %{status: "ready", published: true})
    assert {:ok, _} = Cuts.publish(cut, %{"recorded_on" => "2030-01-01"})
    assert_received {:cut_rendered, %{audio_log_id: ^log_id}}

    log = Logs.get_log!(log.id)
    assert %{status: "pending", recorded_on: ~D[2026-10-12], published: true} = log
    assert length(Logs.list_logs()) == 1
  end

  test "a print gone from the archive fails the render, and says which", %{cut: cut} do
    {:ok, cut} = Cuts.save_timeline(cut, Timeline.add_still(Timeline.empty(), "065/9"))
    Cuts.subscribe(cut.id)

    assert {:ok, _} = Cuts.publish(cut, %{})
    assert_received {:cut_failed, %{status: "failed", render_error: reason}}
    assert reason =~ "065/9"
    assert Logs.list_logs() == []
  end

  test "deleting a cut takes its bin, and leaves its log", %{cut: cut} do
    {:ok, _} = Cuts.add_media(cut, upload("take.mov"), "take.mov")
    bin = Cuts.bin(cut.id)
    assert File.dir?(bin)

    {:ok, _} = Cuts.delete_cut(Cuts.get_cut(cut.id))
    refute File.exists?(bin)
    assert Cuts.get_cut(cut.id) == nil
  end
end
