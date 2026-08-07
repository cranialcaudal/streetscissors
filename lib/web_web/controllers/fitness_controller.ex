defmodule WebWeb.FitnessController do
  use WebWeb, :controller
  alias Web.Fitness

  def export_csv(conn, _params) do
    if get_session(conn, "admin_user") == true do
      logs = Fitness.list_exercise_logs()

      # Define excluded exercises (Saturday and One-Shot specific)
      excluded_slugs = [
        # Saturday
        "thoracic-extension",
        "supine-neck-release",
        "anti-shrug-reset",
        "single-arm-prone-y",
        "wall-clock-isometrics",
        "quadruped-scap-pushups",
        "suitcase-carry",
        "scissor-stance-iso",
        "statue-dead-bug",
        "water-walking",
        # One-Shot (unique ones)
        "offset-split-squat",
        "3-point-row",
        "pushup-down-dog"
      ]

      # Define the CSV headers optimized for R
      # Using snake_case for R column names is standard practice
      headers = [
        "date",
        "week_num",
        "year",
        "quarter",
        "month",
        "exercise_name",
        "muscle_group",
        "weight_lbs",
        "distance_miles",
        "time_str",
        "height_result",
        "notes"
      ]

      # Map logs to rows (filtering out excluded exercises)
      rows =
        logs
        |> Enum.filter(fn log -> log.exercise.slug not in excluded_slugs end)
        |> Enum.map(fn log ->
          metrics = log.metrics || %{}

          # Calculate date components for grouping
          # :calendar.iso_week_number returns {year, week}
          {year, week} = :calendar.iso_week_number({log.date.year, log.date.month, log.date.day})
          quarter = div(log.date.month - 1, 3) + 1
          month = log.date.month

          # Extract numeric values where possible for R analysis
          # "200 lbs" -> "200", MISSING -> "NA"
          extract_numeric = fn val ->
            if val do
              cleaned = String.replace(val, ~r/[^\d\.]/, "")
              if cleaned == "", do: "NA", else: cleaned
            else
              "NA"
            end
          end

          weight_val = extract_numeric.(metrics["weight"])
          dist_val = extract_numeric.(metrics["distance"])
          height_val = extract_numeric.(metrics["result"])

          [
            log.date,
            week,
            year,
            quarter,
            month,
            log.exercise.name,
            log.exercise.muscle_group,
            weight_val,
            dist_val,
            metrics["time"] || "NA",
            height_val,
            log.note || metrics["note"] || "NA"
          ]
        end)

      csv_content =
        [headers | rows]
        |> Enum.map(fn row ->
          Enum.map(row, &escape_csv_field/1)
          |> Enum.join(",")
        end)
        |> Enum.join("\n")

      filename = "fitness_progress_#{Date.to_string(Date.utc_today())}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s[attachment; filename="#{filename}"])
      |> send_resp(200, csv_content)
    else
      conn
      |> put_flash(:error, "Unauthorized")
      |> redirect(to: "/")
    end
  end

  def export_biometrics_csv(conn, _params) do
    if get_session(conn, "admin_user") == true do
      # Fetch all biometrics sorted by date desc
      biometrics = Fitness.list_biometrics()

      headers = [
        "date",
        "weight_lbs",
        "bmi",
        "body_fat_percent",
        "sleep_hours",
        "protein_grams",
        "water_oz",
        "resting_hr",
        "screentime_hours"
      ]

      rows =
        biometrics
        |> Enum.map(fn b ->
          # Calculate BMI if weight is present
          bmi_val =
            if b.weight_lbs do
              w = Decimal.to_float(b.weight_lbs)
              (w * 703 / (69 * 69)) |> Float.round(1)
            else
              "NA"
            end

          [
            b.date,
            b.weight_lbs || "NA",
            bmi_val,
            b.body_fat_percentage || "NA",
            b.sleep_hours || "NA",
            b.protein_grams || "NA",
            b.water_oz || "NA",
            b.resting_hr || "NA",
            b.screentime_hours || "NA"
          ]
        end)

      csv_content =
        [headers | rows]
        |> Enum.map(fn row ->
          Enum.map(row, &escape_csv_field/1)
          |> Enum.join(",")
        end)
        |> Enum.join("\n")

      filename = "biometrics_log_#{Date.to_string(Date.utc_today())}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s[attachment; filename="#{filename}"])
      |> send_resp(200, csv_content)
    else
      conn
      |> put_flash(:error, "Unauthorized")
      |> redirect(to: "/fitness")
    end
  end

  defp escape_csv_field(nil), do: ""

  defp escape_csv_field(val) when is_binary(val) do
    if String.contains?(val, [",", "\"", "\n"]) do
      "\"" <> String.replace(val, "\"", "\"\"") <> "\""
    else
      val
    end
  end

  defp escape_csv_field(val), do: to_string(val)
end
