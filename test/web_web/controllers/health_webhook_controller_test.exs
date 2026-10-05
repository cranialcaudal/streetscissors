defmodule WebWeb.HealthWebhookControllerTest do
  use WebWeb.ConnCase

  import Web.RidesFixtures

  alias Web.Rides
  alias Web.Rides.AppleHealth

  # Health Auto Export's payload for one workout. Invented values.
  @workout %{
    "id" => "7F3A-EXAMPLE",
    "name" => "Outdoor Cycling",
    "start" => "2026-07-08 11:00:10 -0700",
    "end" => "2026-07-08 13:00:00 -0700",
    "heartRate" => %{
      "min" => %{"qty" => 92},
      "avg" => %{"qty" => 141.6},
      "max" => %{"qty" => 170}
    },
    "activeEnergyBurned" => %{"qty" => 600, "units" => "kcal"},
    "heartRateData" => [
      %{"date" => "2026-07-08 11:00:10 -0700", "Avg" => 95},
      %{"date" => "2026-07-08 11:01:10 -0700", "Avg" => 120}
    ],
    "route" => [%{"latitude" => 1.0, "longitude" => 2.0}]
  }

  setup do
    Web.RateLimit.reset_all()
    :ok
  end

  defp with_token(conn, token), do: put_req_header(conn, "authorization", "Bearer " <> token)

  defp post_workouts(conn, workouts),
    do: post(conn, ~p"/api/health/ingest", %{"data" => %{"workouts" => workouts}})

  describe "closed" do
    # The state the site ships in: nobody has asked for the webhook, so there
    # is no token, and so nothing can be the right one.
    test "with no token made, every request is refused", %{conn: conn} do
      refute AppleHealth.webhook_open?()

      assert conn |> post_workouts([@workout]) |> json_response(401)
      assert conn |> with_token("") |> post_workouts([@workout]) |> json_response(401)
      assert conn |> with_token("anything") |> post_workouts([@workout]) |> json_response(401)
      assert Rides.count_workouts() == 0
    end

    test "a wrong token is refused, and so is one that was revoked", %{conn: conn} do
      token = AppleHealth.create_webhook_token()

      assert conn |> with_token(token <> "x") |> post_workouts([@workout]) |> json_response(401)

      AppleHealth.revoke_webhook_token()
      assert conn |> with_token(token) |> post_workouts([@workout]) |> json_response(401)
      assert Rides.count_workouts() == 0
    end

    test "guessing is cut off", %{conn: conn} do
      AppleHealth.create_webhook_token()

      for _ <- 1..60, do: conn |> with_token("guess") |> post_workouts([])

      conn = conn |> with_token("guess") |> post_workouts([])
      assert json_response(conn, 429)
      assert get_resp_header(conn, "retry-after") != []
    end
  end

  describe "open" do
    setup %{conn: conn} do
      {:ok, conn: with_token(conn, AppleHealth.create_webhook_token())}
    end

    test "a workout is stored and pairs with the ride it was recorded on", %{conn: conn} do
      ride = ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})

      assert %{"received" => 1, "stored" => 1} =
               conn |> post_workouts([@workout]) |> json_response(200)

      assert %{avg_hr: 142, max_hr: 170, min_hr: 92, active_kcal: 600, hr_trace: [0, 95, 60, 120]} =
               Rides.get_ride(ride.id).health
    end

    test "sending it again updates it rather than adding another", %{conn: conn} do
      post_workouts(conn, [@workout])
      post_workouts(conn, [%{@workout | "activeEnergyBurned" => %{"qty" => 640}}])

      assert Rides.count_workouts() == 1
    end

    test "what cannot be read is skipped, and said", %{conn: conn} do
      assert %{"received" => 3, "stored" => 1} =
               conn
               |> post_workouts([@workout, %{"name" => "no start"}, "junk"])
               |> json_response(200)
    end

    # The app can be set to send sleep, weight and the rest alongside. The
    # site has no use for any of it and keeps none of it.
    test "health metrics are accepted and ignored", %{conn: conn} do
      conn =
        post(conn, ~p"/api/health/ingest", %{
          "data" => %{"metrics" => [%{"name" => "body_mass", "data" => [%{"qty" => 70}]}]}
        })

      assert json_response(conn, 200) == %{"received" => 0, "stored" => 0}
    end

    test "anything else is refused as unreadable", %{conn: conn} do
      assert conn |> post(~p"/api/health/ingest", %{"hello" => "world"}) |> json_response(422)
    end
  end

  describe "the token" do
    # Shown once, when it is made. What is kept cannot be turned back into it,
    # so neither the database nor a backup of it holds something that can post.
    test "only its digest is kept", %{conn: conn} do
      token = AppleHealth.create_webhook_token()
      kept = Web.SiteSettings.get_setting("health_webhook_token")

      assert byte_size(token) >= 40
      assert "sha256:" <> _hex = kept
      refute kept =~ token

      # What is kept does not open the door.
      assert conn |> with_token(kept) |> post_workouts([@workout]) |> json_response(401)
      assert conn |> with_token(token) |> post_workouts([@workout]) |> json_response(200)
    end

    test "making another replaces the first", %{conn: conn} do
      first = AppleHealth.create_webhook_token()
      second = AppleHealth.create_webhook_token()

      assert conn |> with_token(first) |> post_workouts([]) |> json_response(401)
      assert conn |> with_token(second) |> post_workouts([]) |> json_response(200)
    end

    test "the environment's is used when none was made, and the made one replaces it", %{
      conn: conn
    } do
      Application.put_env(:web, :health_webhook_token, "from-the-environment")
      on_exit(fn -> Application.delete_env(:web, :health_webhook_token) end)

      assert AppleHealth.webhook_open?()

      assert conn
             |> with_token("from-the-environment")
             |> post_workouts([])
             |> json_response(200)

      made = AppleHealth.create_webhook_token()
      assert conn |> with_token(made) |> post_workouts([]) |> json_response(200)

      assert conn
             |> with_token("from-the-environment")
             |> post_workouts([])
             |> json_response(401)
    end

    # A row left by anything but `create_webhook_token/0` is not a token.
    test "a setting that is not a digest opens nothing", %{conn: conn} do
      Web.SiteSettings.put_setting("health_webhook_token", "plain-text-left-behind")

      refute AppleHealth.webhook_open?()

      assert conn
             |> with_token("plain-text-left-behind")
             |> post_workouts([])
             |> json_response(401)
    end
  end
end
