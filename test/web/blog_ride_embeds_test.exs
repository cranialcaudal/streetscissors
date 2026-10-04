defmodule Web.Blog.RideEmbedsTest do
  use Web.DataCase

  import Web.RidesFixtures

  alias Web.Blog.Embeds

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

  test "includes the route's outline once the ride has a track" do
    ride = ride_fixture()
    {:ok, ride} = Web.Rides.store_track(ride, [{45.0, 7.0, 300.0, 0}, {45.001, 7.001, 305.0, 9}])
    html = Embeds.transform("![[ride:#{ride.id}]]")
    assert html =~ ~s(<svg class="blog-embed-ride-route")
    assert html =~ ~s(<path d="#{ride.route_path}")
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
