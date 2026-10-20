defmodule Web.Fitness.GuardrailsTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.{Checks, Guardrails, Training}

  @today ~D[2026-11-10]
  @rdl %{slug: "dumbbell-rdl", low: 10, high: 12, increment: 5.0, pattern: "hinge"}

  @checks Checks.parse("""
          ## Achilles
          states: quiet, talking, angry
          hold: talking
          stop: angry
          guards: box-jumps, single-leg-calf-raises
          talking: Skip the jumps today.

          ## Knee (stairs test)
          states: pass, fail
          stop: fail
          guards: sumo-squat-to-box

          ## Bodyweight
          kind: number
          unit: lb
          """)

  defp checkin(days_ago, answers), do: %{date: Date.add(@today, -days_ago), answers: answers}

  defp state(slug, rule \\ nil, checkins, entries \\ []),
    do: Guardrails.state(slug, rule, checkins, entries, @today, @checks)

  test "the checks are read from the file" do
    assert [
             %{id: "achilles", kind: :state},
             %{id: "knee-stairs-test", stop: ["fail"]},
             %{id: "bodyweight", kind: :number, unit: "lb"}
           ] =
             @checks
  end

  test "green with no check-in, or with a good answer" do
    assert state("box-jumps", []) == {:green, []}
    assert state("box-jumps", [checkin(0, %{"achilles" => "quiet"})]) == {:green, []}
  end

  test "an answer holds or stops only the exercises its check guards, with its advice" do
    talking = [checkin(0, %{"achilles" => "talking"})]

    assert {:hold, ["Achilles talking — Skip the jumps today."]} = state("box-jumps", talking)

    assert {:green, []} = state("dumbbell-rdl", talking),
           "the hinge is not the Achilles' business"

    assert {:stop, ["Achilles angry"]} =
             state("single-leg-calf-raises", [checkin(1, %{"achilles" => "angry"})])

    assert {:stop, ["Knee (stairs test) fail"]} =
             state("sumo-squat-to-box", [checkin(0, %{"knee-stairs-test" => "fail"})])
  end

  test "a check-in older than two days says nothing about today" do
    assert {:green, []} = state("box-jumps", [checkin(3, %{"achilles" => "angry"})])
  end

  test "an answer worsening three check-ins running holds" do
    seq = [
      checkin(0, %{"achilles" => "angry"}),
      checkin(1, %{"achilles" => "talking"}),
      checkin(2, %{"achilles" => "quiet"})
    ]

    assert {:stop, reasons} = state("box-jumps", seq)
    assert "Achilles worse three check-ins running" in reasons
  end

  test "a pattern's load over 1.5 times its average holds a tracked lift" do
    logs =
      for {date, i} <- Enum.with_index(Date.range(Date.add(@today, -28), @today, 7)) do
        weight = if date == @today, do: "300", else: "100"

        %{
          id: i,
          date: date,
          metrics: %{"weight" => weight, "sets" => "1", "reps" => "10"},
          exercise: %{slug: "dumbbell-rdl", name: "RDL"}
        }
      end

    entries = Training.entries(logs, %{lifts: %{"dumbbell-rdl" => @rdl}})
    assert {:hold, [reason]} = state("dumbbell-rdl", @rdl, [], entries)
    assert reason =~ "hinge load at"
  end

  test "hold takes the step up off a target; stop drops it" do
    up = %{sets: 3, reps: 10, weight: 35.0, reason: :up}

    assert Guardrails.apply_to(up, @rdl, {:green, []}) == up
    assert %{weight: 30.0, reason: :hold} = Guardrails.apply_to(up, @rdl, {:hold, ["x"]})
    assert Guardrails.apply_to(up, @rdl, {:stop, ["x"]}) == nil
  end

  test "today's standing lists the checks off their good state" do
    assert [{"Achilles", "talking", :hold}] =
             Guardrails.today(
               [checkin(0, %{"achilles" => "talking", "knee-stairs-test" => "pass"})],
               @today,
               @checks
             )
  end

  test "a stopped exercise names its substitute" do
    assert Guardrails.substitute(%{substitutes: %{"box-jumps" => "step-ups"}}, "box-jumps") ==
             "step-ups"

    assert Guardrails.substitute(nil, "box-jumps") == nil
  end

  test "the verdict in words" do
    assert Guardrails.line({:green, []}) == nil
    assert Guardrails.line({:hold, ["Achilles talking"]}) == "Hold: Achilles talking"
  end
end
