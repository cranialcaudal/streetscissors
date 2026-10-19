defmodule Web.Fitness.Export do
  @moduledoc """
  The training log as CSV for R: one row per entry, the admin's
  `/fitness/export/csv` and `mix fitness.export` both.

  The first twelve columns are the ones the export always had, unchanged
  (R code reads them by name and position). Six follow, from the Get Sharp
  block's structured log (`Web.Fitness.Progression`): the wiki slug, sets,
  reps, RPE, Epley's e1RM and the volume load, all in pounds. A value that
  is not there is `NA`, as R reads it. `checkins_csv/1` is the check-ins
  in the same manner.
  """

  alias Web.Fitness.Progression

  # Exercises of the old Saturday and one-shot plans, never part of a trend.
  @excluded ~w(thoracic-extension supine-neck-release anti-shrug-reset single-arm-prone-y
               wall-clock-isometrics quadruped-scap-pushups suitcase-carry scissor-stance-iso
               statue-dead-bug water-walking offset-split-squat 3-point-row pushup-down-dog)

  @headers ~w(date week_num year quarter month exercise_name muscle_group weight_lbs
              distance_miles time_str height_result notes
              exercise_slug sets reps rpe e1rm_lbs volume_load_lbs)

  @checkin_headers ~w(date pain sleep_hours soreness energy note)

  def headers, do: @headers

  @doc "Exercise log entries (exercise loaded) as CSV text, header first."
  def logs_csv(logs) do
    rows =
      logs
      |> Enum.reject(&(&1.exercise.slug in @excluded))
      |> Enum.sort_by(&{Date.to_gregorian_days(&1.date), &1.id})
      |> Enum.map(&row/1)

    encode([@headers | rows])
  end

  @doc "Check-ins as CSV text, header first."
  def checkins_csv(checkins) do
    rows =
      for c <- Enum.sort_by(checkins, &Date.to_gregorian_days(&1.date)) do
        [c.date, na(c.pain), na(c.sleep_hours), na(c.soreness), na(c.energy), c.note || "NA"]
      end

    encode([@checkin_headers | rows])
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
