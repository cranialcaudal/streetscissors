defmodule Web.Fitness.Coach do
  @moduledoc """
  Each exercise on a day, as the admin's page needs it: what the plan asks
  (`Web.Fitness.Prescription`), the block's rule for it if the block tracks
  it, the last entry, the next target with the guardrails applied, the line
  shown under it on the page, and what the log form starts from.

  Read once when the day's page mounts, from the plan, the logs, the
  check-ins and the block, so the line under an exercise and the form that
  logs it never disagree.
  """

  alias Web.Fitness
  alias Web.Fitness.{Block, Checks, Guardrails, Prescription, Progression, Training}

  @doc "The day's exercises, `%{slug => plan}`, for the admin on `date`."
  def day(day_slug, %Date{} = date, block) do
    logs = Fitness.list_exercise_logs()

    by_slug =
      logs
      |> Enum.group_by(& &1.exercise.slug)
      |> Map.new(fn {s, ls} -> {s, newest_first(ls)} end)

    entries = Training.entries(logs, block)
    checkins = Fitness.recent_checkins(date)
    checks = Checks.all()

    Map.new(Prescription.for_day(day_slug), fn p ->
      {p.slug, plan(p, Map.get(by_slug, p.slug, []), block, entries, checkins, checks, date)}
    end)
  end

  @doc "One exercise's plan; the prescription may be nil (logged off-plan)."
  def plan(prescription, logs, block, entries, checkins, checks, date) do
    slug = prescription.slug
    rule = Block.lift(block, slug)
    verdict = Guardrails.state(slug, rule, checkins, entries, date, checks)

    {last_log, last} =
      case logs do
        [log | _] -> {log, Progression.parse_log_metrics(log.metrics)}
        [] -> {nil, nil}
      end

    target =
      if rule && block,
        do: rule |> Progression.next_target(logs, block) |> Guardrails.apply_to(rule, verdict)

    stopped? = elem(verdict, 0) == :stop

    %{
      slug: slug,
      prescription: prescription,
      rule: rule,
      last: last,
      target: target,
      verdict: verdict,
      guard: Guardrails.line(verdict),
      instead: if(stopped?, do: Guardrails.substitute(block, slug)),
      hint: if(stopped?, do: nil, else: hint(rule, last_log, last, target, block, prescription)),
      defaults: defaults(prescription, start_from(last, last_log, prescription), target),
      last_line: last_line(logs, date)
    }
  end

  # The session before today's, as the card shows it: "26 Oct: 3 x 3 @ 135 lbs".
  defp last_line(logs, date) do
    case Enum.find(logs, &(Date.compare(&1.date, date) == :lt)) do
      nil -> nil
      log -> "#{Calendar.strftime(log.date, "%-d %b")}: #{Fitness.entry_line(log)}"
    end
  end

  # The block's own line for a tracked lift; for anything else, the last time.
  # A lift done at bodyweight has no weight to find in the first weeks: its
  # start is the clean reps there are.
  defp hint(nil, nil, _last, _target, _block, _p), do: nil

  defp hint(nil, log, _last, _target, _block, _p),
    do: "Last, #{Calendar.strftime(log.date, "%-d %b")}: #{Fitness.entry_line(log)}"

  defp hint(rule, _log, last, target, block, %{kind: :reps}) do
    case Progression.hint(rule, last, target, block) do
      nil ->
        nil

      text ->
        String.replace(
          text,
          "find a weight that leaves 3 in reserve (RPE 7)",
          "log the clean reps there are; they are the start"
        )
    end
  end

  defp hint(rule, _log, last, target, block, _p), do: Progression.hint(rule, last, target, block)

  # A last entry whose top set is short of the plan's reps is no start: a ramp
  # to one heavy rep must not open "2 x 5, light" at that weight. The plan keeps
  # its sets and reps, and the weight is the heaviest set that reached them.
  defp start_from(nil, _log, _prescription), do: nil

  defp start_from(last, log, prescription) do
    planned = plan_reps(prescription.reps)

    if is_integer(planned) and is_integer(last.reps) and last.reps < planned,
      do: %{last | sets: nil, reps: nil, weight: heaviest_at(log, planned) || last.weight},
      else: last
  end

  defp heaviest_at(%{metrics: %{"set_list" => sets}}, reps) when is_list(sets) do
    sets
    |> Enum.filter(&(is_number(&1["w"]) and is_integer(&1["r"]) and &1["r"] >= reps))
    |> Enum.map(& &1["w"])
    |> Enum.max(fn -> nil end)
  end

  defp heaviest_at(_log, _reps), do: nil

  @doc """
  What the form starts from: the target, else the last entry, else the plan.
  `%{sets, reps, weight, rpe, seconds, metres, height}`, any of them nil.
  """
  def defaults(p, last, target) do
    from_plan = %{
      sets: p.sets,
      reps: plan_reps(p.reps),
      weight: p.weight,
      seconds: p.seconds,
      metres: p.metres,
      yards: Map.get(p, :yards)
    }

    from_last =
      if last,
        do: %{sets: last.sets, reps: last.reps, weight: last.weight},
        else: %{}

    from_target =
      if target,
        do: %{sets: target.sets, reps: target.reps, weight: target.weight},
        else: %{}

    Enum.reduce(
      [from_last, from_target],
      Map.merge(%{rpe: nil, height: nil}, from_plan),
      fn layer, acc ->
        Map.merge(acc, Map.reject(layer, fn {_, v} -> is_nil(v) end))
      end
    )
  end

  defp plan_reps({low, _high}), do: low
  defp plan_reps(_), do: nil

  defp newest_first(logs),
    do: Enum.sort_by(logs, &{Date.to_gregorian_days(&1.date), &1.id}, :desc)
end
