defmodule Web.Rides.KomootSyncTest do
  use Web.DataCase

  alias Web.Rides
  alias Web.Rides.{KomootSync, Thumbs}

  @login_body %{"username" => "u123", "password" => "tok"}

  # The owner's listing carries the owner's map: the route whole. The site
  # must never fetch it, so it is given a name a test can look for.
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
      "src" => "https://cdn.komoot.de/maps/444-OWNER.jpg?width={width}&height={height}",
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

  # Invented ground: a "home" to hide, a route a stranger is shown that stays
  # well clear of it, and one that runs past the door.
  @home {10.0, 20.0}
  @clear [%{"lat" => 10.01, "lng" => 20.01}, %{"lat" => 10.02, "lng" => 20.02}]
  @past_the_door [%{"lat" => 10.0003, "lng" => 20.0}, %{"lat" => 10.02, "lng" => 20.02}]

  setup do
    File.rm_rf!(Thumbs.dir())
    # The token cache is a named process shared by the whole suite; a token
    # left behind by an earlier test would skip the login these tests stub.
    Web.Komoot.Auth.invalidate()
    on_exit(fn -> Application.delete_env(:web, :ride_privacy_zones) end)
    :ok
  end

  defp hide_home do
    {lat, lng} = @home
    Application.put_env(:web, :ride_privacy_zones, "#{lat},#{lng}")
  end

  # Stands in for Komoot.
  #
  # The listing is the owner's: it needs the login, carries an ETag and
  # honours If-None-Match (the real ETag is a plain md5 of the body).
  #
  # `GET /v007/tours/<id>` is a stranger's read: no login is sent, and a tour
  # that isn't public answers 403 `AccessDenied` without its share token. It
  # returns the route as a stranger is shown it (`points:`, per tour id) and
  # the map drawn from that (`public_map:`, per tour id). A tour in `hidden:`
  # lies inside a privacy zone, and answers 403 `AccessDeniedPrivacyZone`
  # whatever token comes with it — both refusals worded as Komoot words them.
  #
  # Share tokens answer the way Komoot's do: the read is a 204 until one is
  # created, and the create is a 201 carrying it. A tour in `tokens:` already
  # has the link given there, and that is the only one its read accepts.
  #
  # With a `:log` agent, every request is recorded as `{path, logged_in?}`.
  defp stub_komoot(opts \\ []) do
    tours = Keyword.get(opts, :tours, [@tour])
    log = Keyword.get(opts, :log)
    points = Keyword.get(opts, :points, %{})
    public_map = Keyword.get(opts, :public_map, %{})
    hidden = Keyword.get(opts, :hidden, [])
    tokens = Keyword.get(opts, :tokens, %{})
    broken = Keyword.get(opts, :broken, [])

    Req.Test.stub(Web.Komoot.Client, fn conn ->
      logged_in? = Plug.Conn.get_req_header(conn, "authorization") != []
      if log, do: Agent.update(log, &[{conn.request_path, logged_in?} | &1])

      cond do
        String.starts_with?(conn.request_path, "/v006/account/email/") ->
          Req.Test.json(conn, @login_body)

        String.ends_with?(conn.request_path, "/share_token") ->
          [_, tour_id] = Regex.run(~r{/tours/(\d+)/}, conn.request_path)

          cond do
            :share_tokens in broken ->
              Plug.Conn.send_resp(conn, 500, "")

            conn.method == "GET" and is_map_key(tokens, String.to_integer(tour_id)) ->
              Req.Test.json(conn, %{"token" => tokens[String.to_integer(tour_id)]})

            conn.method == "GET" ->
              Plug.Conn.send_resp(conn, 204, "")

            true ->
              conn
              |> Plug.Conn.put_status(201)
              |> Req.Test.json(%{"token" => "share-" <> tour_id})
          end

        String.contains?(conn.request_path, "/maps/") ->
          if :images in broken do
            Plug.Conn.send_resp(conn, 500, "no image")
          else
            conn
            |> Plug.Conn.put_resp_header("content-type", "image/jpeg")
            |> Plug.Conn.send_resp(200, "jpeg of " <> conn.request_path)
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

        match = Regex.run(~r{^/v007/tours/(\d+)$}, conn.request_path) ->
          [_, tour_id] = match
          id = String.to_integer(tour_id)
          tour = Enum.find(tours, &(&1["id"] == id))
          token = URI.decode_query(conn.query_string)["share_token"]

          cond do
            :strangers_read in broken ->
              Plug.Conn.send_resp(conn, 500, "")

            is_nil(tour) ->
              Plug.Conn.send_resp(conn, 404, "")

            id in hidden ->
              conn
              |> Plug.Conn.put_status(403)
              |> Req.Test.json(%{
                "error" => "AccessDeniedPrivacyZone",
                "message" => "User is not allowed to access tour",
                "status" => 403
              })

            tour["status"] != "public" and token != Map.get(tokens, id, "share-" <> tour_id) ->
              conn
              |> Plug.Conn.put_status(403)
              |> Req.Test.json(%{
                "error" => "AccessDenied",
                "message" => "Access denied without authentication.",
                "status" => 403
              })

            true ->
              Req.Test.json(conn, %{
                "id" => id,
                "map_image" => %{
                  "src" =>
                    Map.get(
                      public_map,
                      id,
                      "https://cdn.komoot.de/maps/#{id}-PUBLIC.jpg?width={width}&height={height}&crop={crop}"
                    )
                },
                "_embedded" => %{"coordinates" => %{"items" => Map.get(points, id, @clear)}}
              })
          end
      end
    end)
  end

  defp requests(log), do: log |> Agent.get(& &1) |> Enum.reverse()
  defp paths(log), do: Enum.map(requests(log), &elem(&1, 0))
  defp listings(log), do: Enum.filter(paths(log), &String.contains?(&1, "/v007/users/"))
  defp logins(log), do: Enum.filter(paths(log), &String.starts_with?(&1, "/v006/account/"))
  defp images(log), do: Enum.filter(paths(log), &String.contains?(&1, "/maps/"))
  defp strangers_reads(log), do: Enum.filter(paths(log), &(&1 =~ ~r{^/v007/tours/\d+$}))

  test "a recorded tour is imported from the listing, and its picture from a stranger's view" do
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
    assert ride.stranger_view == "clear"

    assert ride.map_image_url =~ "444-PUBLIC.jpg?width=800&height=450"
    refute ride.map_image_url =~ "{crop}"
    assert Thumbs.exists?(ride)

    # Login, listing, the stranger's read, the stranger's map. Nothing else.
    assert length(requests(log)) == 4
  end

  # The owner's login sees the route whole, front door included. Nothing a
  # visitor is shown may come from a request that carried it.
  test "the route's picture is never fetched with the owner's login, nor from the owner's URL" do
    {:ok, log} = Agent.start_link(fn -> [] end)
    stub_komoot(log: log, tours: [%{@tour | "status" => "private"}])

    assert {:ok, %{imported: 1}} = KomootSync.sync()

    assert {"/v007/tours/444", false} in requests(log)
    assert Enum.all?(images(log), &(&1 =~ "PUBLIC"))
    refute Enum.any?(paths(log), &(&1 =~ "OWNER"))

    assert [ride] = Rides.list_rides()
    assert File.read!(Thumbs.path(ride)) =~ "444-PUBLIC"
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

        conn.request_path =~ ~r{^/v007/tours/\d+$} ->
          Req.Test.json(conn, %{"_embedded" => %{"coordinates" => %{"items" => @clear}}})
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

  describe "share tokens" do
    test "a private tour gets one once, so Komoot's embed can show it" do
      {:ok, log} = Agent.start_link(fn -> [] end)
      stub_komoot(log: log, tours: [%{@tour | "status" => "private"}, @other_tour])

      assert {:ok, %{imported: 2, failed: 0}} = KomootSync.sync()

      assert %{"444" => private, "111" => public} = Rides.komoot_index()
      assert private.share_token == "share-444"
      assert public.share_token == nil

      # A read that finds none, then the create — and only for the private tour.
      assert share_token_requests(log) == [
               "/v007/tours/444/share_token",
               "/v007/tours/444/share_token"
             ]

      # Kept from then on: a full re-read doesn't ask again.
      assert {:ok, %{skipped: 2}} = KomootSync.sync(force: true)
      assert length(share_token_requests(log)) == 2
    end

    @tag :capture_log
    test "a failed one fails the tour until a pass gets it" do
      stub_komoot(tours: [%{@tour | "status" => "private"}], broken: [:share_tokens])

      assert {:ok, %{failed: 1}} = KomootSync.sync()
      assert [%{share_token: nil}] = Rides.list_rides()

      # The ETag wasn't stored, so the next hourly pass reads the listing again
      # and asks again — no force needed.
      stub_komoot(tours: [%{@tour | "status" => "private"}])
      assert {:ok, %{updated: 1, failed: 0, unchanged: false}} = KomootSync.sync()
      assert [%{share_token: "share-444"} = ride] = Rides.list_rides()
      assert Thumbs.exists?(ride)
    end

    test "a tour made private later gets its token on that pass" do
      stub_komoot()
      assert {:ok, %{imported: 1}} = KomootSync.sync()
      assert [%{share_token: nil}] = Rides.list_rides()

      stub_komoot(tours: [%{@tour | "status" => "private"}])
      assert {:ok, %{updated: 1}} = KomootSync.sync()
      assert [%{visibility: "private", share_token: "share-444"}] = Rides.list_rides()
    end

    # Sharing switched off and on again in the app makes a new link, and the
    # one on file stops opening anything. Left alone that tour would fail
    # every pass for good, so a refusal with a token on file is answered by
    # asking Komoot for the token once more.
    test "a link that stopped working is asked for again, once" do
      {:ok, log} = Agent.start_link(fn -> [] end)
      stub_komoot(log: log, tours: [%{@tour | "status" => "private"}])
      assert {:ok, %{imported: 1}} = KomootSync.sync()
      assert [%{share_token: "share-444", stranger_view: "clear"}] = Rides.list_rides()

      stub_komoot(
        log: log,
        tours: [%{@tour | "status" => "private"}],
        tokens: %{444 => "a-new-link"}
      )

      assert {:ok, %{updated: 1, failed: 0}} = KomootSync.sync(force: true)

      assert [%{share_token: "a-new-link", stranger_view: "clear"} = ride] = Rides.list_rides()
      assert Rides.embed_url(ride) =~ "share_token=a-new-link"
      # The refused read, the token asked for again, the read that worked.
      assert Enum.take(paths(log), -3) == [
               "/v007/tours/444",
               "/v007/tours/444/share_token",
               "/v007/tours/444"
             ]
    end

    # Komoot says the link on file is the link, and still refuses it. Asking
    # a third time would change nothing: the tour fails, and is tried again
    # next pass.
    @tag :capture_log
    test "a refusal the same token cannot explain fails the tour without a loop" do
      {:ok, log} = Agent.start_link(fn -> [] end)
      private = %{@tour | "status" => "private"}
      stub_komoot(log: log, tours: [private])
      assert {:ok, %{imported: 1}} = KomootSync.sync()
      before = length(paths(log))

      # The read now wants a link Komoot does not hand out.
      Req.Test.stub(Web.Komoot.Client, fn conn ->
        Agent.update(log, &[{conn.request_path, false} | &1])

        cond do
          String.starts_with?(conn.request_path, "/v006/account/email/") ->
            Req.Test.json(conn, @login_body)

          String.ends_with?(conn.request_path, "/share_token") ->
            Req.Test.json(conn, %{"token" => "share-444"})

          conn.request_path =~ ~r{/v007/users/} ->
            Req.Test.json(conn, %{"_embedded" => %{"tours" => [private]}})

          true ->
            conn
            |> Plug.Conn.put_status(403)
            |> Req.Test.json(%{"error" => "AccessDenied", "status" => 403})
        end
      end)

      assert {:ok, %{failed: 1}} = KomootSync.sync(force: true)
      assert [%{share_token: "share-444"}] = Rides.list_rides()

      # The listing, one refused read, one token asked for again. No second read.
      assert paths(log) |> Enum.drop(before) |> Enum.reject(&(&1 =~ "/account/")) == [
               "/v007/users/u123/tours/",
               "/v007/tours/444",
               "/v007/tours/444/share_token"
             ]
    end

    defp share_token_requests(log),
      do: Enum.filter(paths(log), &String.ends_with?(&1, "/share_token"))
  end

  # Komoot's privacy zone is the protection, and it lives on Komoot's side.
  # The site only checks: does a stranger's view of the tour come near a place
  # it was told is private?
  describe "the tripwire" do
    setup do
      hide_home()
      :ok
    end

    test "a tour whose stranger's view stays clear is shown as Komoot draws it" do
      stub_komoot(points: %{444 => @clear})

      assert {:ok, %{imported: 1}} = KomootSync.sync()
      assert [%{stranger_view: "clear"} = ride] = Rides.list_rides()
      assert Rides.embed_url(ride)
      assert Rides.thumb?(ride)
      assert Rides.exposed() == []
    end

    @tag :capture_log
    test "a tour a stranger can follow to the door is exposed: no embed, no picture, no link" do
      {:ok, log} = Agent.start_link(fn -> [] end)
      stub_komoot(log: log, points: %{444 => @past_the_door})

      assert {:ok, %{imported: 1, failed: 0}} = KomootSync.sync()
      assert [%{stranger_view: "exposed"} = ride] = Rides.list_rides()

      assert Rides.embed_url(ride) == nil
      assert Rides.tour_url(ride) == nil
      refute Rides.thumb?(ride)
      # Its picture was never even downloaded.
      assert images(log) == []
      assert [%{komoot_id: "444"}] = Rides.exposed()
    end

    @tag :capture_log
    test "an exposed tour is looked at again on every pass that reads, and cleared when clean" do
      stub_komoot(points: %{444 => @past_the_door})
      assert {:ok, %{imported: 1}} = KomootSync.sync()
      assert [%{stranger_view: "exposed"}] = Rides.list_rides()

      # The zone is put right on Komoot. Nothing about the tour itself moved,
      # so only a pass that reads the listing can notice: Sync now.
      stub_komoot(points: %{444 => @clear})
      assert {:ok, %{updated: 1}} = KomootSync.sync(force: true)

      assert [%{stranger_view: "clear"} = ride] = Rides.list_rides()
      assert Rides.embed_url(ride)
      assert Rides.thumb?(ride)
    end

    # A zone trims where a tour starts and ends, and nothing else. A ride
    # that came home, stopped and went out again is handed to a stranger with
    # its ends cut and its middle whole. This is what the wire is for.
    @tag :capture_log
    test "a pass back through the zone mid-tour trips it, though both ends are cut" do
      came_home = [
        %{"lat" => 10.01, "lng" => 20.01},
        %{"lat" => 10.0002, "lng" => 20.0},
        %{"lat" => 10.0, "lng" => 20.0},
        %{"lat" => 10.02, "lng" => 20.02}
      ]

      stub_komoot(points: %{444 => came_home})

      assert {:ok, %{imported: 1, failed: 0}} = KomootSync.sync()
      assert [%{stranger_view: "exposed"} = ride] = Rides.list_rides()
      assert Rides.embed_url(ride) == nil
    end

    # An exposed tour is a settled answer, not a failure: the listing's ETag
    # is kept, and a quiet hour goes back to costing one 304.
    @tag :capture_log
    test "an exposed tour does not keep the hourly pass from settling" do
      {:ok, log} = Agent.start_link(fn -> [] end)
      stub_komoot(log: log, points: %{444 => @past_the_door})

      assert {:ok, %{imported: 1, failed: 0}} = KomootSync.sync()
      assert {:ok, %{unchanged: true}} = KomootSync.sync()
      assert length(strangers_reads(log)) == 1
    end

    @tag :capture_log
    test "a tour that was clean and no longer is loses its picture at once" do
      stub_komoot()
      assert {:ok, %{imported: 1}} = KomootSync.sync()
      assert [%{stranger_view: "clear"} = ride] = Rides.list_rides()
      assert Thumbs.exists?(ride)

      # The zone was deleted on Komoot, which touches every tour.
      touched = %{@tour | "changed_at" => "2026-06-20T10:00:00.000Z"}
      stub_komoot(tours: [touched], points: %{444 => @past_the_door})
      assert {:ok, %{updated: 1}} = KomootSync.sync()

      assert [%{stranger_view: "exposed"} = ride] = Rides.list_rides()
      refute Thumbs.exists?(ride)
      assert File.ls!(Thumbs.dir()) == []
    end

    test "Sync now looks at every tour again, changed or not" do
      {:ok, log} = Agent.start_link(fn -> [] end)
      stub_komoot(log: log, tours: [@tour, @other_tour])

      assert {:ok, %{imported: 2}} = KomootSync.sync()
      assert length(strangers_reads(log)) == 2

      assert {:ok, %{skipped: 2}} = KomootSync.sync(force: true)
      assert length(strangers_reads(log)) == 4
      # Looked at, found the same, and so nothing downloaded twice.
      assert length(images(log)) == 2
    end

    @tag :capture_log
    test "a setting that cannot be read exposes everything rather than checking nothing" do
      Application.put_env(:web, :ride_privacy_zones, "somewhere near the river")
      stub_komoot()

      assert {:ok, %{imported: 1}} = KomootSync.sync()
      assert [%{stranger_view: "exposed"}] = Rides.list_rides()
    end

    test "with no private places on file nothing is checked, and nothing is exposed" do
      Application.delete_env(:web, :ride_privacy_zones)
      stub_komoot(points: %{444 => @past_the_door})

      assert {:ok, %{imported: 1}} = KomootSync.sync()
      assert [%{stranger_view: "clear"}] = Rides.list_rides()
    end
  end

  # A tour that never leaves the privacy zone: a walk round the block, a
  # recording left running at the door. Komoot does not hand a stranger a cut
  # route for one of these. It refuses the whole tour, share token or not, and
  # says why. That is an answer, and a good one: the site shows the figures.
  describe "a tour inside Komoot's privacy zone" do
    @private_tour %{@tour | "status" => "private"}

    test "is hidden, not failed: no embed, no picture, no link" do
      {:ok, log} = Agent.start_link(fn -> [] end)
      stub_komoot(log: log, tours: [@private_tour], hidden: [444])

      assert {:ok, %{imported: 1, failed: 0}} = KomootSync.sync()
      assert [%{stranger_view: "hidden", map_image_url: nil} = ride] = Rides.list_rides()

      refute Rides.clear?(ride)
      assert Rides.embed_url(ride) == nil
      assert Rides.tour_url(ride) == nil
      refute Rides.thumb?(ride)
      assert images(log) == []
      # Hidden is Komoot keeping a place private. It is not the tripwire.
      assert Rides.exposed() == []
    end

    # The failure this replaced: a refusal counted as an error kept the ETag
    # from ever being stored, so every hour re-read the whole listing and
    # reported a sync that had half failed.
    test "the pass settles, and the next quiet hour is a 304 again" do
      {:ok, log} = Agent.start_link(fn -> [] end)
      stub_komoot(log: log, tours: [@private_tour, @other_tour], hidden: [444])

      assert {:ok, %{imported: 2, failed: 0}} = KomootSync.sync()
      assert %{status: :ok} = KomootSync.last_run()

      assert {:ok, %{unchanged: true}} = KomootSync.sync()
      assert length(listings(log)) == 2
      assert length(strangers_reads(log)) == 2
    end

    test "a public tour can be hidden too" do
      stub_komoot(hidden: [444])

      assert {:ok, %{imported: 1, failed: 0}} = KomootSync.sync()
      assert [%{visibility: "public", stranger_view: "hidden"} = ride] = Rides.list_rides()
      assert Rides.embed_url(ride) == nil
    end

    test "a tour that was shown and is now inside a zone loses its picture at once" do
      stub_komoot()
      assert {:ok, %{imported: 1}} = KomootSync.sync()
      assert [%{stranger_view: "clear"} = ride] = Rides.list_rides()
      assert Thumbs.exists?(ride)

      # The zone was widened on Komoot.
      touched = %{@tour | "changed_at" => "2026-06-20T10:00:00.000Z"}
      stub_komoot(tours: [touched], hidden: [444])
      assert {:ok, %{updated: 1, failed: 0}} = KomootSync.sync()

      assert [%{stranger_view: "hidden", map_image_url: nil}] = Rides.list_rides()
      assert File.ls!(Thumbs.dir()) == []
    end

    test "is looked at again on a pass that reads, and shown once Komoot shows it" do
      stub_komoot(tours: [@private_tour], hidden: [444])
      assert {:ok, %{imported: 1}} = KomootSync.sync()

      # Still hidden: looked at, found the same, nothing to report.
      assert {:ok, %{skipped: 1, updated: 0}} = KomootSync.sync(force: true)

      # The zone was moved off it.
      stub_komoot(tours: [@private_tour])
      assert {:ok, %{updated: 1}} = KomootSync.sync(force: true)

      assert [%{stranger_view: "clear", share_token: "share-444"} = ride] = Rides.list_rides()
      assert Rides.embed_url(ride) =~ "share_token=share-444"
      assert Rides.thumb?(ride)
    end
  end

  # Only a tour that has been read as a stranger, and found clear, is shown
  # through Komoot. Until then it is its figures.
  @tag :capture_log
  test "a tour not yet read as a stranger is not embedded, public or not" do
    stub_komoot(broken: [:strangers_read])
    assert {:ok, %{failed: 1}} = KomootSync.sync()

    assert [%{visibility: "public", stranger_view: nil} = ride] = Rides.list_rides()
    assert Rides.embed_url(ride) == nil
    assert Rides.tour_url(ride) == nil
  end

  @tag :capture_log
  test "a stranger's read that fails fails the tour, and the next pass tries again" do
    stub_komoot(broken: [:strangers_read])
    assert {:ok, %{failed: 1}} = KomootSync.sync()
    assert [%{map_image_url: nil, stranger_view: nil} = ride] = Rides.list_rides()
    assert Rides.thumb?(ride) == false

    stub_komoot()
    assert {:ok, %{updated: 1, failed: 0, unchanged: false}} = KomootSync.sync()
    assert [ride] = Rides.list_rides()
    assert Thumbs.exists?(ride)
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

  # changed_at is recorded last, so a pass that could not finish looking at an
  # edited tour leaves it looking edited.
  @tag :capture_log
  test "an edit whose stranger's read fails is tried again, not half-recorded" do
    stub_komoot()
    assert {:ok, %{imported: 1}} = KomootSync.sync()

    edited = %{@tour | "changed_at" => "2026-06-14T10:00:00.000Z"}
    stub_komoot(tours: [edited], broken: [:strangers_read])
    assert {:ok, %{failed: 1}} = KomootSync.sync()
    assert [%{komoot_changed_at: ~U[2026-06-13 10:00:00Z]}] = Rides.list_rides()

    stub_komoot(tours: [edited])
    assert {:ok, %{updated: 1, failed: 0}} = KomootSync.sync()
    assert [%{komoot_changed_at: ~U[2026-06-14 10:00:00Z]}] = Rides.list_rides()
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

  # An earlier version of the site cached the owner's map of each tour under
  # the bare ride id. Those show the route whole and must not outlive it.
  test "a pass sweeps out pictures no ride now answers for" do
    File.mkdir_p!(Thumbs.dir())
    File.write!(Path.join(Thumbs.dir(), "1.jpg"), "a whole route, front door and all")
    File.write!(Path.join(Thumbs.dir(), "7777-0123456789ab.jpg"), "a ride long deleted")

    stub_komoot()
    assert {:ok, %{imported: 1}} = KomootSync.sync()

    assert [ride] = Rides.list_rides()
    assert File.ls!(Thumbs.dir()) == [Path.basename(Thumbs.path(ride))]
  end

  test "an empty listing never wipes the archive" do
    stub_komoot()
    assert {:ok, %{imported: 1}} = KomootSync.sync()

    stub_komoot(tours: [])
    assert {:ok, %{deleted: 0}} = KomootSync.sync()
    assert [_ride] = Rides.list_rides()
  end

  @tag :capture_log
  test "thumbnail download failure does not fail the import, and is retried" do
    stub_komoot(broken: [:images])

    assert {:ok, %{imported: 1, failed: 0}} = KomootSync.sync()
    assert [ride] = Rides.list_rides()
    refute Thumbs.exists?(ride)

    stub_komoot()
    assert {:ok, %{failed: 0}} = KomootSync.sync(force: true)
    assert Thumbs.exists?(ride)
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

  test "every pass leaves a record of how it went" do
    stub_komoot()
    assert {:ok, _} = KomootSync.sync()
    assert %{status: :ok, detail: "1 imported", at: %DateTime{}} = KomootSync.last_run()

    assert {:ok, _} = KomootSync.sync()
    assert %{status: :ok, detail: "unchanged since the last pass"} = KomootSync.last_run()
  end

  # The hourly schedule is there to catch a ride quickly, not because the
  # archive usually changes — so the price of a pass where nothing changed is
  # the number that matters. These pin it down.
  describe "cost of a pass" do
    setup do
      {:ok, log} = Agent.start_link(fn -> [] end)
      %{log: log}
    end

    test "an unchanged archive is answered 304 and read no further", %{log: log} do
      stub_komoot(log: log)
      assert {:ok, %{imported: 1, unchanged: false}} = KomootSync.sync()

      assert {:ok, %{imported: 0, updated: 0, skipped: 0, unchanged: true}} = KomootSync.sync()
      assert {:ok, %{unchanged: true}} = KomootSync.sync()

      # Three passes, one login, one look at the tour, and after that nothing
      # beyond the conditional GET itself.
      assert length(logins(log)) == 1
      assert length(listings(log)) == 3
      assert length(strangers_reads(log)) == 1
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
        Agent.update(log, &[{conn.request_path, true} | &1])

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
      assert length(images(log)) == 1

      renamed =
        Map.merge(@tour, %{"name" => "Renamed", "changed_at" => "2026-06-14T10:00:00.000Z"})

      stub_komoot(log: log, tours: [renamed])
      assert {:ok, %{updated: 1}} = KomootSync.sync()
      assert length(images(log)) == 1

      # A re-cut route, though — a zone moved, a tour re-routed — is a
      # genuinely different picture, and the old one does not linger.
      recut = %{renamed | "changed_at" => "2026-06-15T10:00:00.000Z"}

      stub_komoot(
        log: log,
        tours: [recut],
        public_map: %{444 => "https://cdn.komoot.de/maps/444-RECUT.jpg?width={width}"}
      )

      assert {:ok, %{updated: 1}} = KomootSync.sync()
      assert length(images(log)) == 2

      assert [ride] = Rides.list_rides()
      assert File.ls!(Thumbs.dir()) == [Path.basename(Thumbs.path(ride))]
      assert File.read!(Thumbs.path(ride)) =~ "444-RECUT"
    end
  end
end
