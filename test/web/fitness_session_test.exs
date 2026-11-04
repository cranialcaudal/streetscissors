defmodule Web.Fitness.SessionTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.{Coach, Plates, Prescription, Records, Session}

  @md """
  ### Upper B (65 Min)
  *Goal: prose, not shown.*

  - [ ] [[hip-thrusts|Hip Thrusts]]; 3 x 8-12, Smith machine.
  - [ ] Week 1 of 8: find the working weights

  #### Superset A: Flat Bench
  - [ ] [[smith-bench-press|Smith Bench Press]]; 3 x 6-10, 90 sec between sets
  - [ ] [[dumbbell-pullover|Dumbbell Pullover]]; 3 x 10-12

  #### Arms
  - [ ] [[bicep-curls|Curls]]; 3 x 10-12
  - [ ] [[hip-thrusts|Hip Thrusts]] again, as a note
  """

  defp coach(md) do
    for p <- Prescription.parse(md), into: %{} do
      {p.slug, Coach.plan(p, [], nil, [], [], [], ~D[2026-10-27])}
    end
  end

  test "a day reads into modules, stations, supersets and notes" do
    %{modules: [m], stations: stations} = Session.from_markdown(@md, coach(@md), [])

    assert m.title == "Upper B (65 Min)"

    assert [
             %{type: :exercise, slug: "hip-thrusts"},
             %{type: :note, text: "Week 1 of 8: find the working weights"},
             %{
               type: :superset,
               title: "Superset A: Flat Bench",
               items: [%{slug: "smith-bench-press"}, %{slug: "dumbbell-pullover"}]
             },
             %{type: :heading, text: "Arms"},
             %{type: :exercise, slug: "bicep-curls"},
             %{type: :note}
           ] = m.items

    assert Enum.map(stations, & &1.type) == [:exercise, :superset, :exercise]
    assert Enum.map(stations, & &1.index) == [0, 1, 2]
    assert Session.current(%{stations: stations}) == 0
  end

  test "the rest is the line's own, else the default" do
    plans = coach(@md)
    assert Session.rest_seconds(plans["smith-bench-press"]) == 90
    assert Session.rest_seconds(plans["bicep-curls"]) == 90
  end

  test "a line's text becomes safe HTML with its links" do
    html =
      "[[bicep-curls|Curls]]; **3 x 10** <b>" |> Session.inline() |> Phoenix.HTML.safe_to_string()

    assert html =~ ~s(data-figure="bicep-curls")
    assert html =~ "<strong>3 x 10</strong>"
    assert html =~ "&lt;b&gt;"
    assert Session.detail("[[bicep-curls|Curls]]; 3 x 10") == "3 x 10"
  end

  test "plates a side, and the warm-up to a top set" do
    plates = [45.0, 35.0, 25.0, 10.0, 5.0, 2.5]
    assert Plates.per_side(185.0, 45.0, plates) == {[45.0, 25.0], 0.0}
    assert Plates.per_side(140.0, 55.0, plates) == {[35.0, 5.0, 2.5], 0.0}
    assert Plates.per_side(30.0, 45.0, plates) == nil
    assert Plates.ramp(200.0, 55.0, plates) == [{5, 100.0}, {3, 140.0}, {1, 170.0}]
    assert Plates.describe([]) == "the bar alone"
  end

  test "a best beats only the same kind of score, and a first entry is no best" do
    entry = fn sets -> %{metrics: Web.Fitness.Entry.sets_metrics(sets)} end
    old = entry.([%{"w" => 135.0, "r" => 3}])
    new = entry.([%{"w" => 145.0, "r" => 3}])

    assert {:best, {:e1rm, _}, {:e1rm, _}} = Records.new_best(new, [old])
    assert Records.new_best(old, [new]) == nil
    assert Records.new_best(new, []) == nil

    assert Records.new_best(entry.([%{"w" => nil, "r" => 3}]), [entry.([%{"w" => nil, "r" => 2}])]) ==
             {:best, {:reps, 3}, {:reps, 2}}

    assert Records.score(%{metrics: %{"result" => "24 laps"}}) == {:laps, 24}
  end

  describe "where a lift's chips start" do
    @ramp %{
      id: 1,
      date: ~D[2026-10-27],
      note: nil,
      metrics: %{
        "weight" => "250 lbs",
        "reps" => "1",
        "set_list" => [
          %{"w" => 190.0, "r" => 5},
          %{"w" => 210.0, "r" => 3},
          %{"w" => 250.0, "r" => 1}
        ]
      }
    }

    defp lift(sets, reps) do
      %{
        slug: "hex-flat-side-deadlift",
        kind: :weight,
        sets: sets,
        reps: reps,
        weight: nil,
        seconds: nil,
        metres: nil
      }
    end

    test "a ramp to a single does not open a lighter day at the single" do
      plan = Coach.plan(lift(2, {5, 5}), [@ramp], nil, [], [], [], ~D[2026-11-03])

      assert %{sets: 2, reps: 5, weight: 190.0} = plan.defaults
    end

    test "with no set that reached the reps, the weight stays and the plan's reps win" do
      log = %{
        id: 2,
        date: ~D[2026-10-27],
        note: nil,
        metrics: %{"weight" => "30 lbs", "reps" => "6"}
      }

      plan = Coach.plan(lift(2, {8, 8}), [log], nil, [], [], [], ~D[2026-11-03])

      assert %{reps: 8, weight: 30.0} = plan.defaults
    end

    test "a last entry that met the plan starts where it was" do
      log = %{
        id: 3,
        date: ~D[2026-10-27],
        note: nil,
        metrics: %{"weight" => "200 lbs", "reps" => "5"}
      }

      plan = Coach.plan(lift(2, {5, 5}), [log], nil, [], [], [], ~D[2026-11-03])

      assert %{reps: 5, weight: 200.0} = plan.defaults
    end
  end
end
