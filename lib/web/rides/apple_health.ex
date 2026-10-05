defmodule Web.Rides.AppleHealth do
  @moduledoc """
  What the watch measured, read out of Apple Health into
  `Web.Rides.Workout` attributes. Komoot keeps no heart rate and no energy —
  every tour's `kcal_active` is 0, and its track carries position, height
  and time and nothing else — so Apple Health is the only place they exist.

  There are two ways in, and both end in `Web.Rides.store_workouts/1`:

    * **Apple's own export** (`Web.Rides.AppleHealth.Export`): the Health
      app's "Export All Health Data", uploaded from the admin. Free, built
      into the phone, and it carries every workout the watch ever recorded,
      so one upload fills in the whole archive. It is not automatic.
    * **A webhook** (`WebWeb.HealthWebhookController`), for the Health Auto
      Export app, which posts each workout as it is recorded. Automatic, and
      that app charges for it. `workout_attrs/1` here reads its payload
      (`{"data": {"workouts": [...]}}`).

  The app has shipped two payload formats and neither is documented as a
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

  @doc """
  A heart-rate series as the flat `[offset_s, bpm, …]` a `Workout` stores,
  averaged down into at most #{@max_trace_points} buckets. Takes
  `[{offset_s, bpm}]` in time order.
  """
  def trace_of([]), do: []

  def trace_of(samples) do
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

  @token_setting "health_webhook_token"

  @doc """
  True when the webhook will accept anything at all: a token has been made
  in the admin, or `HEALTH_WEBHOOK_TOKEN` is set.
  """
  def webhook_open?, do: stored_digest() != nil or env_token() != nil

  @doc """
  True when `given` is the webhook's token. The one made in the admin is the
  only one accepted while it exists; `HEALTH_WEBHOOK_TOKEN` counts when none
  has been made. With neither, nothing is the right token.
  """
  def valid_webhook_token?(given) when is_binary(given) do
    case {stored_digest(), env_token()} do
      {nil, nil} -> false
      {nil, token} -> Plug.Crypto.secure_compare(given, token)
      {digest, _token} -> Plug.Crypto.secure_compare(digest(given), digest)
    end
  end

  def valid_webhook_token?(_given), do: false

  @doc """
  Makes a new webhook token, replacing any made before, and returns it. This
  is the only time it exists here in the clear: what is kept is its digest,
  so neither the database nor a backup of it holds something that can post.
  """
  def create_webhook_token do
    token = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {:ok, _setting} = Web.SiteSettings.put_setting(@token_setting, digest(token))
    token
  end

  @doc "Removes the admin-made token. With no `HEALTH_WEBHOOK_TOKEN` either, the webhook closes."
  def revoke_webhook_token, do: Web.SiteSettings.delete_setting(@token_setting)

  # A token is 256 random bits, so a plain hash of it cannot be guessed back;
  # the slow hashes passwords need would only slow the webhook down.
  defp digest(token), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)

  # Only a digest counts. Anything else in the row is not a token.
  defp stored_digest do
    case Web.SiteSettings.get_setting(@token_setting) do
      "sha256:" <> _hex = digest -> digest
      _ -> nil
    end
  end

  defp env_token, do: present(Application.get_env(:web, :health_webhook_token))

  defp present(value) when is_binary(value) and value != "", do: value
  defp present(_value), do: nil

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
         min_hr: round_or_nil(qty(heart["min"]) || qty(workout["minHeartRate"]) || low(samples)),
         hr_trace: trace_of(Enum.map(samples, fn {offset, bpm, _max} -> {offset, bpm} end))
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

  defp low([]), do: nil
  defp low(samples), do: samples |> Enum.map(&elem(&1, 1)) |> Enum.min()

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
