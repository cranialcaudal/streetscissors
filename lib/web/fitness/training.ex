defmodule Web.Fitness.Training do
  @moduledoc """
  The numbers a block is judged by, worked out from its log entries: e1RM
  per lift, volume load per movement pattern, how many of the planned
  strength days were trained, and the acute:chronic load ratio.

  Everything here is a pure function of the entries (`entries/2`) and the
  block (`Web.Fitness.Block`), so the charts, the guardrails and the block
  report read one set of figures. Only a block's own lifts count toward a
  pattern: they are the ones the block file gives a pattern.
  Each function says how its figure is worked out.
  """

  alias Web.Fitness
  alias Web.Fitness.{Block, Checks, Prescription, Progression}

  @patterns ~w(hinge squat push pull plyo_locomotion)

  @doc "The movement patterns a block lift may count toward, in chart order."
  def patterns, do: @patterns

  @doc """
  Log entries as figures, oldest first: `%{id, date, slug, name, weight,
  sets, reps, rpe, e1rm, volume, pattern}`. `pattern` is the block lift's,
  nil for an exercise the block does not track.
  """
  def entries(logs, block \\ nil) do
    logs
    |> Enum.map(fn log ->
      parsed = Progression.parse_log_metrics(log.metrics)
      rule = Block.lift(block, log.exercise.slug)

      Map.merge(parsed, %{
        id: log.id,
        date: log.date,
        slug: log.exercise.slug,
        name: log.exercise.name,
        e1rm: Progression.e1rm(parsed.weight, parsed.reps),
        volume: Progression.volume_load(parsed),
        pattern: rule && rule.pattern
      })
    end)
    |> Enum.sort_by(&{Date.to_gregorian_days(&1.date), &1.id})
  end

  @doc "Every entry on file as figures, for the running block's lifts."
  def all_entries(block), do: entries(Fitness.list_exercise_logs(), block)

  @doc "A block's entries only: dated inside it, its setup week included."
  def in_block(entries, %{finish: finish} = block) do
    opens = Map.get(block, :opens, block.start)

    Enum.filter(
      entries,
      &(Date.compare(&1.date, opens) != :lt and Date.compare(&1.date, finish) != :gt)
    )
  end

  @doc "The block week a date falls in (1-based; may be outside 1..weeks)."
  def week_of(%Date{} = date, block), do: Block.week_of(date, block)

  @doc """
  The weeks of a block that have begun by `today`: `0..n` when it has a
  setup week, else `1..n`, n at most the block's length.
  """
  def weeks_so_far(block, today) do
    first = if Map.has_key?(block.phases, 0), do: 0, else: 1
    n = today |> week_of(block) |> min(block.weeks) |> max(first)
    Enum.to_list(first..n)
  end

  @doc "A lift's best e1RM per day, oldest first: `[{date, e1rm}]`."
  def e1rm_series(entries, slug) do
    entries
    |> Enum.filter(&(&1.slug == slug and is_number(&1.e1rm)))
    |> Enum.group_by(& &1.date)
    |> Enum.map(fn {date, day} -> {date, day |> Enum.map(& &1.e1rm) |> Enum.max()} end)
    |> Enum.sort_by(&elem(&1, 0), Date)
  end

  @doc "A lift's best e1RM in each block week: `%{week => e1rm}`."
  def e1rm_by_week(entries, block, slug) do
    entries
    |> e1rm_series(slug)
    |> Enum.group_by(fn {date, _} -> week_of(date, block) end, &elem(&1, 1))
    |> Map.new(fn {week, values} -> {week, Enum.max(values)} end)
  end

  @doc "Volume load per pattern per block week: `%{pattern => %{week => lbs}}`."
  def weekly_volume(entries, block) do
    entries
    |> in_block(block)
    |> Enum.filter(&(&1.pattern && is_number(&1.volume)))
    |> Enum.group_by(& &1.pattern)
    |> Map.new(fn {pattern, rows} ->
      {pattern,
       rows
       |> Enum.group_by(&week_of(&1.date, block), & &1.volume)
       |> Map.new(fn {week, vols} -> {week, Float.round(Enum.sum(vols), 1)} end)}
    end)
  end

  @doc """
  The acute:chronic workload ratio for a pattern on a day: the last 7 days'
  volume load over the last 28 days' weekly average. Nil until 28 days of
  entries exist for the pattern, or when the chronic load is nothing.
  """
  def acwr(entries, pattern, %Date{} = date) do
    rows = Enum.filter(entries, &(&1.pattern == pattern and is_number(&1.volume)))

    with [first | _] <- rows,
         true <- Date.diff(date, first.date) >= 27 do
      acute = load_between(rows, Date.add(date, -6), date)
      chronic = load_between(rows, Date.add(date, -27), date) / 4

      if chronic > 0, do: Float.round(acute / chronic, 2)
    else
      _ -> nil
    end
  end

  @doc "ACWR per pattern at the end of each block week: `%{pattern => %{week => ratio | nil}}`."
  def acwr_by_week(entries, block, weeks) do
    Map.new(@patterns, fn pattern ->
      {pattern,
       Map.new(weeks, fn week ->
         {week, acwr(entries, pattern, Date.add(block.start, week * 7 - 1))}
       end)}
    end)
  end

  @doc """
  The plan, weekday by weekday, for the days that carry one of the block's
  lifts (the strength days): `%{iso_weekday => %{slugs, sets, minutes}}`.
  `sets` are the day's prescribed sets (`Prescription.planned_sets/1`);
  `minutes` the lengths written on the sections that hold a block lift
  ("### Lower … (75 Min)").
  """
  def plan(%{lifts: lifts}) do
    ~w(monday tuesday wednesday thursday friday saturday sunday)
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {day, wd} ->
      lines = Prescription.lines(day)

      if Enum.any?(lines, &Map.has_key?(lifts, &1.slug)) do
        minutes =
          lines
          |> Enum.filter(&Map.has_key?(lifts, &1.slug))
          |> Enum.map(& &1.section)
          |> Enum.uniq_by(& &1.title)
          |> Enum.map(&(&1.minutes || 0))
          |> Enum.sum()

        [
          {wd,
           %{
             slugs: MapSet.new(lines, & &1.slug),
             sets: Prescription.planned_sets(lines),
             minutes: minutes
           }}
        ]
      else
        []
      end
    end)
    |> Map.new()
  end

  def plan(_block), do: %{}

  @doc "The ISO weekdays (1 = Monday) whose plan carries a block lift."
  def planned_weekdays(block), do: block |> plan() |> Map.keys() |> Enum.sort()

  @doc """
  Planned against done, week by week: `%{week => %{days_done, days_planned,
  sets_done, sets_planned}}`. A strength day is done when anything on its
  plan was logged that day; its sets done are the logged sets (1 for an
  entry with no count) of exercises on that day's plan, at most the plan's.
  """
  def compliance(entries, block, weeks, plan \\ nil) do
    plan = plan || plan(block)
    by_date = Enum.group_by(in_block(entries, block), & &1.date)

    Map.new(weeks, fn week ->
      days =
        for {wd, day} <- plan do
          date = Date.add(block.start, (week - 1) * 7 + wd - 1)
          logged = Enum.filter(Map.get(by_date, date, []), &MapSet.member?(day.slugs, &1.slug))
          sets = logged |> Enum.map(&(&1.sets || 1)) |> Enum.sum() |> min(day.sets)
          {logged != [], sets, day.sets}
        end

      {week,
       %{
         days_done: Enum.count(days, &elem(&1, 0)),
         days_planned: length(days),
         sets_done: days |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
         sets_planned: days |> Enum.map(&elem(&1, 2)) |> Enum.sum()
       }}
    end)
  end

  @doc """
  Each strength session's stress, RPE × minutes: the mean RPE logged that
  day (7 when none was) times the minutes the plan gives the day's lifting.
  `[{date, stress}]`, oldest first.
  """
  def session_stress(entries, block, plan \\ nil) do
    plan = plan || plan(block)

    entries
    |> in_block(block)
    |> Enum.group_by(& &1.date)
    |> Enum.flat_map(fn {date, rows} ->
      case plan[Date.day_of_week(date)] do
        %{minutes: minutes} when minutes > 0 ->
          rpes = for %{rpe: r} <- rows, is_number(r), do: r
          rpe = if rpes == [], do: 7.0, else: Enum.sum(rpes) / length(rpes)
          [{date, Float.round(rpe * minutes, 1)}]

        _ ->
          []
      end
    end)
    |> Enum.sort_by(&Date.to_gregorian_days(elem(&1, 0)))
  end

  @doc "Stress per block week, and its acute:chronic ratio at each week's end."
  def stress_by_week(entries, block, weeks, plan \\ nil) do
    sessions = session_stress(entries, block, plan)

    rows =
      Enum.map(sessions, fn {date, stress} -> %{date: date, pattern: "stress", volume: stress} end)

    in_week = fn w ->
      sessions
      |> Enum.filter(&(week_of(elem(&1, 0), block) == w))
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()
    end

    {Map.new(weeks, &{&1, in_week.(&1)}),
     Map.new(weeks, &{&1, acwr(rows, "stress", Date.add(block.start, &1 * 7 - 1))})}
  end

  @doc """
  The block report's figures (G.13): a row per week (phase, days and sets
  done of planned, volume, stress, each check's answers, the days the
  check-ins held or stopped it), each lift's e1RM change from its first week
  with a figure to its latest, the hypothesis's predictions against what
  happened, the author's retrospective, and once the last week has begun, a
  sentence answering it. `checkins` are the block's, any order; `checks`
  from `Checks.all/0`.
  """
  def report(entries, block, weeks, checkins, checks, plan \\ nil) do
    plan = plan || plan(block)
    compliance = compliance(entries, block, weeks, plan)
    volume = weekly_volume(entries, block)
    {stress, _} = stress_by_week(entries, block, weeks, plan)
    by_week = Enum.group_by(checkins, &week_of(&1.date, block))
    state_checks = Enum.filter(checks, &(&1.kind == :state))

    rows =
      for week <- weeks do
        cs = Map.get(by_week, week, [])
        c = compliance[week]

        levels =
          for checkin <- cs do
            state_checks
            |> Enum.map(&Checks.level(&1, checkin.answers[&1.id]))
            |> Enum.max_by(&level_rank/1, fn -> :green end)
          end

        %{
          week: week,
          phase: block.phases[week],
          days_done: c.days_done,
          days_planned: c.days_planned,
          sets_done: c.sets_done,
          sets_planned: c.sets_planned,
          volume: volume |> Map.values() |> Enum.map(&Map.get(&1, week, 0)) |> Enum.sum(),
          stress: stress[week],
          checks: Map.new(checks, &{&1.id, summary(&1, cs)}),
          held: Enum.count(levels, &(&1 == :hold)),
          stopped: Enum.count(levels, &(&1 == :stop))
        }
      end

    lifts =
      for {slug, rule} <- Enum.sort_by(block.lifts, &elem(&1, 0)),
          by = e1rm_by_week(entries, block, slug) |> Map.delete(0),
          by != %{} do
        {w0, first} = Enum.min_by(by, &elem(&1, 0))
        {w1, last} = Enum.max_by(by, &elem(&1, 0))

        %{
          slug: slug,
          name: entries |> Enum.find(&(&1.slug == slug)) |> Map.get(:name),
          pattern: rule.pattern,
          from: {w0, first},
          to: {w1, last},
          change: if(w1 > w0, do: Float.round((last - first) / first * 100, 1))
        }
      end

    predictions = predictions(block, rows, lifts, checkins, checks)

    %{
      rows: rows,
      lifts: lifts,
      predictions: predictions,
      answer: answer(block, weeks, predictions, rows),
      retrospective: section(Map.get(block, :body, ""), "Retrospective")
    }
  end

  # How a check went in a week: a state check's answers counted, worst
  # first ("talking 2 · angry 1"); a number check's mean.
  defp summary(%{kind: :state} = check, checkins) do
    counts =
      checkins |> Enum.map(& &1.answers[check.id]) |> Enum.reject(&is_nil/1) |> Enum.frequencies()

    check.states
    |> Enum.reverse()
    |> Enum.filter(&Map.has_key?(counts, &1))
    |> Enum.map_join(" · ", &"#{&1} #{counts[&1]}")
  end

  defp summary(check, checkins) do
    case for(c <- checkins, n = number(c.answers[check.id]), do: n) do
      [] -> ""
      ns -> "#{Float.round(Enum.sum(ns) / length(ns), 1)}#{if check.unit, do: " " <> check.unit}"
    end
  end

  defp level_rank(:stop), do: 2
  defp level_rank(:hold), do: 1
  defp level_rank(_), do: 0

  # The block file's `predict:` lines, each with what happened:
  #   bodyweight  the slope of the bodyweight check, per week;
  #   e1rm        the mean e1RM change across the lifts, first week to latest;
  #   volume      weekly volume, first week of lifting to latest;
  #   compliance  sets done of sets planned over the weeks so far.
  defp predictions(block, rows, lifts, checkins, checks) do
    for p <- Map.get(block, :predict, []) do
      actual =
        case p.measure do
          "bodyweight" -> slope(checkins, Enum.find(checks, &(&1.id == "bodyweight")), block)
          "e1rm" -> mean_of(for(%{change: c} <- lifts, is_number(c), do: c))
          "volume" -> volume_change(rows)
          "compliance" -> compliance_share(rows)
          _ -> nil
        end

      Map.merge(p, %{
        actual: actual && Float.round(actual * 1.0, 2),
        met: is_number(actual) and actual >= p.value
      })
    end
  end

  # Least-squares change per week over the block's numeric answers.
  defp slope(_checkins, nil, _block), do: nil

  defp slope(checkins, check, block) do
    points =
      for c <- checkins,
          n = number(c.answers[check.id]),
          do: {Date.diff(c.date, block.start) / 7, n}

    if length(points) >= 2 do
      {xs, ys} = Enum.unzip(points)
      mx = Enum.sum(xs) / length(xs)
      my = Enum.sum(ys) / length(ys)
      sxx = xs |> Enum.map(&((&1 - mx) * (&1 - mx))) |> Enum.sum()
      sxy = points |> Enum.map(fn {x, y} -> (x - mx) * (y - my) end) |> Enum.sum()
      if sxx > 0, do: sxy / sxx
    end
  end

  defp volume_change(rows) do
    lifted = Enum.filter(rows, &(&1.week > 0 and &1.volume > 0 and &1.phase != "Deload"))

    case {List.first(lifted), List.last(lifted)} do
      {%{week: a, volume: v0}, %{week: b, volume: v1}} when b > a -> (v1 - v0) / v0 * 100
      _ -> nil
    end
  end

  defp compliance_share(rows) do
    {done, planned} =
      rows
      |> Enum.filter(&(&1.week > 0))
      |> Enum.reduce({0, 0}, fn r, {d, p} -> {d + r.sets_done, p + r.sets_planned} end)

    if planned > 0, do: done / planned * 100
  end

  defp mean_of([]), do: nil
  defp mean_of(xs), do: Enum.sum(xs) / length(xs)

  defp number(nil), do: nil

  defp number(text) do
    case Float.parse(to_string(text)) do
      {n, _} -> n
      :error -> nil
    end
  end

  # A `## Heading` section of the block file's prose, or nil when it is
  # missing or holds only a "(Written at the end …)" placeholder.
  defp section(body, heading) do
    case Regex.run(~r/^##\s+#{heading}\s*\n(.*?)(?=^##\s|\z)/ms, body || "") do
      [_, text] ->
        text = String.trim(text)
        if text == "" or text =~ ~r/\A\(.*\)\z/s, do: nil, else: text

      _ ->
        nil
    end
  end

  # Answered only once the last week has begun: the predictions met, and
  # whether the check-ins ever stopped the block.
  defp answer(block, weeks, predictions, rows) do
    if List.last(weeks) == block.weeks do
      judged = Enum.filter(predictions, &is_number(&1.actual))
      met = Enum.count(judged, & &1.met)
      stopped = rows |> Enum.map(& &1.stopped) |> Enum.sum()

      stop_note =
        if stopped > 0,
          do:
            " The check-ins stopped the block on #{stopped} day#{if stopped == 1, do: "", else: "s"}.",
          else: " The check-ins never stopped the block."

      cond do
        judged == [] ->
          "Not enough data to judge the predictions." <> stop_note

        met == length(judged) ->
          "Supported: every prediction met (#{met} of #{length(judged)})." <> stop_note

        met > 0 ->
          "Partly: #{met} of #{length(judged)} predictions met." <> stop_note

        true ->
          "Not supported: no prediction met." <> stop_note
      end
    end
  end

  @doc """
  One exercise's record, for its wiki page: the first and last entries, its
  records (best e1RM, heaviest weight, most reps), lifetime volume load, and
  every entry, newest first. Nil with no entry.
  """
  def history(entries, slug) do
    case Enum.filter(entries, &(&1.slug == slug)) do
      [] ->
        nil

      rows ->
        best = rows |> Enum.filter(&is_number(&1.e1rm)) |> Enum.max_by(& &1.e1rm, fn -> nil end)

        heaviest =
          rows |> Enum.filter(&is_number(&1.weight)) |> Enum.max_by(& &1.weight, fn -> nil end)

        most_reps =
          rows |> Enum.filter(&is_integer(&1.reps)) |> Enum.max_by(& &1.reps, fn -> nil end)

        %{
          count: length(rows),
          first: hd(rows),
          last: List.last(rows),
          best: best,
          heaviest: heaviest,
          most_reps: most_reps,
          volume: rows |> Enum.map(&(&1.volume || 0)) |> Enum.sum() |> Float.round(0),
          recent: Enum.reverse(rows),
          series: e1rm_series(rows, slug)
        }
    end
  end

  defp load_between(rows, from, to) do
    rows
    |> Enum.filter(&(Date.compare(&1.date, from) != :lt and Date.compare(&1.date, to) != :gt))
    |> Enum.map(& &1.volume)
    |> Enum.sum()
  end
end
