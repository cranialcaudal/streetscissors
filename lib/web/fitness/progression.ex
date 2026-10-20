defmodule Web.Fitness.Progression do
  @moduledoc """
  What a log entry says in numbers, and what the next session of a block
  lift should be.

  A log's `metrics` are the strings the form took (`"185 lbs"`, `"3"`,
  `"8"`, `"8.5"`), kept that way so the CSV export reads them as it always
  has. `parse_log_metrics/1` reads them back as numbers; anything it cannot
  read is nil, and it never raises.

  The rule is double progression inside the lift's rep range (see
  `next_target/3`), with Epley's estimate (`e1rm/2`) as the measure of
  strength. `docs/get-sharp-handoff.md` §3.1 is the rule in prose.
  """

  @kg_to_lb 2.20462

  @doc """
  A log's metrics as numbers: `%{weight: lbs, sets: n, reps: n, rpe: n}`,
  each nil when absent or unreadable. Sets and reps come from their own
  fields, else from a result like `"3 x 8"` or `"20 reps"`.
  """
  def parse_log_metrics(metrics) when is_map(metrics) do
    {result_sets, result_reps} = sets_reps(metrics["result"])

    %{
      weight: weight(metrics["weight"]),
      sets: count(metrics["sets"]) || result_sets,
      reps: count(metrics["reps"]) || result_reps,
      rpe: rpe(metrics["rpe"])
    }
  end

  def parse_log_metrics(_), do: %{weight: nil, sets: nil, reps: nil, rpe: nil}

  @doc "Epley's estimated one-rep max, for 1 to 12 reps; nil otherwise."
  def e1rm(weight, reps)
      when is_number(weight) and weight > 0 and is_integer(reps) and reps in 1..12,
      do: Float.round(weight * (1 + reps / 30), 1)

  def e1rm(_weight, _reps), do: nil

  @doc """
  Sets × reps × weight for a parsed entry, or nil. The reps are the top
  set's, so this is an upper bound when later sets fell short.
  """
  def volume_load(%{weight: w, reps: r} = parsed) when is_number(w) and is_integer(r),
    do: Float.round((parsed.sets || 1) * r * w * 1.0, 1)

  def volume_load(_parsed), do: nil

  @doc """
  The next session of a lift: `%{sets, reps, weight, reason}`, or nil when
  there is nothing to aim at: the Setup and Baseline weeks (find the
  working weights first), a lift with no step, no entry with reps yet.
  `weight` is nil for a lift done at bodyweight, which progresses by reps.

  `rule` is the block's lift (`Web.Fitness.Block.lift/2`), `logs` its
  entries newest first, `block` the running block from
  `Web.Fitness.Block.current/1`. The rule by phase:

    * **Push** and **Peak**: double progression. Every set at the top of
      the range, the top set no harder than the block's `top_set_rpe`,
      adds the step and starts the reps again at the bottom; below the
      bottom, or two grinding sessions (RPE 9.5+), holds; three misses
      running cut 10%; otherwise one more rep at the same weight.
    * **Deload**: the same weight for about 60% of the sets.

  Entries made in a Deload week are not counted: they are lighter on
  purpose, and the week after would step up from them.
  """
  def next_target(rule, logs, block)

  def next_target(_rule, _logs, %{phase: phase}) when phase in ["Setup", "Baseline"], do: nil
  def next_target(%{increment: inc}, _logs, _block) when inc <= 0, do: nil

  def next_target(%{} = rule, logs, %{} = block) do
    case usable(logs, block) do
      [] -> nil
      [last | _] = entries -> target(rule, last, entries, block)
    end
  end

  def next_target(_rule, _logs, _block), do: nil

  @doc "The entries a progression reads: parsed, newest first, with reps, none from a deload."
  def usable(logs, block) do
    logs
    |> Enum.reject(&deload_entry?(&1, block))
    |> Enum.map(&parse_log_metrics(&1.metrics))
    |> Enum.filter(&is_integer(&1.reps))
  end

  @doc "A target in a line: `3 x 8 @ 190 lbs`, or `3 x 10` at bodyweight."
  def target_line(%{sets: s, reps: r, weight: nil}), do: "#{s} x #{r}"
  def target_line(%{sets: s, reps: r, weight: w}), do: "#{s} x #{r} @ #{format_lbs(w)} lbs"

  @doc """
  The admin's line under a lift on the day page:
  `Last: 3×8 @ 30 lbs → Target: 3×9 @ 30 lbs · +5 lbs when all sets hit 10`.
  Nil when there is no entry yet and no target.
  """
  def hint(rule, last, target, block) do
    last_part = last && "Last: " <> session_line(last)

    target_part =
      cond do
        target ->
          "Target: " <> String.replace(target_line(target), " x ", "×") <> rule_note(rule, target)

        block && block.phase in ["Setup", "Baseline"] ->
          "#{block.phase}: find a weight that leaves 3 in reserve (RPE 7)"

        true ->
          nil
      end

    case Enum.reject([last_part, target_part], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " → ")
    end
  end

  defp session_line(%{sets: s, reps: r, weight: w}) do
    work = "#{s || 1}×#{r}"
    if is_number(w), do: work <> " @ #{format_lbs(w)} lbs", else: work
  end

  defp rule_note(_rule, %{reason: :deload}), do: " · deload, the same weight for fewer sets"
  defp rule_note(_rule, %{reason: :cut}), do: " · three misses, 10% off to rebuild"

  defp rule_note(%{increment: inc, high: high}, %{weight: w}) when is_number(w),
    do: " · +#{format_lbs(inc * 1.0)} lbs when all sets hit #{high}"

  defp rule_note(%{high: high}, _target), do: " · add weight when all sets hit #{high}"

  defp target(rule, _last, entries, %{phase: "Deload"}) do
    # The heaviest of the last three, so a light day before the deload
    # does not make it lighter still. About 60% of the volume, by sets.
    recent = Enum.take(entries, 3)
    weights = for %{weight: w} <- recent, is_number(w), do: w
    sets = recent |> Enum.map(&(&1.sets || 3)) |> Enum.max()

    %{
      sets: max(1, round(sets * 0.6)),
      reps: rule.low,
      weight: if(weights == [], do: nil, else: Enum.max(weights)),
      reason: :deload
    }
  end

  defp target(rule, last, entries, block) do
    sets = last.sets || 3
    top_rpe = Map.get(block, :top_set_rpe, 8.0)
    misses = Enum.take_while(entries, &(&1.reps < rule.low)) |> length()
    # is_number first: nil sorts above every number, so `nil >= 9.5` holds.
    grinding =
      match?(
        [%{rpe: a}, %{rpe: b} | _] when is_number(a) and is_number(b) and a >= 9.5 and b >= 9.5,
        entries
      )

    weight = last.weight

    cond do
      misses >= 3 and is_number(weight) ->
        %{sets: sets, reps: rule.low, weight: round5(weight * 0.9), reason: :cut}

      misses > 0 or grinding ->
        %{sets: sets, reps: rule.low, weight: weight, reason: :hold}

      last.reps >= rule.high and (last.rpe || 8) <= top_rpe and is_number(weight) ->
        %{sets: sets, reps: rule.low, weight: weight + rule.increment, reason: :up}

      true ->
        %{sets: sets, reps: min(last.reps + 1, rule.high), weight: weight, reason: :same}
    end
  end

  defp deload_entry?(%{date: %Date{} = date}, %{phases: phases} = block) do
    Map.get(phases, Web.Fitness.Block.week_of(date, block)) == "Deload"
  end

  defp deload_entry?(_log, _block), do: false

  defp round5(lbs), do: Float.round(lbs / 5) * 5

  defp format_lbs(w) when is_float(w) and w == trunc(w), do: Integer.to_string(trunc(w))
  defp format_lbs(w) when is_float(w), do: :erlang.float_to_binary(w, decimals: 1)
  defp format_lbs(w), do: to_string(w)

  defp weight(text) when is_binary(text) do
    case Regex.run(~r/(\d+(?:\.\d+)?)\s*(kgs?|kilos?|lbs?|pounds?)?/i, text) do
      [_, n | unit] ->
        {value, _} = Float.parse(n)

        if match?([u] when u != "", unit) and String.downcase(hd(unit)) =~ ~r/^k/,
          do: Float.round(value * @kg_to_lb, 1),
          else: value

      _ ->
        nil
    end
  end

  defp weight(_), do: nil

  defp count(text) when is_binary(text) do
    case Integer.parse(String.trim(text)) do
      {n, _} when n > 0 -> n
      _ -> nil
    end
  end

  defp count(_), do: nil

  defp rpe(text) when is_binary(text) do
    case Float.parse(String.trim(text)) do
      {n, _} when n >= 1 and n <= 10 -> n
      _ -> nil
    end
  end

  defp rpe(_), do: nil

  defp sets_reps(text) when is_binary(text) do
    cond do
      m = Regex.run(~r/(\d+)\s*[x×]\s*(\d+)/iu, text) ->
        [_, s, r] = m
        {String.to_integer(s), String.to_integer(r)}

      m = Regex.run(~r/(\d+)\s*reps?\b/i, text) ->
        {nil, String.to_integer(Enum.at(m, 1))}

      true ->
        {nil, nil}
    end
  end

  defp sets_reps(_), do: {nil, nil}
end
