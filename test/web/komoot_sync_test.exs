defmodule Web.Rides.KomootSyncTest do
  use Web.DataCase

  alias Web.Rides
  alias Web.Rides.{KomootSync, Thumbs}

  @login_body %{"username" => "u123", "password" => "tok"}

  @tour %{
    "id" => 444,
    "type" => "tour_recorded",
    "name" => "Evening loop",
    "sport" => "racebike",
    "date" => "2026-06-12T18:00:00.000Z",
    "distance" => 40_000.0,
    "duration" => 7200,
    "time_in_motion" => 6000,
    "elevation_up" => 800.0,
    "elevation_down" => 790.0,
    "kcal_active" => 1500,
    "status" => "public",
    "changed_at" => "2026-06-13T10:00:00.000Z",
    "map_image" => %{
      "src" => "https://cdn.komoot.de/maps/444.jpg?width={width}&height={height}&crop={crop}",
      "templated" => true
    }
  }

  @other_tour %{
    "id" => 111,
    "type" => "tour_recorded",
    "name" => "Morning run",
    "sport" => "jogging",
    "date" => "2026-06-10T14:00:00.000Z",
    "distance" => 5_000.0,
    "status" => "public"
  }

  # No start date — the one field a ride can't be stored without.
  @broken_tour %{"id" => 999, "type" => "tour_recorded", "name" => "Undated"}

  setup do
    File.rm_rf!(Thumbs.dir())
    # The token cache is a named process shared by the whole suite; a token
    # left behind by an earlier test would skip the login these tests stub.
    Web.Komoot.Auth.invalidate()
    :ok
  end

  # Serves the listing with an ETag and honours If-None-Match, the way the
  # real API does — its ETag is a plain md5 of the listing body. With a
  # `:log` agent, every request path is recorded.
  defp stub_komoot(opts \\ []) do
    tours = Keyword.get(opts, :tours, [@tour])
    log = Keyword.get(opts, :log)
    broken_images = Keyword.get(opts, :broken_images, false)

    Req.Test.stub(Web.Komoot.Client, fn conn ->
      if log, do: Agent.update(log, &[conn.request_path | &1])

      cond do
        String.starts_with?(conn.request_path, "/v006/account/email/") ->
          Req.Test.json(conn, @login_body)

        String.contains?(conn.request_path, "/maps/") ->
          if broken_images do
            Plug.Conn.send_resp(conn, 500, "no image")
          else
            conn
            |> Plug.Conn.put_resp_header("content-type", "image/jpeg")
            |> Plug.Conn.send_resp(200, "fake-jpeg-bytes")
          end

        conn.request_path =~ ~r{/v007/users/} ->
          etag = ~s("etag-#{:erlang.phash2(tours)}")

          if Plug.Conn.get_req_header(conn, "if-none-match") == [etag] do
            Plug.Conn.send_resp(conn, 304, "")
          else
            conn
            |> Plug.Conn.put_resp_header("etag", etag)
            |> Req.Test.json(%{"_embedded" => %{"tours" => tours}})
          end
      end
    end)
  end

  test "a recorded tour is imported from the listing alone" do
    {:ok, log} = Agent.start_link(fn -> [] end)
    stub_komoot(log: log)

    assert {:ok, %{imported: 1, failed: 0}} = KomootSync.sync()
    assert [ride] = Rides.list_rides()

    assert ride.komoot_id == "444"
    assert ride.name == "Evening loop"
    assert ride.sport == "racebike"
    assert ride.started_at == ~U[2026-06-12 18:00:00Z]
    assert ride.distance_m == 40_000.0
    assert ride.duration_s == 7200
    assert ride.time_in_motion_s == 6000
    assert_in_delta ride.avg_speed_mps, 40_000.0 / 6000, 0.001
    assert ride.ascent_m == 800.0
    assert ride.descent_m == 790.0
    assert ride.kcal == 1500
    assert ride.visibility == "public"
    assert ride.komoot_changed_at == ~U[2026-06-13 10:00:00Z]
    assert ride.map_image_url =~ "width=800"
    refute ride.map_image_url =~ "{crop}"
    assert Thumbs.exists?(ride)

    # Login, listing, map image — no per-tour request of any kind.
    assert Agent.get(log, &length/1) == 3
  end

  test "tour listing follows pagination links" do
    second = %{@other_tour | "id" => 333}

    Req.Test.stub(Web.Komoot.Client, fn conn ->
      cond do
        String.starts_with?(conn.request_path, "/v006/account/email/") ->
          Req.Test.json(conn, @login_body)

        conn.request_path =~ ~r{/v007/users/} ->
          case URI.decode_query(conn.query_string)["page"] do
            nil ->
              Req.Test.json(conn, %{
                "_embedded" => %{"tours" => [@other_tour]},
                "_links" => %{
                  "next" => %{
                    "href" =>
                      "https://api.komoot.de/v007/users/u123/tours/?type=tour_recorded&page=1"
                  }
                }
              })

            "1" ->
              Req.Test.json(conn, %{"_embedded" => %{"tours" => [second]}})
          end
      end
    end)

    assert {:ok, %{imported: 2}} = KomootSync.sync()
    assert ~w(111 333) == Rides.list_rides() |> Enum.map(& &1.komoot_id) |> Enum.sort()
  end

  test "rerunning the sync is idempotent" do
    stub_komoot(tours: [@tour, @other_tour])

    assert {:ok, %{imported: 2}} = KomootSync.sync()

    assert {:ok, %{imported: 0, updated: 0, deleted: 0, skipped: 2}} =
             KomootSync.sync(force: true)

    assert length(Rides.list_rides()) == 2
  end

  test "login failure surfaces as an error and imports nothing" do
    Req.Test.stub(Web.Komoot.Client, fn conn ->
      Plug.Conn.send_resp(conn, 401, "nope")
    end)

    assert {:error, :auth_failed} = KomootSync.sync()
    assert Rides.list_rides() == []
  end

  @tag :capture_log
  test "one broken tour does not abort the rest of the sync" do
    stub_komoot(tours: [@broken_tour, @other_tour])

    assert {:ok, %{imported: 1, failed: 1}} = KomootSync.sync()
    assert [%{komoot_id: "111"}] = Rides.list_rides()
  end

  test "tours that aren't public are archived like any other, marked private" do
    stub_komoot(tours: [%{@tour | "status" => "private"}, %{@other_tour | "status" => "friends"}])

    assert {:ok, %{imported: 2}} = KomootSync.sync()
    assert Enum.all?(Rides.list_rides(), &(&1.visibility == "private"))
  end

  # Komoot does not always bump changed_at when privacy is the only edit.
  test "a privacy flip on Komoot is mirrored without a changed_at bump" do
    stub_komoot(tours: [%{@tour | "status" => "private"}])
    assert {:ok, %{imported: 1}} = KomootSync.sync()

    stub_komoot(tours: [@tour])
    assert {:ok, %{updated: 1}} = KomootSync.sync()
    assert [%{visibility: "public"}] = Rides.list_rides()

    # And it settles: no churn once the two sides agree.
    assert {:ok, %{updated: 0, skipped: 1}} = KomootSync.sync(force: true)
  end

  test "an edit on Komoot is copied over via changed_at" do
    stub_komoot()
    assert {:ok, %{imported: 1}} = KomootSync.sync()

    edited =
      Map.merge(@tour, %{
        "name" => "Renamed loop",
        "distance" => 42_000.0,
        "changed_at" => "2026-06-14T10:00:00.000Z"
      })

    stub_komoot(tours: [edited])
    assert {:ok, %{imported: 0, updated: 1, failed: 0}} = KomootSync.sync()

    assert [ride] = Rides.list_rides()
    assert ride.name == "Renamed loop"
    assert ride.distance_m == 42_000.0
    assert ride.komoot_changed_at == ~U[2026-06-14 10:00:00Z]
  end

  test "a tour deleted on Komoot is deleted here, thumbnail and all" do
    stub_komoot(tours: [@tour, @other_tour])
    assert {:ok, %{imported: 2}} = KomootSync.sync()

    gone = Enum.find(Rides.list_rides(), &(&1.komoot_id == "444"))
    assert Thumbs.exists?(gone)

    stub_komoot(tours: [@other_tour])
    assert {:ok, %{deleted: 1}} = KomootSync.sync()

    assert [%{komoot_id: "111"}] = Rides.list_rides()
    refute Thumbs.exists?(gone)
  end

  test "an empty listing never wipes the archive" do
    stub_komoot()
    assert {:ok, %{imported: 1}} = KomootSync.sync()

    stub_komoot(tours: [])
    assert {:ok, %{deleted: 0}} = KomootSync.sync()
    assert [_ride] = Rides.list_rides()
  end

  @tag :capture_log
  test "thumbnail download failure does not fail the import" do
    stub_komoot(broken_images: true)

    assert {:ok, %{imported: 1, failed: 0}} = KomootSync.sync()
    assert [ride] = Rides.list_rides()
    refute Thumbs.exists?(ride)
  end

  test "sync is disabled without credentials" do
    original = Application.get_env(:web, :komoot)
    Application.put_env(:web, :komoot, email: nil, password: nil)
    on_exit(fn -> Application.put_env(:web, :komoot, original) end)

    refute KomootSync.enabled?()
    assert :disabled = KomootSync.sync()
  end

  @tag :capture_log
  test "run_scheduled never raises, even on transport errors" do
    Req.Test.stub(Web.Komoot.Client, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    assert :ok = KomootSync.run_scheduled()
  end

  # The hourly schedule is there to catch a ride quickly, not because the
  # archive usually changes — so the price of a pass where nothing changed is
  # the number that matters. These pin it down.
  describe "cost of a pass" do
    setup do
      {:ok, log} = Agent.start_link(fn -> [] end)
      %{log: log}
    end

    defp requests(log), do: log |> Agent.get(& &1) |> Enum.reverse()

    defp listings(log), do: Enum.filter(requests(log), &String.contains?(&1, "/v007/users/"))

    defp logins(log), do: Enum.filter(requests(log), &String.starts_with?(&1, "/v006/account/"))

    defp images(log), do: Enum.count(requests(log), &String.contains?(&1, "/maps/"))

    test "an unchanged archive is answered 304 and read no further", %{log: log} do
      stub_komoot(log: log)
      assert {:ok, %{imported: 1, unchanged: false}} = KomootSync.sync()

      assert {:ok, %{imported: 0, updated: 0, skipped: 0, unchanged: true}} = KomootSync.sync()
      assert {:ok, %{unchanged: true}} = KomootSync.sync()

      # Three passes, one login, and nothing beyond the conditional GET itself.
      assert length(logins(log)) == 1
      assert length(listings(log)) == 3
    end

    test "a changed listing gets a new ETag and is processed", %{log: log} do
      stub_komoot(log: log)
      assert {:ok, %{imported: 1}} = KomootSync.sync()
      assert {:ok, %{unchanged: true}} = KomootSync.sync()

      renamed =
        Map.merge(@tour, %{"name" => "Renamed", "changed_at" => "2026-06-14T10:00:00.000Z"})

      stub_komoot(log: log, tours: [renamed])
      assert {:ok, %{updated: 1, unchanged: false}} = KomootSync.sync()

      # And it settles again on the new ETag.
      assert {:ok, %{unchanged: true}} = KomootSync.sync()
    end

    @tag :capture_log
    test "a failed import does not store the ETag, so the next pass retries", %{log: log} do
      stub_komoot(log: log, tours: [@broken_tour])

      assert {:ok, %{failed: 1}} = KomootSync.sync()
      assert {:ok, %{failed: 1, unchanged: false}} = KomootSync.sync()
    end

    test "force: true re-reads the listing despite a stored ETag", %{log: log} do
      stub_komoot(log: log)
      assert {:ok, %{imported: 1}} = KomootSync.sync()
      assert {:ok, %{unchanged: true}} = KomootSync.sync()

      assert {:ok, %{unchanged: false, skipped: 1}} = KomootSync.sync(force: true)
    end

    test "the API token is reused instead of re-minted every pass", %{log: log} do
      stub_komoot(log: log)

      for _ <- 1..5, do: KomootSync.sync()

      assert length(logins(log)) == 1
    end

    test "a token the API stops accepting is replaced, not given up on", %{log: log} do
      stub_komoot(log: log)
      assert {:ok, %{imported: 1}} = KomootSync.sync()

      # Same credentials, but the cached token is now rejected once.
      rejected = :counters.new(1, [])

      Req.Test.stub(Web.Komoot.Client, fn conn ->
        Agent.update(log, &[conn.request_path | &1])

        cond do
          String.starts_with?(conn.request_path, "/v006/account/email/") ->
            Req.Test.json(conn, %{@login_body | "password" => "fresh-tok"})

          :counters.get(rejected, 1) == 0 ->
            :counters.add(rejected, 1, 1)
            Plug.Conn.send_resp(conn, 401, "stale token")

          true ->
            Req.Test.json(conn, %{"_embedded" => %{"tours" => [@tour]}})
        end
      end)

      assert {:ok, %{imported: 0, skipped: 1}} = KomootSync.sync()
      assert length(logins(log)) == 2
    end

    test "a metadata edit does not re-download an unchanged map image", %{log: log} do
      stub_komoot(log: log)
      assert {:ok, %{imported: 1}} = KomootSync.sync()
      assert images(log) == 1

      renamed =
        Map.merge(@tour, %{"name" => "Renamed", "changed_at" => "2026-06-14T10:00:00.000Z"})

      stub_komoot(log: log, tours: [renamed])
      assert {:ok, %{updated: 1}} = KomootSync.sync()
      assert images(log) == 1

      # A re-routed tour, though, gets a genuinely different image URL.
      rerouted =
        Map.merge(renamed, %{
          "changed_at" => "2026-06-15T10:00:00.000Z",
          "map_image" => %{
            "src" => "https://cdn.komoot.de/maps/444-v2.jpg?width={width}&height={height}"
          }
        })

      stub_komoot(log: log, tours: [rerouted])
      assert {:ok, %{updated: 1}} = KomootSync.sync()
      assert images(log) == 2
    end
  end
end
