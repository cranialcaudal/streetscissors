defmodule Web.Blog.RideEmbedsTest do
  use Web.DataCase

  alias Web.Blog.Embeds
  alias Web.Rides
  alias Web.Rides.Thumbs

  setup do
    File.rm_rf!(Thumbs.dir())
    :ok
  end

  defp make_ride(attrs \\ %{}) do
    points = [
      %{lat: 54.54, lon: -3.15, altitude_m: 100.0, recorded_at: ~U[2026-07-08 08:00:00Z]},
      %{lat: 54.55, lon: -3.15, altitude_m: 110.0, recorded_at: ~U[2026-07-08 08:01:00Z]}
    ]

    {:ok, ride} =
      Rides.create_imported_ride(points, Map.merge(%{"name" => "Evening Loop"}, attrs))

    ride
  end

  test "expands a ride embed into a card" do
    ride = make_ride()
    html = Embeds.transform("<p>![[ride:#{ride.id}]]</p>")
    assert html =~ ~s(<figure class="blog-embed blog-embed-ride">)
    assert html =~ ~s(href="/fitness/rides/#{ride.id}")
    assert html =~ "Evening Loop"
    refute html =~ "<img"
  end

  test "escapes ride names" do
    ride = make_ride(%{"name" => "<script>alert(1)</script>"})
    html = Embeds.transform("![[ride:#{ride.id}]]")
    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end

  test "includes the thumbnail when cached" do
    ride = make_ride()
    :ok = Thumbs.store(ride, "fake-jpeg")
    html = Embeds.transform("![[ride:#{ride.id}]]")
    assert html =~ ~s(src="/fitness/rides/#{ride.id}/thumb")
  end

  test "renders captions" do
    ride = make_ride()
    html = Embeds.transform("![[ride:#{ride.id}|Big day out]]")
    assert html =~ "<figcaption>Big day out</figcaption>"
  end

  test "unknown and private rides stay literal text" do
    assert Embeds.transform("![[ride:999999]]") == "![[ride:999999]]"

    ride = make_ride()
    {:ok, _ride} = Rides.update_ride(ride, %{"visibility" => "private"})
    assert Embeds.transform("![[ride:#{ride.id}]]") == "![[ride:#{ride.id}]]"
  end
end
