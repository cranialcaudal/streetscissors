defmodule Web.FitnessMeasureTest do
  # The figure's body is held to a man's measurements: `priv/figure/measure.mjs`
  # puts a tape round the solid the camera draws and compares it with the lean
  # men of the ANSUR II survey. Before it was measured the hips were a quarter
  # too wide, the crotch a fifth too low and the head a third too broad, and
  # nobody could say what was wrong with the waist. These are the proportions
  # that were wrong; a change to the body that loses one fails here.
  use ExUnit.Case, async: true

  alias Web.Fitness.Clip

  # the tape is node, as the camera is; a machine without it has no figures
  @moduletag skip: is_nil(System.find_executable("node")) && "node is not installed"

  setup_all do
    {:ok, found} = Clip.measurements()
    ratios = Map.new(found["rows"], &{&1["key"], &1["ratio"]})
    %{found: found, ratios: ratios}
  end

  test "the hips are a man's, and the waist is most of them", %{found: found, ratios: ratios} do
    assert_in_delta ratios["hip_breadth"], 1.0, 0.1
    assert_in_delta ratios["waist_breadth"], 1.0, 0.08
    # 0.68 when the hip joints were 4.8 from the middle; a lean man's is 0.89
    assert found["waist_to_hips"] > 0.8 and found["waist_to_hips"] < 0.95
    assert found["shoulders_to_hips"] > 1.35 and found["shoulders_to_hips"] < 1.6
  end

  test "the pelvis is as tall as a pelvis", %{found: found, ratios: ratios} do
    # the crotch was 39% of the way up (a man's is 48.5%): a pelvis drawn as a
    # ball round the hip joints, and thighs that ran together under it
    assert ratios["crotch_height"] > 0.92
    # and the waist is the gap under the ribs, not a tube from the hips up
    assert found["waist_narrowest_at"] > 0.58 and found["waist_narrowest_at"] < 0.67
  end

  test "the head, the neck and the shoulders are in proportion", %{ratios: ratios} do
    assert_in_delta ratios["head_breadth"], 1.0, 0.1
    assert_in_delta ratios["head_girth"], 1.0, 0.08
    assert_in_delta ratios["neck_girth"], 1.0, 0.1
    assert_in_delta ratios["acromial_height"], 1.0, 0.05
    assert_in_delta ratios["bideltoid_breadth"], 1.0, 0.08
  end

  test "the limbs are as thick as a lean man's", %{ratios: ratios} do
    for key <-
          ~w(thigh_girth lower_thigh_girth calf_girth ankle_girth forearm_girth_flexed wrist_girth) do
      assert_in_delta ratios[key], 1.0, 0.08, key
    end

    # drawn a little stronger than the survey's mean, on purpose
    assert ratios["biceps_girth_flexed"] > 0.98 and ratios["biceps_girth_flexed"] < 1.12
  end

  test "what is still off is what the pose engine sets, and nothing else", %{found: found} do
    off = for row <- found["rows"], abs(row["ratio"] - 1) > 0.08, do: row["key"]
    # the ankle joint is two units off the floor in every pose file, and a
    # shoe is wider than a foot
    assert Enum.sort(off) == ["foot_breadth", "malleolus_height"]
  end
end
