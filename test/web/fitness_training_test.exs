defmodule Web.Fitness.TrainingTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.Training

  {:ok, block} =
    Web.Fitness.Block.parse("get-sharp", %{
      "title" => "Get Sharp",
      "start" => "2026-10-26",
      "weeks" => "8",
      "phases" => "1 Baseline; 2-3 Accumulate; 4 Deload; 5-7 Intensify; 8 Test",
      "lifts" => "hexbar-rdl 5-8 +5 hinge; weighted-dips 6-10 +5 push"
    })

  @block block

  defp log(id, date, slug, metrics),
    do: %{id: id, date: date, metrics: metrics, exercise: %{slug: slug, name: slug}}

  defp entries(logs), do: Training.entries(logs, @block)

  test "entries are figures, oldest first, with the block lift's pattern" do
    [a, b, c] =
      entries([
        log(3, ~D[2026-10-29], "hexbar-rdl", %{"weight" => "200", "sets" => "3", "reps" => "5"}),
        log(1, ~D[2026-10-27], "weighted-dips", %{"weight" => "25", "sets" => "3", "reps" => "8"}),
        log(2, ~D[2026-10-27], "push-ups", %{"result" => "3 x 12"})
      ])

    assert {a.id, b.id, c.id} == {1, 2, 3}
    assert a.pattern == "push" and b.pattern == nil and c.pattern == "hinge"
    assert c.e1rm == 233.3
    assert c.volume == 3000.0
  end

  test "e1RM by week keeps each week's best" do
    rows =
      entries([
        log(1, ~D[2026-10-27], "hexbar-rdl", %{"weight" => "200", "reps" => "5"}),
        log(2, ~D[2026-10-29], "hexbar-rdl", %{"weight" => "210", "reps" => "5"}),
        log(3, ~D[2026-11-03], "hexbar-rdl", %{"weight" => "215", "reps" => "5"})
      ])

    assert Training.e1rm_by_week(rows, @block, "hexbar-rdl") == %{1 => 245.0, 2 => 250.8}
  end

  test "weekly volume is by pattern and by week, block lifts only" do
    rows =
      entries([
        log(1, ~D[2026-10-27], "hexbar-rdl", %{"weight" => "200", "sets" => "3", "reps" => "5"}),
        log(2, ~D[2026-10-29], "hexbar-rdl", %{"weight" => "200", "sets" => "3", "reps" => "5"}),
        log(3, ~D[2026-10-29], "push-ups", %{"weight" => "20", "sets" => "3", "reps" => "12"}),
        log(4, ~D[2026-10-20], "hexbar-rdl", %{"weight" => "200", "sets" => "3", "reps" => "5"})
      ])

    assert Training.weekly_volume(rows, @block) == %{"hinge" => %{1 => 6000.0}}
  end

  test "ACWR waits for 28 days, then is the week over the four-week average" do
    rows =
      for {date, i} <- Enum.with_index(Date.range(~D[2026-10-26], ~D[2026-11-22], 7)),
          do: log(i, date, "hexbar-rdl", %{"weight" => "100", "sets" => "1", "reps" => "10"})

    rows = entries(rows)
    assert Training.acwr(rows, "hinge", ~D[2026-11-15]) == nil
    assert Training.acwr(rows, "hinge", ~D[2026-11-22]) == 1.0

    spike =
      entries([
        log(99, ~D[2026-11-22], "hexbar-rdl", %{"weight" => "300", "sets" => "1", "reps" => "10"})
      ])

    # The week is 4000 lb against a 28-day weekly average of 7000 / 4.
    assert Training.acwr(rows ++ spike, "hinge", ~D[2026-11-22]) == 2.29
    assert Training.acwr(rows, "push", ~D[2026-11-22]) == nil
  end

  test "compliance counts the planned weekdays trained each week" do
    rows =
      entries([
        log(1, ~D[2026-10-27], "hexbar-rdl", %{"weight" => "200", "reps" => "5"}),
        log(2, ~D[2026-10-29], "push-ups", %{"result" => "3 x 12"}),
        log(3, ~D[2026-11-05], "weighted-dips", %{"weight" => "25", "reps" => "8"})
      ])

    # Tuesday and Thursday planned.
    assert Training.compliance(rows, @block, [1, 2], [2, 4]) == %{1 => {1, 2}, 2 => {1, 2}}
  end

  test "weeks so far are clamped into the block" do
    assert Training.weeks_so_far(@block, ~D[2026-10-01]) == [1]
    assert Training.weeks_so_far(@block, ~D[2026-11-10]) == [1, 2, 3]
    assert Training.weeks_so_far(@block, ~D[2027-03-01]) == Enum.to_list(1..8)
  end

  test "history is an exercise's record, or nil" do
    rows =
      entries([
        log(1, ~D[2026-10-27], "hexbar-rdl", %{"weight" => "200", "reps" => "5"}),
        log(2, ~D[2026-11-03], "hexbar-rdl", %{"weight" => "190", "reps" => "5"})
      ])

    assert %{
             count: 2,
             first: %{id: 1},
             last: %{id: 2},
             best: %{id: 1},
             recent: [%{id: 2}, %{id: 1}]
           } =
             Training.history(rows, "hexbar-rdl")

    assert Training.history(rows, "box-jumps") == nil
  end

  test "the report answers the hypothesis once the last week has begun" do
    rows =
      entries([
        log(1, ~D[2026-10-27], "hexbar-rdl", %{"weight" => "200", "sets" => "3", "reps" => "5"}),
        log(2, ~D[2026-12-15], "hexbar-rdl", %{"weight" => "230", "sets" => "1", "reps" => "5"}),
        log(3, ~D[2026-10-28], "weighted-dips", %{"weight" => "25", "reps" => "8"}),
        log(4, ~D[2026-12-16], "weighted-dips", %{"weight" => "45", "reps" => "8"})
      ])

    weeks = Enum.to_list(1..8)
    calm = [%{date: ~D[2026-11-02], pain: 1, sleep_hours: 7.5, energy: 7}]

    assert %{answer: "Supported:" <> _, lifts: [rdl, dips], rows: rows8} =
             Training.report(rows, @block, weeks, calm, [2, 3])

    assert rdl.change == 15.0
    assert dips.from == {1, 31.7}
    assert %{week: 2, pain: 1.0, sleep: 7.5} = Enum.at(rows8, 1)

    sore = [%{date: ~D[2026-11-02], pain: 6, sleep_hours: nil, energy: nil}]

    assert %{answer: "Not as hoped: pain stopped the block on 1 day."} =
             Training.report(rows, @block, weeks, sore, [2, 3])

    assert %{answer: nil} = Training.report(rows, @block, [1, 2, 3], calm, [2, 3])
  end
end
