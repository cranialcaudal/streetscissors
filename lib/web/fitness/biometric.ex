defmodule Web.Fitness.Biometric do
  use Ecto.Schema
  import Ecto.Changeset

  @scored_fields [
    {:sleep_hours, 8.0, :higher, 3.0},
    {:hrv_ms, 60, :higher, 3.0},
    {:energy, 7, :higher, 2.0},
    {:soreness, 3, :lower, 2.0},
    {:protein_grams, 160, :higher, 1.5},
    {:resting_hr, 55, :lower, 1.5},
    {:water_oz, 100, :higher, 1.0},
    {:active_calories, 600, :higher, 1.0}
  ]

  @goals Enum.into(@scored_fields, %{}, fn {f, g, _, _} -> {f, g} end)

  def goals, do: @goals

  schema "biometrics" do
    field :date, :date
    field :weight_lbs, :decimal
    field :resting_hr, :integer
    field :protein_grams, :integer
    field :water_oz, :integer
    field :sleep_hours, :decimal
    field :screentime_hours, :decimal
    field :body_fat_percentage, :decimal
    field :hrv_ms, :integer
    field :active_calories, :integer
    field :vo2_max, :decimal
    field :spo2_percent, :decimal
    field :respiratory_rate, :decimal
    field :soreness, :integer
    field :energy, :integer

    field :bmi, :decimal, virtual: true

    timestamps()
  end

  def changeset(biometric, attrs) do
    biometric
    |> cast(attrs, [
      :date,
      :weight_lbs,
      :resting_hr,
      :protein_grams,
      :water_oz,
      :sleep_hours,
      :screentime_hours,
      :body_fat_percentage,
      :hrv_ms,
      :active_calories,
      :vo2_max,
      :spo2_percent,
      :respiratory_rate,
      :soreness,
      :energy
    ])
    |> validate_required([:date])
    |> validate_number(:soreness, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> validate_number(:energy, greater_than_or_equal_to: 1, less_than_or_equal_to: 10)
    |> unique_constraint(:date)
  end

  @doc "Returns a 0–100 readiness score, or nil if no scored fields are present."
  def compute_score(entry) do
    pairs =
      Enum.flat_map(@scored_fields, fn {field, goal, dir, weight} ->
        case Map.get(entry, field) do
          nil ->
            []

          raw ->
            v = to_float(raw)
            pct = score_pct(v, goal * 1.0, dir)
            [{pct, weight}]
        end
      end)

    case pairs do
      [] ->
        nil

      _ ->
        total_w = Enum.sum(Enum.map(pairs, &elem(&1, 1)))
        weighted = Enum.sum(Enum.map(pairs, fn {p, w} -> p * w end))
        round(weighted / total_w)
    end
  end

  defp score_pct(v, goal, :higher), do: min(v / goal * 100, 100)
  defp score_pct(v, goal, :lower), do: max(min((2 * goal - v) / goal * 100, 100), 0)

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n * 1.0
end
