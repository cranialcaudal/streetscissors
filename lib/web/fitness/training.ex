defmodule Web.Fitness.Training do
  @moduledoc """
  The numbers a block is judged by, worked out from its log entries: e1RM
  per lift, volume load per movement pattern, how many of the planned
  strength days were trained, and the acute:chronic load ratio.

  Everything here is a pure function of the entries (`entries/2`) and the
  block (`Web.Fitness.Block`), so the charts, the guardrails and the block
  report read one set of figures. Only a block's own lifts count toward a
  pattern: they are the ones the block file gives a pattern.
  `docs/get-sharp-handoff.md` §3.1 defines each figure.
  """

  alias Web.Fitness
  alias Web.Fitness.{Block, Progression, Vault}

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

  @doc "A block's entries only: dated inside it."
  def in_block(entries, %{start: start, finish: finish}) do
    Enum.filter(
      entries,
      &(Date.compare(&1.date, start) != :lt and Date.compare(&1.date, finish) != :gt)
    )
  end

  @doc "The block week a date falls in (1-based; may be outside 1..weeks)."
  def week_of(%Date{} = date, %{start: start}), do: div(Date.diff(date, start), 7) + 1

  @doc """
  The weeks of a block that have begun by `today`: `1..n`, where n is at
  most the block's length and at least 1.
  """
  def weeks_so_far(block, today) do
    n = today |> week_of(block) |> min(block.weeks) |> max(1)
    Enum.to_list(1..n)
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
  The strength days trained each week against the days planned:
  `%{week => {done, planned}}`. A planned day is a weekday whose regimen
  page has a Log button for one of the block's lifts; a day is done when
  any block lift was logged on it.
  """
  def compliance(entries, block, weeks, planned \\ nil) do
    planned = planned || planned_weekdays(block)

    done_days =
      entries
      |> in_block(block)
      |> Enum.filter(& &1.pattern)
      |> Enum.map(& &1.date)
      |> MapSet.new()

    Map.new(weeks, fn week ->
      days = for wd <- planned, do: Date.add(block.start, (week - 1) * 7 + wd - 1)
      {week, {Enum.count(days, &MapSet.member?(done_days, &1)), length(days)}}
    end)
  end

  @doc "The ISO weekdays (1 = Monday) whose regimen page carries a block lift."
  def planned_weekdays(%{lifts: lifts}) do
    ~w(monday tuesday wednesday thursday friday saturday sunday)
    |> Enum.with_index(1)
    |> Enum.filter(fn {day, _} ->
      case Vault.get_day(day) do
        {:ok, html} ->
          ~r/phx-value-slug="([a-z0-9-]+)"/
          |> Regex.scan(html, capture: :all_but_first)
          |> List.flatten()
          |> Enum.any?(&Map.has_key?(lifts, &1))

        _ ->
          false
      end
    end)
    |> Enum.map(&elem(&1, 1))
  end

  @doc """
  One exercise's record, for its wiki page: the first and last entries, the
  best e1RM and when, and the latest five, newest first. Nil with no entry.
  """
  def history(entries, slug) do
    case Enum.filter(entries, &(&1.slug == slug)) do
      [] ->
        nil

      rows ->
        best = rows |> Enum.filter(&is_number(&1.e1rm)) |> Enum.max_by(& &1.e1rm, fn -> nil end)

        %{
          count: length(rows),
          first: hd(rows),
          last: List.last(rows),
          best: best,
          recent: rows |> Enum.reverse() |> Enum.take(5),
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
