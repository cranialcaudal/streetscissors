defmodule Web.Fitness.ExportTest do
  use WebWeb.ConnCase

  alias Web.Fitness
  alias Web.Fitness.Export

  setup do
    {:ok, exercise} = Fitness.loggable_exercise("push-ups")

    {:ok, _} =
      Fitness.create_exercise_log(%{
        exercise_id: exercise.id,
        date: ~D[2026-10-27],
        metrics: %{"weight" => "20 lbs", "sets" => "3", "reps" => "10", "rpe" => "8"},
        note: "felt, strong"
      })

    {:ok, _} =
      Fitness.create_exercise_log(%{
        exercise_id: exercise.id,
        date: ~D[2026-10-20],
        metrics: %{"result" => "3 x 12"}
      })

    :ok
  end

  test "the twelve old columns come first, unchanged, and six new ones follow" do
    [header, older, newer] =
      Export.logs_csv(Fitness.list_exercise_logs()) |> String.split("\n", trim: true)

    assert header ==
             "date,week_num,year,quarter,month,exercise_name,muscle_group,weight_lbs,distance_miles," <>
               "time_str,height_result,notes,exercise_slug,sets,reps,rpe,e1rm_lbs,volume_load_lbs"

    assert older ==
             "2026-10-20,43,2026,4,10,Push-ups,upper,NA,NA,NA,312,NA,push-ups,3,12,NA,NA,NA"

    assert newer ==
             ~s(2026-10-27,44,2026,4,10,Push-ups,upper,20,NA,NA,NA,"felt, strong",push-ups,3,10,8.0,26.7,600.0)
  end

  test "the admin downloads it; anyone else is sent home", %{conn: conn} do
    assert conn |> get("/fitness/export/csv") |> redirected_to() == "/"

    body =
      conn
      |> init_test_session(%{"admin_user" => true})
      |> get("/fitness/export/csv")
      |> response(200)

    assert body =~ "exercise_slug,sets,reps,rpe,e1rm_lbs,volume_load_lbs"
  end

  test "check-ins as CSV, a column per check" do
    {:ok, _} =
      Fitness.save_checkin(%{
        date: ~D[2026-10-27],
        answers: %{"shoulder" => "sore", "bodyweight" => "171.4"}
      })

    {:ok, _} = Fitness.save_checkin(%{date: ~D[2026-10-28], answers: %{}, note: "ok"})

    checks =
      Web.Fitness.Checks.parse("## Shoulder\nstates: fine, sore\n\n## Bodyweight\nkind: number\n")

    assert Export.checkins_csv(Fitness.checkins_between(~D[2026-10-01], ~D[2026-11-01]), checks) ==
             "date,shoulder,bodyweight,note\n2026-10-27,sore,171.4,NA\n2026-10-28,NA,NA,ok\n"
  end

  test "Komoot rides as CSV, in miles and Pacific time, the Thursday morning ride a TT" do
    {:ok, _} =
      Web.Rides.create_ride(%{
        komoot_id: "t1",
        name: "Home to the lab",
        sport: "racebike",
        started_at: ~U[2026-10-22 13:00:00Z],
        distance_m: 24_140.16,
        duration_s: 3600,
        time_in_motion_s: 3500,
        avg_speed_mps: 6.7,
        ascent_m: 100.0,
        kcal: 500
      })

    {:ok, _} =
      Web.Rides.create_ride(%{
        komoot_id: "t2",
        name: "Sunday loop",
        sport: "hike",
        started_at: ~U[2026-10-25 17:00:00Z],
        distance_m: 8_046.72
      })

    [header, tt, hike] =
      Web.Rides.list_rides() |> Export.rides_csv() |> String.split("\n", trim: true)

    assert header ==
             "date,week_num,year,quarter,month,weekday,start_local,sport,kind,tt," <>
               "distance_miles,duration_min,moving_min,avg_mph,ascent_ft,kcal,avg_hr,max_hr"

    assert tt ==
             "2026-10-22,43,2026,4,10,Thu,06:00,racebike,bike,TRUE,15.0,60.0,58.33,14.99,328.08,500,NA,NA"

    assert hike == "2026-10-25,43,2026,4,10,Sun,10:00,hike,hike,FALSE,5.0,NA,NA,NA,NA,NA,NA,NA"
  end
end
