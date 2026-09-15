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

  test "rejects a bad token", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer wrong")
      |> post_metrics([metric("dietary_fiber", "g", 30)])

    assert json_response(conn, 401)
  end
end
