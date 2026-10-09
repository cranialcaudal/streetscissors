defmodule Web.Fitness.FigureTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.Figure

  # A squat: feet planted, hips down and back, a bell held at the chest.
  @squat %{
    "view" => "side",
    "planted" => ["foot_a", "foot_b"],
    "props" => [%{"kind" => "kettlebell", "hold" => "hands"}],
    "poses" => [
      %{
        "name" => "stand",
        "hold" => 0.4,
        "move" => 1.4,
        "pelvis" => [78, 60],
        "lean" => 4,
        "feet" => [78, 99],
        "hands" => [88, 41],
        "elbows" => "down"
      },
      %{
        "name" => "bottom",
        "hold" => 0.5,
        "move" => 1.2,
        "pelvis" => [68, 82],
        "lean" => 28,
        "feet" => [78, 99],
        "hands" => [89, 64],
        "elbows" => "down"
      }
    ]
  }

  defp points(d) do
    for [_, x, y] <- Regex.scan(~r/[ML]([\d.-]+) ([\d.-]+)/, d),
        do: {String.to_float(x), String.to_float(y)}
  end

  # A layer of the drawing by name, and one of its parts: a leg's are its
  # thigh, shin and foot; the trunk's (side view) its neck, belly and chest.
  defp layer(figure, name), do: Enum.find(figure.back ++ figure.top, &(&1.name == name))

  defp part(figure, name, index),
    do: figure |> layer(name) |> Map.fetch!(:parts) |> Enum.at(index)

  defp change(figure, pose, fun), do: update_in(figure, ["poses", Access.at(pose)], fun)

  defp distance({ax, ay}, {bx, by}), do: :math.sqrt(:math.pow(bx - ax, 2) + :math.pow(by - ay, 2))

  test "a figure bakes into a loop that closes, with a stop at each pose" do
    assert {:ok, figure} = Figure.build(@squat)

    assert figure.seconds == 3.5
    assert Enum.map(figure.stops, & &1.name) == ["stand", "bottom"]
    assert Enum.map(figure.stops, & &1.at) == [0.0, 1.8]

    for layer <- figure.back ++ figure.top, part <- layer.parts do
      assert length(part.d) == figure.frames
      assert List.first(part.d) == List.last(part.d)
    end
  end

  # Back to front: the far limbs, the trunk, the near leg, and the near arm
  # last, over what is held. Only the near limbs carry an edge.
  test "the body is drawn in layers, far side first" do
    {:ok, figure} = Figure.build(@squat)

    assert Enum.map(figure.back, & &1.name) == [:leg_b, :arm_b, :trunk, :leg_a]
    assert Enum.map(figure.top, & &1.name) == [:arm_a]
    assert Enum.map(figure.back ++ figure.top, & &1.tone) == [:far, :far, :body, :near, :near]
    assert Enum.map(figure.back ++ figure.top, & &1.edge) == [false, false, false, true, true]
  end

  test "every part has a thickness, and a thigh is thicker than a shin" do
    {:ok, figure} = Figure.build(@squat)
    [thigh, shin, foot] = layer(figure, :leg_a).parts

    assert thigh.w > shin.w and shin.w > foot.w

    assert Enum.all?(figure.back ++ figure.top, fn layer ->
             Enum.all?(layer.parts, &(&1.w > 3))
           end)
  end

  test "a planted foot does not move, and no bone grows" do
    {:ok, figure} = Figure.build(@squat)

    for {thigh, shin} <- Enum.zip(part(figure, :leg_a, 0).d, part(figure, :leg_a, 1).d) do
      [hip, knee] = points(thigh)
      [^knee, foot] = points(shin)

      assert foot == {78.0, 99.0}
      assert_in_delta distance(hip, knee), 20.0, 1.3
      assert_in_delta distance(knee, foot), 20.0, 1.3
    end
  end

  test "the knees bend forward and the hips sink at the bottom" do
    {:ok, figure} = Figure.build(@squat)
    bottom = round(1.8 / figure.seconds * (figure.frames - 1))

    [{hip_x, hip_y}, {knee_x, _}] = points(Enum.at(part(figure, :leg_a, 0).d, bottom))
    [{_, stand_hip_y}, _] = points(hd(part(figure, :leg_a, 0).d))

    assert knee_x > hip_x
    assert hip_y > stand_hip_y + 15
  end

  test "what is held follows the hands, in front of the body unless a pose says otherwise" do
    {:ok, figure} = Figure.build(@squat)
    [bell] = figure.props

    assert bell.kind == :kettlebell
    assert length(bell.cx) == figure.frames
    assert hd(bell.cy) == "46.0"
    assert Enum.uniq(bell.behind) == [false]
  end

  # How a twist reads in a flat picture: the weight goes behind the body.
  test "a pose can put the weight behind the body, and it changes side halfway to the next" do
    {:ok, figure} = Figure.build(change(@squat, 1, &Map.put(&1, "weight", "behind")))
    [bell] = figure.props
    bottom = round(1.8 / figure.seconds * (figure.frames - 1))

    refute hd(bell.behind)
    assert Enum.at(bell.behind, bottom)
    assert Enum.count(bell.behind, & &1) in 15..27
  end

  test "what the far hand holds alone is behind the body" do
    far = put_in(@squat, ["props"], [%{"kind" => "kettlebell", "hold" => "hand_b"}])
    {:ok, figure} = Figure.build(far)

    assert Enum.uniq(hd(figure.props).behind) == [true]
  end

  test "a single pose is a hold that stands still" do
    hold = Map.put(@squat, "poses", [hd(@squat["poses"])])
    assert {:ok, figure} = Figure.build(hold)

    assert length(figure.stops) == 1
    assert figure |> part(:trunk, 1) |> Map.fetch!(:d) |> Enum.uniq() |> length() == 1
  end

  test "mirror turns the figure to face the other way" do
    {:ok, right} = Figure.build(@squat)
    {:ok, left} = Figure.build(Map.put(@squat, "mirror", true))

    [{x, y} | _] = points(hd(part(right, :trunk, 1).d))
    [{mx, my} | _] = points(hd(part(left, :trunk, 1).d))

    assert_in_delta mx, 160 - x, 0.01
    assert my == y
  end

  test "seen from the front the trunk is a shape between shoulders and hips" do
    front = %{
      "view" => "front",
      "poses" => [
        %{
          "name" => "stand",
          "pelvis" => [80, 60],
          "arm_a" => [-170, 1.0],
          "arm_b" => [170, 1.0],
          "foot_a" => [75, 99],
          "foot_b" => [85, 99],
          "elbows" => "out",
          "knees" => "out"
        }
      ]
    }

    {:ok, figure} = Figure.build(front)

    assert Enum.map(figure.back, & &1.name) == [:leg_a, :leg_b, :trunk]
    assert Enum.map(figure.top, & &1.name) == [:arm_a, :arm_b]
    assert [%{d: [shape | _]}] = layer(figure, :trunk).shapes
    assert shape =~ ~r/^M72\.0 34\.0L88\.0 34\.0L85\.0 60\.0L75\.0 60\.0Z$/
  end

  describe "a figure that cannot be is refused, with the pose named" do
    test "a hand out of reach" do
      assert {:error, [problem | _]} =
               Figure.build(change(@squat, 0, &Map.put(&1, "hands", [140, 20])))

      assert problem =~ ~s(pose "stand")
      assert problem =~ "out of reach"
    end

    test "a foot through the floor" do
      broken =
        @squat
        |> change(0, &Map.put(&1, "feet", [78, 104]))
        |> change(1, &Map.put(&1, "feet", [78, 104]))

      assert {:error, problems} = Figure.build(broken)
      assert Enum.any?(problems, &(&1 =~ "below the floor"))
    end

    test "a planted foot that moves" do
      assert {:error, [problem | _]} =
               Figure.build(change(@squat, 1, &Map.put(&1, "feet", [82, 99])))

      assert problem =~ "foot_a is planted but is not in the same place"
    end

    test "a key it does not know, so a misspelling is not silently ignored" do
      assert {:error, [problem]} = Figure.build(change(@squat, 0, &Map.put(&1, "elbow", "down")))
      assert problem =~ "a key it does not know: elbow"
    end

    test "a joint that would pop across its limb between poses" do
      flipped = change(@squat, 1, &Map.put(&1, "elbows", "up"))
      assert {:error, problems} = Figure.build(flipped)
      assert Enum.any?(problems, &(&1 =~ ~s(bends one way in "stand" and the other in "bottom")))
    end

    test "a bend that means nothing in this view" do
      assert {:error, [problem | _]} =
               Figure.build(change(@squat, 0, &Map.put(&1, "elbows", "out")))

      assert problem =~ "elbow_a must be one of up, down, front, back"
    end

    test "a loop too long to watch" do
      assert {:error, [problem]} = Figure.build(change(@squat, 0, &Map.put(&1, "hold", 20)))
      assert problem =~ "the loop lasts"
    end

    test "a file that is not JSON" do
      assert {:error, [problem]} = Figure.from_json("{not json")
      assert problem =~ "not valid JSON"
    end
  end

  # A rollout from the knees: the feet stay where they are and the hips go
  # forward and down over the knees.
  @rollout %{
    "view" => "side",
    "planted" => ["foot_a", "foot_b"],
    "poses" => [
      %{
        "name" => "start",
        "hold" => 0.3,
        "move" => 1.6,
        "pelvis" => [80, 79],
        "lean" => 60,
        "feet" => [61, 97],
        "hands" => [106, 94],
        "elbows" => "down",
        "knees" => "down"
      },
      %{
        "name" => "rolled out",
        "hold" => 0.4,
        "move" => 1.6,
        "pelvis" => [95, 85],
        "lean" => 78,
        "feet" => [61, 97],
        "hands" => [144, 94],
        "elbows" => "down",
        "knees" => "down"
      }
    ]
  }

  test "a body rocking over its knees rides up on them instead of pressing them into the floor" do
    assert {:ok, track} = Figure.track(@rollout)

    knees = for frame <- track.frames, do: frame.knee_a |> Enum.at(1)
    assert Enum.max(knees) <= 99.6

    # Halfway, the hips are above the straight line between the two poses.
    {_x, halfway} =
      track.frames
      |> Enum.map(fn frame -> List.to_tuple(frame.pelvis) end)
      |> Enum.min_by(fn {x, _y} -> abs(x - 87.5) end)

    assert halfway < 82.0
  end

  describe "what only the film can show is carried to it" do
    test "how far the elbows are out to the sides, and the hands apart" do
      flared =
        @squat
        |> change(0, &Map.merge(&1, %{"flare" => 0.0, "spread" => 4}))
        |> change(1, &Map.merge(&1, %{"flare" => 1, "spread" => 12}))

      assert {:ok, track} = Figure.track(flared)
      assert hd(track.frames).flare == 0.0
      assert hd(track.frames).spread == 4.0
      assert Enum.max_by(track.frames, & &1.flare).flare > 0.95
      assert Enum.max_by(track.frames, & &1.spread).spread > 11.5
    end

    test "a figure that says nothing of them is filmed in the plane of the picture" do
      assert {:ok, track} = Figure.track(@squat)
      assert Enum.all?(track.frames, &(&1.flare == 0.0 and &1.spread == nil))
    end

    test "a band that comes from beside the body, and a disc that is a ball" do
      rigged =
        Map.put(@squat, "props", [
          %{"kind" => "line", "from" => [78, 47], "to" => "hands", "depth" => 58},
          %{"kind" => "disc", "at" => [108, 28], "r" => 4.6, "ball" => true},
          %{"kind" => "disc", "at" => [40, 96], "r" => 3}
        ])

      assert {:ok, track} = Figure.track(rigged)

      assert [
               %{kind: :line, depth: 58.0},
               %{kind: :disc, ball: true},
               %{kind: :disc, ball: false}
             ] = track.props

      # and the flat drawing still draws them
      assert {:ok, _figure} = Figure.build(rigged)
    end

    test "a depth that is not a number is refused" do
      bad =
        Map.put(@squat, "props", [
          %{"kind" => "line", "from" => [78, 47], "to" => "hands", "depth" => "near"}
        ])

      assert {:error, [problem]} = Figure.build(bad)
      assert problem =~ "depth must be a number"
    end
  end

  test "an exercise with no file has no figure" do
    assert Figure.load("no-such-exercise") == :none
  end

  test "explicit targets can be defined in figure JSON" do
    with_targets = Map.put(@squat, "targets", ["quads", "glutes"])
    assert {:ok, figure} = Figure.build(with_targets)
    assert figure.targets == [:quads, :glutes]

    thigh = hd(layer(figure, :leg_a).parts)
    assert thigh.targeted
    assert thigh.muscle == :quads
  end

  test "the mannequin head carries a visor facet" do
    {:ok, figure} = Figure.build(@squat)
    [head] = layer(figure, :trunk).over
    assert Map.has_key?(head, :visor)
    assert length(head.visor) == figure.frames
  end
end
