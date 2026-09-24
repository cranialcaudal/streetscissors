defmodule Web.Rides.AppleHealthTest do
  use ExUnit.Case, async: true

  alias Web.Rides.AppleHealth

  # Health Auto Export's second format: totals under heartRate/activeEnergyBurned,
  # a per-minute series with Min/Avg/Max. Invented values.
  @v2 %{
    "id" => "7F3A-EXAMPLE",
    "name" => "Outdoor Cycling",
    "start" => "2026-07-08 11:00:00 -0700",
    "end" => "2026-07-08 12:00:00 -0700",
    "duration" => 3600,
    "heartRate" => %{
      "min" => %{"qty" => 92, "units" => "bpm"},
      "avg" => %{"qty" => 138.4, "units" => "bpm"},
      "max" => %{"qty" => 168, "units" => "bpm"}
    },
    "activeEnergyBurned" => %{"qty" => 702.6, "units" => "kcal"},
    "heartRateData" => [
      %{"date" => "2026-07-08 11:00:00 -0700", "Min" => 90, "Avg" => 95, "Max" => 99},
      %{"date" => "2026-07-08 11:01:00 -0700", "Min" => 110, "Avg" => 120.4, "Max" => 131},
      %{"date" => "2026-07-08 11:02:00 -0700", "Min" => 130, "Avg" => 141, "Max" => 150}
    ],
    "route" => [%{"latitude" => 1.0, "longitude" => 2.0}]
  }

  test "reads the v2 export" do
    assert {:ok, attrs} = AppleHealth.workout_attrs(@v2)

    assert attrs.hk_id == "7F3A-EXAMPLE"
    assert attrs.activity == "Outdoor Cycling"
    assert attrs.started_at == ~U[2026-07-08 18:00:00Z]
    assert attrs.ended_at == ~U[2026-07-08 19:00:00Z]
    assert attrs.avg_hr == 138
    assert attrs.max_hr == 168
    assert attrs.active_kcal == 703
    # Offsets from the start, and each minute's average.
    assert attrs.hr_trace == [0, 95, 60, 120, 120, 141]
  end

  test "never keeps the route" do
    assert {:ok, attrs} = AppleHealth.workout_attrs(@v2)
    refute Map.has_key?(attrs, :route)
    refute inspect(attrs) =~ "latitude"
  end

  test "reads the v1 export" do
    v1 = %{
      "name" => "Outdoor Run",
      "start" => "2026-07-08 07:00:00 -0700",
      "duration" => 1800,
      "avgHeartRate" => %{"qty" => 151, "units" => "count/min"},
      "maxHeartRate" => %{"qty" => 177, "units" => "count/min"},
      "activeEnergy" => %{"qty" => 1400, "units" => "kJ"},
      "heartRateData" => [
        %{"date" => "2026-07-08 07:00:30 -0700", "qty" => 140},
        %{"date" => "2026-07-08 07:01:30 -0700", "qty" => 160}
      ]
    }

    assert {:ok, attrs} = AppleHealth.workout_attrs(v1)

    # No id: the start stands in, so a repeat is still the same workout.
    assert attrs.hk_id == "start:2026-07-08T14:00:00Z"
    assert attrs.ended_at == ~U[2026-07-08 14:30:00Z]
    assert attrs.avg_hr == 151
    assert attrs.max_hr == 177
    assert attrs.active_kcal == round(1400 * 0.239006)
    assert attrs.hr_trace == [30, 140, 90, 160]
  end

  test "a v2 per-minute energy series is summed" do
    workout =
      @v2
      |> Map.delete("activeEnergyBurned")
      |> Map.put("activeEnergy", [
        %{"date" => "2026-07-08 11:00:00 -0700", "qty" => 10.2, "units" => "kcal"},
        %{"date" => "2026-07-08 11:01:00 -0700", "qty" => 11.1, "units" => "kcal"}
      ])

    assert {:ok, %{active_kcal: 21}} = AppleHealth.workout_attrs(workout)
  end

  test "without totals, heart rate comes from the series" do
    workout = Map.delete(@v2, "heartRate")

    assert {:ok, %{avg_hr: avg, max_hr: 150}} = AppleHealth.workout_attrs(workout)
    assert avg == round((95 + 120.4 + 141) / 3)
  end

  test "a long series is averaged down to at most 240 points" do
    # Ten hours, one sample a minute.
    series =
      for minute <- 0..599 do
        at = DateTime.add(~U[2026-07-08 18:00:00Z], minute * 60)
        %{"date" => DateTime.to_iso8601(at), "Avg" => 100 + rem(minute, 7)}
      end

    assert {:ok, %{hr_trace: trace}} =
             AppleHealth.workout_attrs(%{@v2 | "heartRateData" => series})

    pairs = Enum.chunk_every(trace, 2)
    assert length(pairs) <= 240
    assert [first_t, _] = hd(pairs)
    assert [last_t, _] = List.last(pairs)
    assert first_t < 120 and last_t > 35_000
  end

  test "no heart data at all is fine" do
    workout = Map.drop(@v2, ["heartRate", "heartRateData"])

    assert {:ok, %{avg_hr: nil, max_hr: nil, hr_trace: []}} = AppleHealth.workout_attrs(workout)
  end

  test "a workout without a readable start is skipped" do
    assert :skip = AppleHealth.workout_attrs(Map.delete(@v2, "start"))
    assert :skip = AppleHealth.workout_attrs(%{@v2 | "start" => "last Tuesday"})
    assert :skip = AppleHealth.workout_attrs("not a workout")
  end

  test "times parse in the app's form and in ISO 8601" do
    assert AppleHealth.parse_time("2026-07-08 11:00:00 -0700") == ~U[2026-07-08 18:00:00Z]
    assert AppleHealth.parse_time("2026-07-08 11:00:00.250 +0100") == ~U[2026-07-08 10:00:00Z]
    assert AppleHealth.parse_time("2026-07-08T18:00:00Z") == ~U[2026-07-08 18:00:00Z]
    assert AppleHealth.parse_time("2026-07-08") == nil
    assert AppleHealth.parse_time(nil) == nil
  end
end
