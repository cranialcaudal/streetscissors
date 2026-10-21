defmodule Web.HappeningTest do
  use Web.DataCase

  alias Web.Analytics.Hit
  alias Web.Happening

  defp hits(path, people) do
    for i <- 1..people do
      Repo.insert!(%Hit{path: path, ip_hash: "visitor-#{path}-#{i}"})
    end
  end

  test "now names the block's week, from the fixture vault's block" do
    assert %{now: %{block: "Test Block · Week " <> rest}} = Happening.build()
    assert rest =~ "— Push"
  end

  test "now names the newest clear activity by day, sport and distance only" do
    Web.RidesFixtures.ride_fixture(%{stranger_view: "exposed", distance_m: 9000.0})
    assert Happening.build().now.ride == nil

    ride = Web.RidesFixtures.ride_fixture(%{stranger_view: "clear", distance_m: 16093.4})
    assert %{path: path, sport: _, distance: distance, date: %Date{}} = Happening.build().now.ride
    assert path == "/fitness/rides/#{ride.id}"
    assert distance =~ "10"
  end

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

  test "witnessed is the three pieces most people read this week, public ones only" do
    hits("/blog/keyworded-post", 5)
    hits("/blog/bare-post", 3)
    hits("/blog/draft-post", 9)
    hits("/food", 20)
    hits("/Christ", 20)
    hits("/admin/dashboard", 20)
    hits("/blog/no-such-post", 20)

    assert [%{path: "/blog/keyworded-post", people: 5}, %{path: "/blog/bare-post", people: 3}] =
             Happening.witnessed(Web.Clock.local_today())
  end

  test "the same person reading twice is one" do
    Repo.insert!(%Hit{path: "/blog/bare-post", ip_hash: "same"})
    Repo.insert!(%Hit{path: "/blog/bare-post", ip_hash: "same"})
    assert [%{people: 1}] = Happening.witnessed(Web.Clock.local_today())
  end

  test "one reader at two spellings of an address is one person, not two" do
    Repo.insert!(%Hit{path: "/blog/bare-post", ip_hash: "reader"})
    Repo.insert!(%Hit{path: "/blog/bare-post?from=feed", ip_hash: "reader"})
    Repo.insert!(%Hit{path: "/blog/bare%2Dpost", ip_hash: "other"})

    assert [%{path: "/blog/bare-post", people: 2}] =
             Happening.witnessed(Web.Clock.local_today())
  end

  test "a hit older than the week does not count" do
    old =
      NaiveDateTime.add(NaiveDateTime.utc_now(), -10 * 86_400) |> NaiveDateTime.truncate(:second)

    Repo.insert!(%Hit{path: "/blog/bare-post", ip_hash: "x", inserted_at: old})
    assert Happening.witnessed(Web.Clock.local_today()) == []
  end
end
