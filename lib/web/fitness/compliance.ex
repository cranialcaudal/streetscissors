defmodule Web.Fitness.Compliance do
  @moduledoc """
  The block week as done against planned, for the admin's day strip: each
  day of `week.md` scored from what it holds, and the week's sessions counted
  by discipline.

  A day's sessions are graded by kind:

    * **strength**: the day's planned sets of its lifts (`Prescription`
      lines of kind weight or reps) against the sets logged that date;
    * **bike**: a Komoot ride that date on a road or touring bike;
    * **run**: a Komoot run that date, or a logged walk-run;
    * **swim**: a logged swim (an entry for one of the day's swim lines).

  Work, courts and stretching are not graded. A day's score is the mean of
  its graded sessions; a day with none has no score. `status/2` turns a
  score into the strip's colour.
  """

  alias Web.Fitness.{Entry, Prescription, Week}

  @bikes ~w(racebike touringbicycle)
  @graded [:strength, :bike, :run, :swim]

  @doc """
  The week of `block` (the running one, from `Web.Fitness.Block.current/1`)
  as `%{days: %{slug => %{date, score, status, sessions}}, totals: %{kind =>
  {done, planned}}}`, or nil without a block or a week.
  """
  def week(nil, _today), do: nil

  def week(%{start: start, week: n}, today) do
    with {:ok, week} <- Week.load() do
      monday = Date.add(start, (n - 1) * 7)
      dates = Date.range(monday, Date.add(monday, 6))
      logs = Web.Fitness.list_exercise_logs() |> Enum.filter(&(&1.date in dates))

      rides =
        Web.Rides.list_rides() |> Enum.filter(&(Web.Clock.local_today(&1.started_at) in dates))

      days =
        for {day, i} <- Enum.with_index(week.days), into: %{} do
          date = Date.add(monday, day_index(day.slug, i))
          on = Enum.filter(logs, &(&1.date == date))
          rode = Enum.filter(rides, &(Web.Clock.local_today(&1.started_at) == date))

          sessions =
            for block <- day.blocks, block.kind in @graded do
              {block.kind, grade(block.kind, day.slug, on, rode)}
            end

          score =
            if sessions == [],
              do: nil,
              else: Enum.sum(Enum.map(sessions, &elem(&1, 1))) / length(sessions)

          {day.slug,
           %{
             date: date,
             score: score,
             status: status(score, Date.compare(date, today)),
             sessions: sessions
           }}
        end

      totals =
        for kind <- @graded, into: %{} do
          graded = days |> Map.values() |> Enum.filter(&(Date.compare(&1.date, today) != :gt))
          planned = for d <- Map.values(days), {^kind, _} <- d.sessions, do: 1
          done = for d <- graded, {^kind, g} <- d.sessions, g >= 0.8, do: 1
          {kind, {length(done), length(planned)}}
        end

      %{days: days, totals: totals}
    else
      _ -> nil
    end
  end

  @weekdays ~w(monday tuesday wednesday thursday friday saturday sunday)
  defp day_index(slug, fallback), do: Enum.find_index(@weekdays, &(&1 == slug)) || fallback

  @doc false
  def grade(:strength, day_slug, logs, _rides) do
    lifts = day_slug |> Prescription.for_day() |> Enum.filter(&(&1.kind in [:weight, :reps]))
    planned = lifts |> Enum.map(&(&1.sets || 3)) |> Enum.sum()

    done =
      for p <- lifts do
        sets =
          logs
          |> Enum.filter(&(&1.exercise.slug == p.slug))
          |> Enum.map(&length(Entry.set_list(&1.metrics)))
          |> Enum.sum()

        min(sets, p.sets || 3)
      end
      |> Enum.sum()

    if planned == 0, do: 0.0, else: done / planned
  end

  def grade(:bike, _day, _logs, rides),
    do: if(Enum.any?(rides, &(&1.sport in @bikes)), do: 1.0, else: 0.0)

  def grade(:run, day_slug, logs, rides) do
    # the run itself, logged by its minutes; a stretch after it is not a run
    run_slugs =
      day_slug
      |> Prescription.for_day()
      |> Enum.filter(&(&1.kind == :timed))
      |> Enum.map(& &1.slug)

    if Enum.any?(rides, &(&1.sport == "jogging")) or
         Enum.any?(logs, &(&1.exercise.slug in run_slugs)),
       do: 1.0,
       else: 0.0
  end

  def grade(:swim, day_slug, logs, _rides) do
    swim_slugs =
      day_slug
      |> Prescription.for_day()
      |> Enum.filter(&(&1.kind in [:laps, :swim, :trial]))
      |> Enum.map(& &1.slug)

    if Enum.any?(logs, &(&1.exercise.slug in swim_slugs)), do: 1.0, else: 0.0
  end

  @doc """
  A day's colour: `:ahead` for a day still to come, `:rest` for one with
  nothing graded, else `:done` (80% or more), `:part` (50% or more) or
  `:missed`. Today is `:today` until it reaches `:done`.
  """
  def status(_score, :gt), do: :ahead
  def status(nil, _when), do: :rest
  def status(score, _when) when score >= 0.8, do: :done
  def status(_score, :eq), do: :today
  def status(score, _when) when score >= 0.5, do: :part
  def status(_score, _when), do: :missed
end
