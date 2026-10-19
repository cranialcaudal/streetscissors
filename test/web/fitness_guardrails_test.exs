defmodule Web.Fitness.GuardrailsTest do
  use ExUnit.Case, async: true

  alias Web.Fitness.{Guardrails, Training}

  @today ~D[2026-11-10]
  @rdl %{slug: "hexbar-rdl", low: 5, high: 8, increment: 5.0, pattern: "hinge"}
  @jumps %{slug: "box-jumps", low: 3, high: 3, increment: 0.0, pattern: "plyo_locomotion"}

  defp checkin(days_ago, pain), do: %{date: Date.add(@today, -days_ago), pain: pain}

  test "green with no check-in, or an easy one" do
    assert Guardrails.state(@rdl, [], [], @today) == {:green, []}
    assert Guardrails.state(@rdl, [checkin(0, 2)], [], @today) == {:green, []}
  end

  test "pain 3 or 4 holds; 5 or more stops" do
    assert {:hold, ["pain 3 of 10"]} = Guardrails.state(@rdl, [checkin(0, 3)], [], @today)
    assert {:stop, ["pain 5 of 10"]} = Guardrails.state(@rdl, [checkin(1, 5)], [], @today)
  end

  test "a check-in older than two days says nothing about today" do
    assert {:green, []} = Guardrails.state(@rdl, [checkin(3, 6)], [], @today)
  end

  test "pain rising three check-ins running stops, however low" do
    assert {:stop, ["pain rising three check-ins running"]} =
             Guardrails.state(@rdl, [checkin(0, 2), checkin(1, 1), checkin(2, 0)], [], @today)
  end

  test "a pattern's load over 1.5 times its average holds" do
    logs =
      for {date, i} <- Enum.with_index(Date.range(Date.add(@today, -28), @today, 7)) do
        weight = if date == @today, do: "300", else: "100"

        %{
          id: i,
          date: date,
          metrics: %{"weight" => weight, "sets" => "1", "reps" => "10"},
          exercise: %{slug: "hexbar-rdl", name: "RDL"}
        }
      end

    entries = Training.entries(logs, %{lifts: %{"hexbar-rdl" => @rdl}})
    assert {:hold, [reason]} = Guardrails.state(@rdl, [], entries, @today)
    assert reason =~ "hinge load at"
  end

  test "hold and stop take the step up off a target; stop drops a plyometric's" do
    up = %{sets: 3, reps: 5, weight: 190.0, reason: :up}

    assert Guardrails.apply_to(up, @rdl, {:green, []}) == up
    assert %{weight: 185.0, reason: :hold} = Guardrails.apply_to(up, @rdl, {:hold, ["x"]})
    assert %{weight: 185.0} = Guardrails.apply_to(up, @rdl, {:stop, ["x"]})
    assert Guardrails.apply_to(up, @jumps, {:stop, ["x"]}) == nil
  end

  test "a stopped plyometric names its substitute" do
    block = %{substitutes: %{"box-jumps" => "step-ups"}}
    assert Guardrails.substitute(block, @jumps) == "step-ups"
    assert Guardrails.substitute(block, @rdl) == nil
  end

  test "the verdict in words" do
    assert Guardrails.line({:green, []}) == nil
    assert Guardrails.line({:hold, ["pain 3 of 10"]}) == "Hold: pain 3 of 10"
  end
end
