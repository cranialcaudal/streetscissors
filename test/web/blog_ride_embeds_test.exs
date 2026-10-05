defmodule Web.Blog.RideEmbedsTest do
  use Web.DataCase

  import Web.RidesFixtures

  alias Web.Blog.Embeds
  alias Web.Rides.Thumbs

  setup do
    File.rm_rf!(Thumbs.dir())
    :ok
  end

  test "expands a ride embed into a card" do
    ride = ride_fixture(%{name: "Evening Loop"})
    html = Embeds.transform("<p>![[ride:#{ride.id}]]</p>")
    assert html =~ ~s(<figure class="blog-embed blog-embed-ride">)
    assert html =~ ~s(href="/fitness/rides/#{ride.id}")
    assert html =~ "Evening Loop"
    refute html =~ "<img"
  end

  test "escapes ride names" do
    ride = ride_fixture(%{name: "<script>alert(1)</script>"})
    html = Embeds.transform("![[ride:#{ride.id}]]")
    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end

  test "includes Komoot's picture of the route when one is cached" do
    ride = ride_fixture(%{map_image_url: "https://cdn.example/maps/1.jpg"})
    :ok = Thumbs.store(ride, "fake-jpeg")
    html = Embeds.transform("![[ride:#{ride.id}]]")

    assert html =~
             ~s(src="/fitness/rides/#{ride.id}/thumb?v=#{Thumbs.fingerprint(ride.map_image_url)}")
  end

  # The tripwire outranks the cache: an exposed ride's picture is never shown.
  test "an exposed ride's card has no picture, even with one on disk" do
    ride =
      ride_fixture(%{map_image_url: "https://cdn.example/maps/1.jpg", stranger_view: "exposed"})

    :ok = Thumbs.store(ride, "fake-jpeg")
    html = Embeds.transform("![[ride:#{ride.id}]]")

    assert html =~ ~s(href="/fitness/rides/#{ride.id}")
    refute html =~ "<img"
  end

  test "renders captions" do
    ride = ride_fixture()
    html = Embeds.transform("![[ride:#{ride.id}|Big day out]]")
    assert html =~ "<figcaption>Big day out</figcaption>"
  end

  test "unknown rides stay literal text; private ones expand like any other" do
    assert Embeds.transform("![[ride:999999]]") == "![[ride:999999]]"

    ride = ride_fixture(%{name: "Home loop", visibility: "private"})
    assert Embeds.transform("![[ride:#{ride.id}]]") =~ "Home loop"
  end
end
