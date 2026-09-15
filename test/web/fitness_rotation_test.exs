defmodule Web.Fitness.RotationTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.Rotation

  doctest Web.Fitness.Rotation

  # Dates are pinned rather than derived from today, so the suite does not
  # change behaviour with the calendar.
  describe "index/2" do
    test "week 1 is the first option" do
      assert Rotation.index(2, ~D[2026-01-01]) == 0
      assert Rotation.index(4, ~D[2026-01-01]) == 0
    end

    test "Friday alternates: odd weeks swim, even weeks run" do
      assert Rotation.index(2, ~D[2026-01-01]) == 0
      assert Rotation.index(2, ~D[2026-01-08]) == 1
      assert Rotation.index(2, ~D[2026-01-15]) == 0
      assert Rotation.index(2, ~D[2026-01-22]) == 1
    end

    test "Saturday runs a four-week cycle and wraps" do
      weeks = [~D[2026-01-01], ~D[2026-01-08], ~D[2026-01-15], ~D[2026-01-22], ~D[2026-01-29]]
      assert Enum.map(weeks, &Rotation.index(4, &1)) == [0, 1, 2, 3, 0]
    end

    test "every day in the same ISO week gets the same option" do
      # Mon-Sun of one ISO week: the option must not change mid-week.
      week = Date.range(~D[2026-01-05], ~D[2026-01-11])
      assert week |> Enum.map(&Rotation.index(4, &1)) |> Enum.uniq() |> length() == 1
    end

    test "a single-option day is always index 0" do
      assert Rotation.index(1, ~D[2026-06-15]) == 0
      assert Rotation.index(0, ~D[2026-06-15]) == 0
    end

    test "handles the year boundary, where a date can fall in week 53 of the prior year" do
      # 2027-01-01 is a Friday, which ISO puts in week 53 of 2026.
      assert Rotation.week_number(~D[2027-01-01]) == 53
      # It still resolves to a valid option rather than crashing or going negative.
      assert Rotation.index(4, ~D[2027-01-01]) in 0..3
      assert Rotation.index(2, ~D[2027-01-01]) in 0..1
    end
  end

  describe "mark/2" do
    test "flags exactly one option as active" do
      marked = Rotation.mark([:a, :b, :c, :d], ~D[2026-01-15])

      assert length(marked) == 4
      assert Enum.count(marked, fn {_opt, active?} -> active? end) == 1
      assert {:c, true} in marked
    end

    test "preserves order" do
      assert Rotation.mark([:a, :b], ~D[2026-01-01]) == [{:a, true}, {:b, false}]
    end

    test "an empty list marks nothing" do
      assert Rotation.mark([], ~D[2026-01-01]) == []
    end
  end
end
