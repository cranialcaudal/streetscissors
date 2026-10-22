defmodule Web.Fitness.Export do
  @moduledoc """
  The training log as CSV for R: one row per entry, the admin's
  `/fitness/export/csv` and `mix fitness.export` both.

  The first twelve columns are the ones the export always had, unchanged
  (R code reads them by name and position). Six follow, from the Get Sharp
  block's structured log (`Web.Fitness.Progression`): the wiki slug, sets,
  reps, RPE, Epley's e1RM and the volume load, all in pounds. A value that
  is not there is `NA`, as R reads it. `checkins_csv/2` is the check-ins
  in the same manner, a column per check, and `rides_csv/1` the Komoot
  rides, which stand for the cycling stats.
  """

  alias Web.Fitness.Progression

  # Exercises of the old Saturday and one-shot plans, never part of a trend.
  @excluded ~w(thoracic-extension supine-neck-release anti-shrug-reset single-arm-prone-y
               wall-clock-isometrics quadruped-scap-pushups suitcase-carry scissor-stance-iso
               statue-dead-bug water-walking offset-split-squat 3-point-row pushup-down-dog)

  @headers ~w(date week_num year quarter month exercise_name muscle_group weight_lbs
              distance_miles time_str height_result notes
              exercise_slug sets reps rpe e1rm_lbs volume_load_lbs)

  def headers, do: @headers

  @ride_headers ~w(date week_num year quarter month weekday start_local sport kind tt
                   distance_miles duration_min moving_min avg_mph ascent_ft kcal
                   avg_hr max_hr)

  def ride_headers, do: @ride_headers

  @doc """
  Komoot activities (`Web.Rides.list_rides/0`, Apple Health attached) as CSV
  text, header first, oldest first: Komoot's figures stand for the cycling
  stats. The date and `start_local` are Pacific. `kind` is the sport's family
  (`bike`, `run`, `hike`, `other`), so R can keep to the bike. `tt` is `TRUE`
  for a bike ride that is the week's time trial: one on a Thursday before
  9 AM (the regimen's TT ride in), or any whose Komoot name says TT or time
  trial. The tour's name and route are not written out. Miles, feet and mph,
  as the log's distances are; an unrecorded figure is `NA`.
  """
  def rides_csv(rides) do
    rows =
      rides
      |> Enum.sort_by(&DateTime.to_unix(&1.started_at))
      |> Enum.map(&ride_row/1)

    encode([@ride_headers | rows])
  end

  defp ride_row(ride) do
    local = Web.Clock.local_naive(ride.started_at)
    date = NaiveDateTime.to_date(local)
    {year, week} = :calendar.iso_week_number(Date.to_erl(date))
    kind = Web.Rides.Units.sport_kind(ride.sport)
    health = ride.health

    [
      date,
      week,
      year,
      div(date.month - 1, 3) + 1,
      date.month,
      Calendar.strftime(date, "%a"),
      Calendar.strftime(local, "%H:%M"),
      ride.sport || "NA",
      kind,
      kind == "bike" and tt?(ride, date, local),
      scaled(ride.distance_m, 1 / 1609.344),
      scaled(ride.duration_s, 1 / 60),
      scaled(ride.time_in_motion_s, 1 / 60),
      scaled(ride.avg_speed_mps, 2.23694),
      scaled(ride.ascent_m, 3.28084),
      na(ride.kcal),
      na(health && health.avg_hr),
      na(health && health.max_hr)
    ]
    |> Enum.map(fn
      true -> "TRUE"
      false -> "FALSE"
      v -> v
    end)
  end

  defp tt?(ride, date, local) do
    (Date.day_of_week(date) == 4 and local.hour < 9) or
      String.match?(ride.name || "", ~r/\bTT\b|time.?trial/i)
  end

  defp scaled(nil, _factor), do: "NA"
  defp scaled(value, factor), do: Float.round(value * factor * 1.0, 2)

  @doc "Exercise log entries (exercise loaded) as CSV text, header first."
  def logs_csv(logs) do
    rows =
      logs
      |> Enum.reject(&(&1.exercise.slug in @excluded))
      |> Enum.sort_by(&{Date.to_gregorian_days(&1.date), &1.id})
      |> Enum.map(&row/1)

    encode([@headers | rows])
  end

  @doc """
  Check-ins as CSV text, header first: `date`, one column per check (its
  id, as `Web.Fitness.Checks` makes it), `note`. A check not answered that
  day is `NA`.
  """
  def checkins_csv(checkins, checks) do
    ids = Enum.map(checks, & &1.id)

    rows =
      for c <- Enum.sort_by(checkins, &Date.to_gregorian_days(&1.date)) do
        [c.date] ++ Enum.map(ids, &(c.answers[&1] || "NA")) ++ [c.note || "NA"]
      end

    encode([["date" | ids] ++ ["note"] | rows])
  end

  defp row(log) do
    metrics = log.metrics || %{}
    {year, week} = :calendar.iso_week_number(Date.to_erl(log.date))
    parsed = Progression.parse_log_metrics(metrics)

    [
      log.date,
      week,
      year,
      div(log.date.month - 1, 3) + 1,
      log.date.month,
      log.exercise.name,
      log.exercise.muscle_group,
      numeric(metrics["weight"]),
      numeric(metrics["distance"]),
      metrics["time"] || "NA",
      numeric(metrics["result"]),
      log.note || metrics["note"] || "NA",
      log.exercise.slug,
      na(parsed.sets),
      na(parsed.reps),
      na(parsed.rpe),
      na(Progression.e1rm(parsed.weight, parsed.reps)),
      na(Progression.volume_load(parsed))
    ]
  end

  # "200 lbs" -> "200", as the export always read a value: the digits.
  defp numeric(nil), do: "NA"

  defp numeric(value) do
    case String.replace(value, ~r/[^\d\.]/, "") do
      "" -> "NA"
      digits -> digits
    end
  end

  defp na(nil), do: "NA"
  defp na(v), do: v

  defp encode(rows) do
    rows
    |> Enum.map(fn row -> Enum.map_join(row, ",", &field/1) end)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp field(nil), do: ""

  defp field(val) when is_binary(val) do
    if String.contains?(val, [",", "\"", "\n"]),
      do: "\"" <> String.replace(val, "\"", "\"\"") <> "\"",
      else: val
  end

  defp field(val), do: to_string(val)
end
