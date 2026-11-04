defmodule Web.HappeningTest do
  use Web.DataCase

  alias Web.Happening

  describe "lately" do
    test "the newest published posts, never a draft, each with its picture or nil" do
      posts = Happening.build().lately.posts
      assert length(posts) in 1..3
      refute Enum.any?(posts, &(&1.path == "/blog/draft-post"))

      assert Enum.map(posts, & &1.path) ==
               Web.Blog.list_posts() |> Enum.take(3) |> Enum.map(&"/blog/#{&1.slug}")

      assert Enum.all?(posts, &Map.has_key?(&1, :cover))
    end

    test "the newest roll, with its prints" do
      assert %{roll: "001", path: "/negatives/roll/001", prints: prints, count: count} =
               Happening.build().lately.roll

      assert count == length(Web.Negatives.list_frames("001"))
      assert Enum.all?(prints, &String.starts_with?(&1.path, "/negatives/roll/001/frame/"))
    end

    test "the newest log; a video names its file to preview, a recording of sound does not" do
      assert Happening.build().lately.log == nil

      Web.AudioFixtures.log_fixture(recorded_on: ~D[2026-09-17], kind: "audio")
      assert %{video: nil} = Happening.build().lately.log

      video = Web.AudioFixtures.log_fixture(recorded_on: ~D[2026-09-18], kind: "video")
      assert %{path: path, video: src} = Happening.build().lately.log
      assert path == "/logs/#{video.slug}"
      assert src == Web.Logs.Log.media_url(video)
    end
  end
end
