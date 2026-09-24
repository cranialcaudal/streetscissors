defmodule Web.Rides.AppleHealth do
  @moduledoc """
  Reads one workout from a Health Auto Export payload
  (`{"data": {"workouts": [...]}}`) into `Web.Rides.Workout` attributes.

  The app has shipped two export formats and neither is documented as a
  schema, so every field is looked for where either puts it and nil-tolerated:

    * heart rate — `heartRate.avg`/`.max` (v2) or `avgHeartRate`/`maxHeartRate`
      (v1), each `{qty, units}`; failing both, derived from the series
    * energy — `activeEnergyBurned` (v2 total) or `activeEnergy` (a v1 total,
      or a v2 per-minute series that is summed), converted from kJ when the
      phone is set to it
    * the heart-rate series — `heartRateData`, one sample a minute carrying
      `Avg`/`Max` (v2) or `qty` (v1)
    * times — the app's `"2026-09-22 06:45:43 -0700"`, or ISO 8601

  Only what the Activities pages show is kept. A workout's `route` — its GPS
  track — is never read: the map is Komoot's.
  """

  # Enough to draw a smooth line at any width the page gives it, and small
  # enough that a four-hour ride stays a few kilobytes.
  @max_trace_points 240

  @doc "`{:ok, attrs}` for a workout with a readable start, `:skip` otherwise."
  @spec workout_attrs(term) :: {:ok, map} | :skip
  def workout_attrs(%{} = workout) do
    with %DateTime{} = started_at <- parse_time(workout["start"]) do
      samples = heart_samples(workout["heartRateData"], started_at)
      heart = workout["heartRate"] || %{}

      {:ok,
       %{
         hk_id: hk_id(workout, started_at),
         activity: if(is_binary(workout["name"]), do: workout["name"]),
         started_at: started_at,
         ended_at: ended_at(workout, started_at),
         active_kcal: round_or_nil(active_kcal(workout)),
         avg_hr: round_or_nil(qty(heart["avg"]) || qty(workout["avgHeartRate"]) || avg(samples)),
         max_hr: round_or_nil(qty(heart["max"]) || qty(workout["maxHeartRate"]) || peak(samples)),
         hr_trace: trace(samples)
       }}
    else
      _ -> :skip
    end
  end

  def workout_attrs(_workout), do: :skip

  @doc """
  Parses the app's `"2026-09-22 06:45:43 -0700"` timestamps, or ISO 8601,
  into a UTC `DateTime` truncated to the second. nil for anything else.
  """
  def parse_time(value) when is_binary(value) do
    iso =
      case Regex.run(
             ~r/^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(\.\d+)?\s*([+-]\d{2}):?(\d{2})$/,
             String.trim(value)
           ) do
        [_, date, time, fraction, hours, minutes] ->
          "#{date}T#{time}#{fraction}#{hours}:#{minutes}"

        nil ->
          String.trim(value)
      end

    case DateTime.from_iso8601(iso) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  def parse_time(_value), do: nil

  # HealthKit's own id when the export carries one; otherwise the start, which
  # no two workouts from one watch share.
  defp hk_id(%{"id" => id}, _started_at) when is_binary(id) and id != "", do: id
  defp hk_id(_workout, started_at), do: "start:" <> DateTime.to_iso8601(started_at)

  defp ended_at(workout, started_at) do
    case parse_time(workout["end"]) do
      %DateTime{} = ended_at ->
        ended_at

      nil ->
        case qty(workout["duration"]) do
          nil -> nil
          seconds -> DateTime.add(started_at, round(seconds))
        end
    end
  end

  defp active_kcal(workout) do
    case {workout["activeEnergyBurned"], workout["activeEnergy"]} do
      {%{} = total, _} -> kcal(total)
      {_, %{} = total} -> kcal(total)
      {_, series} when is_list(series) -> series |> Enum.map(&kcal/1) |> sum()
      _ -> nil
    end
  end

  defp kcal(%{"units" => units} = measure) when is_binary(units) do
    case qty(measure) do
      nil -> nil
      value -> if String.downcase(units) in ~w(kj kilojoules), do: value * 0.239006, else: value
    end
  end

  defp kcal(measure), do: qty(measure)

  # `{offset_s, avg_bpm, max_bpm}` per sample, in time order. A sample
  # without a readable time or a number is dropped, not guessed at.
  defp heart_samples(series, started_at) when is_list(series) do
    series
    |> Enum.flat_map(fn
      %{} = sample ->
        with %DateTime{} = at <- parse_time(sample["date"]),
             bpm when is_number(bpm) <- sample["Avg"] || sample["avg"] || sample["qty"] do
          [{DateTime.diff(at, started_at), bpm, sample["Max"] || sample["max"] || bpm}]
        else
          _ -> []
        end

      _other ->
        []
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp heart_samples(_series, _started_at), do: []

  defp avg([]), do: nil
  defp avg(samples), do: samples |> Enum.map(&elem(&1, 1)) |> mean()

  defp peak([]), do: nil

  defp peak(samples) do
    samples |> Enum.map(&elem(&1, 2)) |> Enum.filter(&is_number/1) |> Enum.max(fn -> nil end)
  end

  # Flattened `offset_s, bpm` pairs (see `Workout`), averaged down into at
  # most @max_trace_points buckets.
  defp trace([]), do: []

  defp trace(samples) do
    size = ceil(length(samples) / @max_trace_points)

    samples
    |> Enum.chunk_every(size)
    |> Enum.flat_map(fn bucket ->
      [
        round(mean(Enum.map(bucket, &elem(&1, 0)))),
        round(mean(Enum.map(bucket, &elem(&1, 1))))
      ]
    end)
  end

  defp qty(%{"qty" => value}) when is_number(value), do: value
  defp qty(value) when is_number(value), do: value
  defp qty(_value), do: nil

  defp sum(values) do
    case Enum.filter(values, &is_number/1) do
      [] -> nil
      numbers -> Enum.sum(numbers)
    end
  end

  defp mean(values), do: Enum.sum(values) / length(values)

  defp round_or_nil(nil), do: nil
  defp round_or_nil(value), do: round(value)
end
