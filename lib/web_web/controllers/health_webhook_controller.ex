defmodule WebWeb.HealthWebhookController do
  use WebWeb, :controller

  alias Web.Fitness

  # Health Auto Export metric names → biometric field + unit conversion
  @metric_map %{
    "heart_rate_variability_sdnn" => {:hrv_ms, :round},
    "resting_heart_rate" => {:resting_hr, :round},
    "active_energy_burned" => {:active_calories, :round},
    "vo2_max" => {:vo2_max, :float},
    "oxygen_saturation" => {:spo2_percent, :float},
    "respiratory_rate" => {:respiratory_rate, :float},
    "body_mass" => {:weight_lbs, :kg_to_lbs},
    "dietary_protein" => {:protein_grams, :round},
    "dietary_water" => {:water_oz, :ml_to_oz},
    "sleep_analysis" => {:sleep_hours, :sleep_duration}
  }

  def ingest(conn, params) do
    with :ok <- check_token(conn),
         {:ok, entries} <- parse_payload(params) do
      results = Enum.map(entries, &Fitness.upsert_biometric/1)
      ok = Enum.count(results, &match?({:ok, _}, &1))
      json(conn, %{ok: ok, total: length(results)})
    else
      :unauthorized ->
        conn |> put_status(401) |> json(%{error: "unauthorized"})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: inspect(reason)})
    end
  end

  defp check_token(conn) do
    expected =
      case Web.SiteSettings.get_setting("health_webhook_token") do
        t when is_binary(t) and t != "" -> t
        _ -> Application.get_env(:web, :health_webhook_token)
      end

    case {expected, get_req_header(conn, "authorization")} do
      {e, ["Bearer " <> t]} when is_binary(e) and e != "" and t == e -> :ok
      _ -> :unauthorized
    end
  end

  # Health Auto Export: {data: {metrics: [{name, units, data: [{date, qty}]}]}}
  defp parse_payload(%{"data" => %{"metrics" => metrics}}) do
    by_date =
      Enum.reduce(metrics, %{}, fn metric, acc ->
        parse_metric(metric, acc)
      end)

    entries = Enum.map(by_date, fn {date, fields} -> Map.put(fields, "date", date) end)
    {:ok, entries}
  end

  # iOS Shortcuts flat format: {"date": "2026-06-13", "hrv_ms": 45, "sleep_hours": 7.5, ...}
  @flat_fields ~w(hrv_ms resting_hr active_calories vo2_max spo2_percent
                  respiratory_rate weight_lbs protein_grams water_oz
                  sleep_hours soreness energy)

  defp parse_payload(%{"date" => _} = flat) do
    entry = Map.take(flat, ["date" | @flat_fields])
    {:ok, [entry]}
  end

  defp parse_payload(_), do: {:error, "unexpected payload shape"}

  defp parse_metric(%{"name" => name, "data" => data_points}, acc) do
    case Map.get(@metric_map, name) do
      nil ->
        acc

      {field, converter} ->
        Enum.reduce(data_points, acc, fn point, inner ->
          with date when is_binary(date) <- extract_date(point["date"]),
               value when not is_nil(value) <- convert(point["qty"], converter) do
            update_in(inner, [Access.key(date, %{})], &Map.put(&1, Atom.to_string(field), value))
          else
            _ -> inner
          end
        end)
    end
  end

  defp parse_metric(_, acc), do: acc

  defp extract_date(nil), do: nil

  defp extract_date(str) when is_binary(str) do
    # "2026-01-15 07:30:00 -0800" → "2026-01-15"
    case String.split(str, " ") do
      [date | _] when byte_size(date) == 10 -> date
      _ -> nil
    end
  end

  defp convert(nil, _), do: nil
  defp convert(v, :round), do: round(v * 1.0)
  defp convert(v, :float), do: v * 1.0
  defp convert(v, :kg_to_lbs), do: Float.round(v * 2.20462, 1)
  defp convert(v, :ml_to_oz), do: Float.round(v * 0.033814, 1)
  # sleep_analysis qty is hours already in most Health Auto Export versions
  defp convert(v, :sleep_duration), do: Float.round(v * 1.0, 2)
end
