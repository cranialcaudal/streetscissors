defmodule Web.FitnessLogTest do
  use Web.DataCase

  alias Web.Fitness

  # The invented vault in test/support/fixtures/fitness has one exercise in
  # its wiki, push-ups.

  describe "log_exercise/2" do
    test "files an entry under the wiki's slug, with numbers that compare" do
      assert {:ok, log} =
               Fitness.log_exercise("push-ups", %{
                 "weight" => "22.5",
                 "sets" => "3",
                 "reps" => "8"
               })

      assert log.slug == "push-ups"
      assert log.weight == 22.5
      assert {log.sets, log.reps} == {3, 8}
      assert log.date == Web.Clock.local_today()
      assert log.metrics == %{}
    end

    test "needs no row in the old exercises table" do
      assert Fitness.get_exercise_by_slug("push-ups") == nil
      assert {:ok, _} = Fitness.log_exercise("push-ups", %{"reps" => "20"})
    end

    test "keeps distance, time and result as written, and only when filled in" do
      {:ok, log} =
        Fitness.log_exercise("push-ups", %{
          "distance" => " 2 miles ",
          "time" => "",
          "result" => "to failure",
          "note" => "  slow  "
        })

      assert log.metrics == %{"distance" => "2 miles", "result" => "to failure"}
      assert log.note == "slow"
    end

    test "takes a date for a day that was missed" do
      {:ok, log} = Fitness.log_exercise("push-ups", %{"reps" => "10", "date" => "2026-01-05"})
      assert log.date == ~D[2026-01-05]
    end

    test "refuses an exercise the wiki does not have" do
      assert {:error, :unknown_exercise} = Fitness.log_exercise("no-such-lift", %{"reps" => "5"})
      assert {:error, :unknown_exercise} = Fitness.log_exercise("", %{"reps" => "5"})
    end

    test "refuses an empty entry and a weight that is not one" do
      assert {:error, %Ecto.Changeset{errors: [{:base, _} | _]}} =
               Fitness.log_exercise("push-ups", %{"weight" => "", "note" => " "})

      assert {:error, %Ecto.Changeset{} = changeset} =
               Fitness.log_exercise("push-ups", %{"weight" => "-5", "reps" => "5"})

      assert Keyword.has_key?(changeset.errors, :weight)
    end
  end

  describe "reading the log" do
    setup do
      {:ok, _} =
        Fitness.log_exercise("push-ups", %{
          "weight" => "45",
          "reps" => "5",
          "date" => "2026-01-05"
        })

      {:ok, _} =
        Fitness.log_exercise("push-ups", %{
          "weight" => "50",
          "reps" => "5",
          "date" => "2026-01-12"
        })

      {:ok, _} =
        Fitness.log_exercise("push-ups", %{
          "weight" => "40",
          "reps" => "8",
          "date" => "2026-01-19"
        })

      :ok
    end

    test "is newest first, and the newest so many when asked" do
      assert [40.0, 50.0, 45.0] ==
               Fitness.list_exercise_logs(slug: "push-ups") |> Enum.map(& &1.weight)

      assert [%{weight: 40.0}] = Fitness.list_exercise_logs(slug: "push-ups", limit: 1)
      assert Fitness.list_exercise_logs(slug: "other") == []
    end

    test "knows the heaviest and how many each exercise has" do
      assert Fitness.best_weight("push-ups") == 50.0
      assert Fitness.best_weight("other") == nil
      assert Fitness.logged_exercises() == [{"push-ups", 3}]
    end

    test "deletes one entry" do
      [newest | _] = Fitness.list_exercise_logs()
      assert {:ok, _} = Fitness.delete_exercise_log(newest.id)
      assert {:error, :not_found} = Fitness.delete_exercise_log(newest.id)
      assert length(Fitness.list_exercise_logs()) == 2
    end
  end

  test "describe_log/1 says an entry in a line" do
    {:ok, full} =
      Fitness.log_exercise("push-ups", %{
        "weight" => "135",
        "sets" => "3",
        "reps" => "8",
        "distance" => "2 miles"
      })

    assert Fitness.describe_log(full) == "135 lb · 3 × 8 · 2 miles"

    {:ok, reps} = Fitness.log_exercise("push-ups", %{"reps" => "20"})
    assert Fitness.describe_log(reps) == "20 reps"

    assert Fitness.format_weight(22.5) == "22.5"
    assert Fitness.format_weight(135.0) == "135"
  end
end
