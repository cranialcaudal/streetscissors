defmodule Web.Fitness.BlockTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.Block

  @meta %{
    "title" => "Get Sharp",
    "start" => "2026-10-26",
    "weeks" => "8",
    "phases" => "0 Setup; 1-2 Baseline; 3-6 Push; 7 Peak; 8 Deload",
    "top_set_rpe" => "9",
    "hypothesis" => "8 weeks, +0.25 lb/wk, hypertrophy → visible definition",
    "predict" => "bodyweight +0.25 lb/week; e1rm +10%; compliance 85%",
    "poses" => "front, side, back",
    "lifts" => "hex-flat-side-deadlift 3-3 +5 hinge; box-jumps 5-5 +0 plyo_locomotion",
    "substitutes" => "box-jumps step-ups"
  }

  defp block(meta \\ %{}) do
    {:ok, block} = Block.parse("get-sharp", Map.merge(@meta, meta))
    block
  end

  test "reads the dates, the phases, the lifts and the experiment" do
    block = block()

    assert block.opens == ~D[2026-10-19], "week 0 is the week before the start"
    assert block.finish == ~D[2026-12-20]
    assert block.phases[0] == "Setup"
    assert block.phases[3] == "Push"
    assert block.phases[7] == "Peak"
    assert block.phases[8] == "Deload"
    assert block.top_set_rpe == 9.0
    assert block.hypothesis =~ "visible definition"
    assert block.poses == ~w(front side back)

    assert [
             %{measure: "bodyweight", value: 0.25, unit: "lb/week"},
             %{measure: "e1rm", value: 10.0, unit: "%"},
             _
           ] =
             block.predict

    assert Block.lift(block, "hex-flat-side-deadlift") ==
             %{slug: "hex-flat-side-deadlift", low: 3, high: 3, increment: 5.0, pattern: "hinge"}

    assert Block.lift(block, "push-ups") == nil
  end

  test "the week of a day, week 0 included" do
    b = block()

    assert Block.week_of(~D[2026-10-19], b) == 0
    assert Block.week_of(~D[2026-10-25], b) == 0
    assert Block.week_of(~D[2026-10-26], b) == 1
    assert Block.week_of(~D[2026-12-20], b) == 8
  end

  test "a block that cannot be read is no block" do
    assert Block.parse("x", Map.put(@meta, "start", "2026-10-27")) == :error,
           "a block starts on a Monday"

    assert Block.parse("x", Map.put(@meta, "phases", "1 Baseline; 2-7 Push")) == :error,
           "every week needs a phase"

    assert Block.parse("x", Map.put(@meta, "phases", "1-8 Cruise")) == :error
    assert Block.parse("x", Map.delete(@meta, "title")) == :error
    assert Block.parse("x", Map.put(@meta, "weeks", "eight")) == :error
  end

  test "without week 0 the block opens on its start, and the step RPE defaults to 8" do
    b = block(%{"phases" => "1-2 Baseline; 3-8 Push", "top_set_rpe" => nil})
    assert b.opens == b.start
    assert b.top_set_rpe == 8.0
  end

  test "a lift that does not read is left out, not the block" do
    block =
      block(%{"lifts" => "dumbbell-rdl 10-12 +5 hinge; ../etc 1-2 +5 x; squat 8-5 +5 squat"})

    assert Map.keys(block.lifts) == ["dumbbell-rdl"]
  end

  test "the fixture vault's block covers today" do
    assert %{title: "Test Block", phase: "Push"} = Block.current(Web.Clock.local_today())
    assert Block.current(~D[2026-01-04]) == nil
  end
end
