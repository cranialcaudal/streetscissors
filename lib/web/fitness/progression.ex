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
  there is nothing to aim at (the Baseline week, a lift with no step, no
  entry with a weight and reps yet).

  `rule` is the block's lift (`Web.Fitness.Block.lift/2`), `logs` its
  entries newest first, `block` the running block from
  `Web.Fitness.Block.current/1`. Entries made in a Deload week are not
  counted: they are lighter on purpose, and the week after would step up
  from them.
  """
  def next_target(rule, logs, block)

  def next_target(_rule, _logs, %{phase: "Baseline"}), do: nil
  def next_target(%{increment: inc}, _logs, _block) when inc <= 0, do: nil

  def next_target(%{} = rule, logs, %{} = block) do
    entries =
      logs
      |> Enum.reject(&deload_entry?(&1, block))
      |> Enum.map(&parse_log_metrics(&1.metrics))
      |> Enum.filter(&(is_number(&1.weight) and is_integer(&1.reps)))

    case entries do
      [] -> nil
      [last | _] = entries -> target(rule, last, entries, block.phase)
    end
  end

  def next_target(_rule, _logs, _block), do: nil

  @doc "A target in a line: `3 x 8 @ 190 lbs`."
  def target_line(%{sets: s, reps: r, weight: w}), do: "#{s} x #{r} @ #{format_lbs(w)} lbs"

  defp target(rule, _last, entries, "Deload") do
    # The heaviest of the last three, so a light day before the deload
    # does not make it lighter still.
    heaviest = entries |> Enum.take(3) |> Enum.map(& &1.weight) |> Enum.max()
    %{sets: 2, reps: rule.low, weight: round5(heaviest * 0.9), reason: :deload}
  end

  defp target(rule, last, entries, phase) do
    sets = last.sets || 3
    misses = Enum.take_while(entries, &(&1.reps < rule.low)) |> length()
    # is_number first: nil sorts above every number, so `nil >= 9.5` holds.
    grinding =
      match?(
        [%{rpe: a}, %{rpe: b} | _] when is_number(a) and is_number(b) and a >= 9.5 and b >= 9.5,
        entries
      )

    base =
      cond do
        misses >= 3 ->
          %{sets: sets, reps: rule.low, weight: round5(last.weight * 0.9), reason: :cut}

        misses > 0 or grinding ->
          %{sets: sets, reps: rule.low, weight: last.weight, reason: :hold}

        last.reps >= rule.high and (last.rpe || 8) <= 8 ->
          %{sets: sets, reps: rule.low, weight: last.weight + rule.increment, reason: :up}

        true ->
          %{sets: sets, reps: min(last.reps + 1, rule.high), weight: last.weight, reason: :same}
      end

    # The Test week is one top set at the weight the rule arrived at.
    if phase == "Test", do: %{base | sets: 1, reason: :test}, else: base
  end

  defp deload_entry?(%{date: %Date{} = date}, %{start: start, phases: phases}) do
    week = div(Date.diff(date, start), 7) + 1
    Map.get(phases, week) == "Deload"
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
