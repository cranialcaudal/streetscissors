defmodule Web.LiveTrackingTest do
  use Web.DataCase

  alias Web.Rides.LiveTracking
  alias Web.SiteSettings

  describe "valid_live_url?/1" do
    test "accepts https komoot hosts" do
      assert LiveTracking.valid_live_url?("https://www.komoot.com/live/abc123")
      assert LiveTracking.valid_live_url?("https://share.komoot.com/x?y=1")
      assert LiveTracking.valid_live_url?("https://komoot.com/live/x")
      assert LiveTracking.valid_live_url?("  https://www.komoot.com/live/x  ")
    end

    test "rejects everything else" do
      refute LiveTracking.valid_live_url?("http://www.komoot.com/live/x")
      refute LiveTracking.valid_live_url?("https://evil.com/komoot.com")
      refute LiveTracking.valid_live_url?("https://notkomoot.com/live")
      refute LiveTracking.valid_live_url?("https://evilkomoot.com/live")
      refute LiveTracking.valid_live_url?("")
      refute LiveTracking.valid_live_url?(nil)
      refute LiveTracking.valid_live_url?("komoot.com/live/x")
    end
  end

  describe "session lifecycle" do
    test "start_live then current returns the session, stop_live clears it" do
      assert LiveTracking.current() == nil

      {:ok, info} = LiveTracking.start_live("https://www.komoot.com/live/abc", "Fred Whitton")
      assert info.url == "https://www.komoot.com/live/abc"
      assert info.note == "Fred Whitton"
      assert %DateTime{} = info.started_at
      assert DateTime.compare(info.expires_at, info.started_at) == :gt

      assert %{url: "https://www.komoot.com/live/abc"} = LiveTracking.current()

      :ok = LiveTracking.stop_live()
      assert LiveTracking.current() == nil
    end

    test "start_live rejects an invalid url and stores nothing" do
      assert {:error, :invalid_url} = LiveTracking.start_live("http://www.komoot.com/x")
      assert LiveTracking.current() == nil
    end

    test "an expired session is hidden from current but visible in raw" do
      {:ok, _info} = LiveTracking.start_live("https://www.komoot.com/live/old")

      stale = DateTime.utc_now() |> DateTime.add(-15 * 3600, :second) |> DateTime.to_iso8601()
      {:ok, _} = SiteSettings.put_setting("live_ride_started_at", stale)

      assert LiveTracking.current() == nil
      assert %{url: "https://www.komoot.com/live/old"} = LiveTracking.raw()
    end

    test "a garbled started_at is treated as just-started, not a crash" do
      {:ok, _info} = LiveTracking.start_live("https://www.komoot.com/live/x")
      {:ok, _} = SiteSettings.put_setting("live_ride_started_at", "not-a-date")

      assert %{url: "https://www.komoot.com/live/x"} = LiveTracking.current()
    end
  end

  describe "ttl" do
    test "defaults to 14 hours" do
      assert LiveTracking.ttl_hours() == 14
    end

    test "put_ttl_hours round-trips and clamps to 1..48" do
      assert LiveTracking.put_ttl_hours("20") == 20
      assert LiveTracking.ttl_hours() == 20

      assert LiveTracking.put_ttl_hours(0) == 1
      assert LiveTracking.put_ttl_hours(100) == 48
      assert LiveTracking.put_ttl_hours("junk") == 14
    end
  end

  describe "pubsub" do
    test "broadcasts on start and stop" do
      :ok = LiveTracking.subscribe()

      {:ok, _info} = LiveTracking.start_live("https://www.komoot.com/live/abc")
      assert_receive {:live_ride, :started, %{url: "https://www.komoot.com/live/abc"}}

      :ok = LiveTracking.stop_live()
      assert_receive {:live_ride, :ended}
    end
  end
end
