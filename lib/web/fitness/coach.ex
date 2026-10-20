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
      hint: if(stopped?, do: nil, else: hint(rule, last_log, last, target, block)),
      defaults: defaults(prescription, last, target)
    }
  end

  # The block's own line for a tracked lift; for anything else, the last time.
  defp hint(nil, nil, _last, _target, _block), do: nil

  defp hint(nil, log, _last, _target, _block),
    do: "Last, #{Calendar.strftime(log.date, "%-d %b")}: #{Fitness.entry_line(log)}"

  defp hint(rule, _log, last, target, block), do: Progression.hint(rule, last, target, block)

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
      metres: p.metres
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
