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
