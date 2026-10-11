defmodule Web.Fitness.ChainTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.{Chain, Figure}

  defp tiers(raw, primary) do
    {:ok, track} = Figure.track(raw, 12)
    Chain.tiers(raw, track, primary)
  end

  defp standing(props, hands) do
    %{
      "view" => "side",
      "props" => props,
      "poses" => [
        %{
          "name" => "one",
          "pelvis" => [80, 60],
          "lean" => 0,
          "feet" => [80, 99],
          "hands" => hands
        },
        %{
          "name" => "two",
          "pelvis" => [80, 60],
          "lean" => 4,
          "feet" => [80, 99],
          "hands" => hands
        }
      ]
    }
  end

  test "a weight in the hands of a standing body is held by the grip and the trunk, and carried by the legs" do
    found = tiers(standing([%{"kind" => "dumbbell", "hold" => "hands"}], [84, 62]), ["biceps"])

    assert found.primary == ["biceps"]
    assert "forearms" in found.chain and "abs" in found.chain and "lowback" in found.chain
    assert "quads" in found.brace and "calves" in found.brace
  end

  test "with nothing in the hands there is no chain to name" do
    assert %{chain: [], brace: []} = tiers(standing([], [84, 62]), ["quads"])
  end

  test "a muscle the page names is not repeated in a weaker tier" do
    found =
      tiers(standing([%{"kind" => "kettlebell", "hold" => "hands"}], [84, 62]), ["abs", "quads"])

    refute "abs" in found.chain
    refute "quads" in found.brace
  end

  test "a load pressed overhead brings in the shoulder blades" do
    found = tiers(standing([%{"kind" => "dumbbell", "hold" => "hands"}], [80, 8]), ["delts"])
    assert "traps" in found.chain and "serratus" in found.chain
  end

  test "the finer groups are heard in a page's anatomy" do
    assert Chain.detail("Hip flexors, tibialis anterior and the rhomboids") ==
             ["rhomboids", "hipflexors", "tibialis"]

    assert Chain.detail(nil) == []
  end
end
