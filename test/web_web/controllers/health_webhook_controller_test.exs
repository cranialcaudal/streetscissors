defmodule WebWeb.HealthWebhookControllerTest do
  use WebWeb.ConnCase

  alias Web.Fitness

  @token "test-health-token"

  setup %{conn: conn} do
    {:ok, _} = Web.SiteSettings.put_setting("health_webhook_token", @token)
    {:ok, conn: put_req_header(conn, "authorization", "Bearer " <> @token)}
  end

  defp metric(name, units, qty) do
    %{
      "name" => name,
      "units" => units,
      "data" => [%{"date" => "2026-08-10 09:00:00 -0700", "qty" => qty}]
    }
  end

  defp post_metrics(conn, metrics) do
    post(conn, ~p"/api/health/ingest", %{"data" => %{"metrics" => metrics}})
  end

  test "ingests dietary fiber and calories consumed", %{conn: conn} do
    conn =
      post_metrics(conn, [
        metric("dietary_fiber", "g", 38.4),
        metric("dietary_energy", "kcal", 2900)
      ])

    assert json_response(conn, 200)["ok"] == 1

    entry = Fitness.get_latest_biometric()
    assert entry.fiber_grams == 38
    assert entry.calories_in == 2900
  end

  # Health Auto Export reports energy in whichever unit the phone is set to,
  # and the parser used to discard the units field entirely.
  test "converts dietary energy reported in kilojoules", %{conn: conn} do
    conn = post_metrics(conn, [metric("dietary_energy", "kJ", 10_042)])

    assert json_response(conn, 200)["ok"] == 1
    assert Fitness.get_latest_biometric().calories_in == 2400
  end

  test "treats missing units as kcal", %{conn: conn} do
    conn =
      post(conn, ~p"/api/health/ingest", %{
        "data" => %{
          "metrics" => [
            %{
              "name" => "dietary_energy",
              "data" => [%{"date" => "2026-08-10 09:00:00 -0700", "qty" => 2700}]
            }
          ]
        }
      })

    assert json_response(conn, 200)["ok"] == 1
    assert Fitness.get_latest_biometric().calories_in == 2700
  end

  test "accepts the flat iOS Shortcuts shape for the new fields", %{conn: conn} do
    conn =
      post(conn, ~p"/api/health/ingest", %{
        "date" => "2026-08-10",
        "calories_in" => 2400,
        "fiber_grams" => 41
      })

    assert json_response(conn, 200)["ok"] == 1

    entry = Fitness.get_latest_biometric()
    assert entry.calories_in == 2400
    assert entry.fiber_grams == 41
  end

  describe "workouts" do
    # Health Auto Export's v2 workout, invented values, route included so the
    # test proves it is dropped.
    @workout %{
      "id" => "HK-RIDE-1",
      "name" => "Outdoor Cycling",
      "start" => "2026-07-08 11:00:05 -0700",
      "end" => "2026-07-08 13:00:00 -0700",
      "heartRate" => %{"avg" => %{"qty" => 139.6}, "max" => %{"qty" => 168}},
      "activeEnergyBurned" => %{"qty" => 2600, "units" => "kJ"},
      "heartRateData" => [
        %{"date" => "2026-07-08 11:00:05 -0700", "Avg" => 101, "Max" => 110},
        %{"date" => "2026-07-08 11:01:05 -0700", "Avg" => 130, "Max" => 141}
      ],
      "route" => [%{"latitude" => 1.0, "longitude" => 2.0}]
    }

    test "are stored and pair with the ride they were recorded on", %{conn: conn} do
      ride = Web.RidesFixtures.ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})

      conn = post(conn, ~p"/api/health/ingest", %{"data" => %{"workouts" => [@workout]}})
      assert %{"workouts" => 1, "ok" => 0} = json_response(conn, 200)

      assert %{avg_hr: 140, max_hr: 168, active_kcal: 621, hr_trace: [0, 101, 60, 130]} =
               Web.Rides.get_ride(ride.id).health
    end

    test "a repeated export updates rather than duplicates", %{conn: conn} do
      post(conn, ~p"/api/health/ingest", %{"data" => %{"workouts" => [@workout]}})
      post(conn, ~p"/api/health/ingest", %{"data" => %{"workouts" => [@workout]}})

      assert Web.Rides.count_workouts() == 1
    end

    test "can arrive alongside metrics", %{conn: conn} do
      conn =
        post(conn, ~p"/api/health/ingest", %{
          "data" => %{
            "metrics" => [metric("dietary_fiber", "g", 30)],
            "workouts" => [@workout]
          }
        })

      assert %{"ok" => 1, "workouts" => 1} = json_response(conn, 200)
    end

    test "a payload with neither is refused", %{conn: conn} do
      conn = post(conn, ~p"/api/health/ingest", %{"data" => %{"symptoms" => []}})
      assert json_response(conn, 422)
    end
  end

  test "rejects a bad token", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer wrong")
      |> post_metrics([metric("dietary_fiber", "g", 30)])

    assert json_response(conn, 401)
  end
end
