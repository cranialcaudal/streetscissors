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

  test "check-ins as CSV" do
    {:ok, _} = Fitness.save_checkin(%{date: ~D[2026-10-27], pain: 2, sleep_hours: 7.5})

    assert Export.checkins_csv(Fitness.checkins_between(~D[2026-10-01], ~D[2026-11-01])) ==
             "date,pain,sleep_hours,soreness,energy,note\n2026-10-27,2,7.5,NA,NA,NA\n"
  end
end
