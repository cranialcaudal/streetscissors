defmodule Web.Fitness.BlockTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.Block

  @meta %{
    "title" => "Get Sharp",
    "start" => "2026-10-26",
    "weeks" => "8",
    "phases" => "1 Baseline; 2-3 Accumulate; 4 Deload; 5-7 Intensify; 8 Test",
    "lifts" => "hexbar-rdl 5-8 +5 hinge; box-jumps 3-3 +0 plyo_locomotion"
  }

  defp block(meta \\ %{}) do
    {:ok, block} = Block.parse("get-sharp", Map.merge(@meta, meta))
    block
  end

  test "reads the dates, the phases and the lifts" do
    block = block()

    assert block.finish == ~D[2026-12-20]
    assert block.phases[1] == "Baseline"
    assert block.phases[4] == "Deload"
    assert block.phases[8] == "Test"

    assert Block.lift(block, "hexbar-rdl") ==
             %{slug: "hexbar-rdl", low: 5, high: 8, increment: 5.0, pattern: "hinge"}

    assert Block.lift(block, "box-jumps").increment == 0.0
    assert Block.lift(block, "push-ups") == nil
  end

  test "a block that cannot be read is no block" do
    assert Block.parse("x", Map.put(@meta, "start", "2026-10-27")) == :error,
           "a block starts on a Monday"

    assert Block.parse("x", Map.put(@meta, "phases", "1 Baseline; 2-7 Accumulate")) == :error,
           "every week needs a phase"

    assert Block.parse("x", Map.put(@meta, "phases", "1-8 Cruise")) == :error
    assert Block.parse("x", Map.delete(@meta, "title")) == :error
    assert Block.parse("x", Map.put(@meta, "weeks", "eight")) == :error
  end

  test "a lift that does not read is left out, not the block" do
    block = block(%{"lifts" => "hexbar-rdl 5-8 +5 hinge; ../etc 1-2 +5 x; squat 8-5 +5 squat"})
    assert Map.keys(block.lifts) == ["hexbar-rdl"]
  end

  test "the fixture vault's block covers today" do
    assert %{title: "Test Block", phase: "Accumulate"} = Block.current(Web.Clock.local_today())
    assert Block.current(~D[2026-01-04]) == nil
  end
end
