defmodule Web.Fitness.ProgressionTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.Progression

  @rule %{slug: "hexbar-rdl", low: 5, high: 8, increment: 5.0, pattern: "hinge"}
  @phases Map.new(
            0..8,
            &{&1, Enum.at(~w(Setup Baseline Baseline Push Push Push Push Peak Deload), &1)}
          )

  defp block(week, rpe \\ 8.0),
    do: %{start: ~D[2026-10-26], phases: @phases, phase: @phases[week], top_set_rpe: rpe}

  # Entries newest first, dated in week 2 unless given.
  defp log(metrics, date \\ ~D[2026-11-03]), do: %{date: date, metrics: metrics}

  describe "parse_log_metrics/1" do
    test "reads weights as pounds, whatever they were written in" do
      assert Progression.parse_log_metrics(%{"weight" => "185 lbs"}).weight == 185.0
      assert Progression.parse_log_metrics(%{"weight" => "185"}).weight == 185.0
      assert Progression.parse_log_metrics(%{"weight" => "90 kg"}).weight == 198.4
      assert Progression.parse_log_metrics(%{"weight" => "bodyweight"}).weight == nil
    end

    test "takes sets and reps from their own fields, else from the result" do
      assert %{sets: 3, reps: 8, rpe: 8.5} =
               Progression.parse_log_metrics(%{"sets" => "3", "reps" => "8", "rpe" => "8.5"})

      assert %{sets: 3, reps: 12} = Progression.parse_log_metrics(%{"result" => "3 x 12"})
      assert %{sets: 4, reps: 6} = Progression.parse_log_metrics(%{"result" => "4×6"})
      assert %{sets: nil, reps: 20} = Progression.parse_log_metrics(%{"result" => "20 reps"})
      assert %{sets: nil, reps: nil} = Progression.parse_log_metrics(%{"result" => "30 inches"})
    end

    test "is nil for what it cannot read, and never raises" do
      assert Progression.parse_log_metrics(nil) == %{weight: nil, sets: nil, reps: nil, rpe: nil}

      assert %{sets: nil, rpe: nil} =
               Progression.parse_log_metrics(%{"sets" => "x", "rpe" => "11"})
    end
  end

  test "e1rm/2 is Epley's, for 1 to 12 reps" do
    assert Progression.e1rm(200.0, 5) == 233.3
    assert Progression.e1rm(200.0, 13) == nil
    assert Progression.e1rm(nil, 5) == nil
  end

  test "volume_load/1 is sets x reps x weight" do
    assert Progression.volume_load(%{weight: 185.0, sets: 3, reps: 8}) == 4440.0
    assert Progression.volume_load(%{weight: nil, sets: 3, reps: 8}) == nil
  end

  describe "next_target/3" do
    test "nothing in the Setup and Baseline weeks, for a lift with no step, or with no reps" do
      top = [log(%{"weight" => "185", "sets" => "3", "reps" => "8"})]
      assert Progression.next_target(@rule, top, block(0)) == nil
      assert Progression.next_target(@rule, top, block(1)) == nil
      assert Progression.next_target(%{@rule | increment: 0.0}, top, block(3)) == nil
      assert Progression.next_target(@rule, [log(%{"weight" => "185"})], block(3)) == nil
    end

    test "the top of the range at the block's step RPE or easier steps up" do
      logs = [log(%{"weight" => "185 lbs", "sets" => "3", "reps" => "8", "rpe" => "9"})]

      assert Progression.next_target(@rule, logs, block(3, 8.0)) |> Map.get(:reason) == :same,
             "RPE 9 is too hard when the block steps at 8"

      assert %{sets: 3, reps: 5, weight: 190.0, reason: :up} =
               Progression.next_target(@rule, logs, block(3, 9.0))

      # RPE not written is taken as 8.
      assert %{reason: :up} =
               Progression.next_target(
                 @rule,
                 [log(%{"weight" => "185", "reps" => "8"})],
                 block(3)
               )
    end

    test "the Peak week progresses as the Push weeks do" do
      logs = [log(%{"weight" => "185", "sets" => "3", "reps" => "8"})]
      assert %{reason: :up} = Progression.next_target(@rule, logs, block(7))
    end

    test "inside the range, one more rep at the same weight" do
      logs = [log(%{"weight" => "185", "sets" => "3", "reps" => "6", "rpe" => "8"})]

      assert %{reps: 7, weight: 185.0, reason: :same} =
               Progression.next_target(@rule, logs, block(3))
    end

    test "a bodyweight lift progresses by reps" do
      logs = [log(%{"sets" => "3", "reps" => "6"})]

      assert %{reps: 7, weight: nil, reason: :same} =
               Progression.next_target(@rule, logs, block(3))
    end

    test "a miss, or two grinding sessions, holds; three misses cut 10%" do
      miss = log(%{"weight" => "185", "reps" => "4"})
      ok = log(%{"weight" => "185", "reps" => "6"})
      grind = log(%{"weight" => "185", "reps" => "6", "rpe" => "9.5"})

      assert %{weight: 185.0, reps: 5, reason: :hold} =
               Progression.next_target(@rule, [miss, ok], block(3))

      assert %{reason: :hold} = Progression.next_target(@rule, [grind, grind], block(3))

      assert %{weight: 165.0, reason: :cut} =
               Progression.next_target(@rule, [miss, miss, miss, ok], block(3))
    end

    test "an entry with no RPE is not taken for a grinding one" do
      plain = log(%{"weight" => "185", "reps" => "6"})
      assert %{reason: :same} = Progression.next_target(@rule, [plain, plain], block(3))
    end

    test "the Deload week keeps the heaviest recent weight for about 60% of the sets" do
      logs = [
        log(%{"weight" => "175", "sets" => "3", "reps" => "8"}),
        log(%{"weight" => "185", "sets" => "3", "reps" => "8"})
      ]

      assert %{sets: 2, reps: 5, weight: 185.0, reason: :deload} =
               Progression.next_target(@rule, logs, block(8))
    end

    test "entries made in a deload week are not stepped up from" do
      deload = log(%{"weight" => "165", "sets" => "2", "reps" => "5"}, ~D[2026-12-15])
      before = log(%{"weight" => "190", "sets" => "3", "reps" => "6"}, ~D[2026-12-10])

      assert %{weight: 190.0, reps: 7, sets: 3} =
               Progression.next_target(@rule, [deload, before], block(7))
    end
  end

  test "hint/4 is the line under a lift" do
    last = %{sets: 3, reps: 8, weight: 30.0, rpe: nil}
    target = %{sets: 3, reps: 5, weight: 35.0, reason: :up}

    assert Progression.hint(@rule, last, target, block(3)) ==
             "Last: 3×8 @ 30 lbs → Target: 3×5 @ 35 lbs · +5 lbs when all sets hit 8"

    assert Progression.hint(@rule, last, nil, block(1)) =~ "Baseline: find a weight"
    assert Progression.hint(@rule, nil, nil, nil) == nil
  end

  test "target_line/1" do
    assert Progression.target_line(%{sets: 3, reps: 8, weight: 190.0}) == "3 x 8 @ 190 lbs"
    assert Progression.target_line(%{sets: 3, reps: 8, weight: 92.5}) == "3 x 8 @ 92.5 lbs"
    assert Progression.target_line(%{sets: 3, reps: 10, weight: nil}) == "3 x 10"
  end
end
