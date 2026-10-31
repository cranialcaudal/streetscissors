defmodule Web.Fitness.PrescriptionTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.Prescription

  @day """
  ### Lower: Hinge (75 Min)

  - [ ] [[box-jumps|Box Jumps]]; 3 x 5, low box, step down.
  - [ ] [[dumbbell-rdl|Dumbbell RDL]]; 3 x 10, 30 lb dumbbells. Groove the hinge.
  - [ ] [[single-leg-calf-raises|Single-Leg Calf Raises]]; 3 x 10–12/leg.
  - [ ] [[hex-flat-side-deadlift|Hexbar Deadlift]]; ramp 5/3/1, then **3 x 3** at top weight.
  - [ ] [[side-planks|Side Planks]]; 3 x 30–40 sec/side.
  - [ ] [[farmers-walk|Farmer's Walk]]; 3 x 40 m, heavy.

  #### Upper 4 x 8-10

  - [ ] **[[push-ups|Push-ups]]** — 3 × 12
  - [ ] [[pull-ups|Pull-Ups]]; 3 x AMRAP.
  - [ ] [[dumbbell-rows|Dumbbell Rows]]; slow on the way down.
  """

  test "each line becomes a kind of entry and its planned numbers" do
    by = Map.new(Prescription.parse(@day), &{&1.slug, &1})

    assert %{kind: :jump, sets: 3, reps: {5, 5}} = by["box-jumps"]
    assert %{kind: :weight, sets: 3, reps: {10, 10}, weight: 30.0} = by["dumbbell-rdl"]
    assert %{sets: 3, reps: {10, 12}} = by["single-leg-calf-raises"]
    # The ramp is warm-up; the work is the 3 x 3.
    assert %{kind: :weight, sets: 3, reps: {3, 3}} = by["hex-flat-side-deadlift"]
    assert %{kind: :hold, sets: 3, seconds: 30} = by["side-planks"]
    assert %{kind: :carry, sets: 3, metres: 40} = by["farmers-walk"]
    assert %{kind: :reps, sets: 3, reps: {12, 12}} = by["push-ups"]
    assert %{kind: :reps, reps: :amrap} = by["pull-ups"]
  end

  test "a line with no numbers takes its heading's, and the section carries its minutes" do
    by = Map.new(Prescription.parse(@day), &{&1.slug, &1})

    assert %{sets: 4, reps: {8, 10}} = by["dumbbell-rows"]
    assert by["dumbbell-rdl"].section == %{title: "Lower: Hinge (75 Min)", minutes: 75}
  end

  test "rest between sets is not a hold, a swim is in yards, and a count is laps" do
    by =
      Map.new(
        Prescription.parse("""
        ### Pull (40 Min)
        - [ ] [[pull-ups|Pull-Ups]]; 4 x 1-3, from a dead hang, 90 sec between sets
        - [ ] [[dumbbell-rows|Dumbbell Rows]]; 3 x 8, 60 sec rest
        - [ ] [[plank|Plank]]; 2 x 45 sec, rest 30 sec
        - [ ] [[kick-with-board|Kick]]; 4 x 25 yd
        - [ ] [[freestyle|Freestyle]]; laps in 15 min, counted
        - [ ] [[swim-time-trial|200 yd Time Trial]]; the baseline
        """),
        &{&1.slug, &1}
      )

    assert %{kind: :reps, sets: 4, reps: {1, 3}, seconds: nil} = by["pull-ups"]
    assert %{kind: :weight, seconds: nil} = by["dumbbell-rows"]
    assert %{kind: :hold, seconds: 45} = by["plank"]
    assert %{kind: :swim, sets: 4, yards: 25} = by["kick-with-board"]
    assert %{kind: :laps, seconds: 900} = by["freestyle"]
    assert %{kind: :trial} = by["swim-time-trial"]
  end

  test "the planned sets count a line with no count as one" do
    assert Prescription.planned_sets([%{sets: 3}, %{sets: nil}, %{sets: 4}]) == 8
  end
end
