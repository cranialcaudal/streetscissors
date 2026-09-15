defmodule Web.Fitness.Biometric do
  use Ecto.Schema
  import Ecto.Changeset

  alias Web.Fitness.Vault

  # How each field is scored and how much it counts. :target means "hit the
  # number" — over and under are both penalised, which is what a recomp calorie
  # budget actually asks for.
  @scored_fields [
    {:sleep_hours, :higher, 3.0},
    {:hrv_ms, :higher, 3.0},
    {:energy, :higher, 2.0},
    {:protein_grams, :higher, 2.0},
    {:soreness, :lower, 2.0},
    {:calories_in, :target, 1.5},
    {:resting_hr, :lower, 1.5},
    {:fiber_grams, :higher, 1.0},
    {:water_oz, :higher, 1.0},
    {:active_calories, :higher, 1.0}
  ]

  # The goals themselves, and standing height, are the author's own numbers, so
  # they live in the fitness vault (`biometric-goals.json`) rather than here.
  # Without that file these generic reference values apply and BMI stays blank.
  @default_goals %{
    sleep_hours: 8.0,
    hrv_ms: 60,
    energy: 7,
    protein_grams: 120,
    soreness: 3,
    calories_in: 2000,
    resting_hr: 60,
    fiber_grams: 28,
    water_oz: 64,
    active_calories: 500
  }

  @doc "The goal each scored field is judged against: the vault's goals over generic defaults."
  def goals do
    given = Map.get(settings(), "goals", %{})

    Map.new(@default_goals, fn {field, default} ->
      case Map.get(given, Atom.to_string(field)) do
        n when is_number(n) and n > 0 -> {field, n}
        _ -> {field, default}
      end
    end)
  end

  @doc "Standing height in inches from the vault, used for the BMI derivation; nil when unset."
  def height_inches do
    case Map.get(settings(), "height_inches") do
      n when is_number(n) and n > 0 -> n
      _ -> nil
    end
  end

  defp settings do
    with {:ok, json} <- File.read(Path.join(Vault.base_path(), "biometric-goals.json")),
         {:ok, %{} = settings} <- Jason.decode(json) do
      settings
    else
      _ -> %{}
    end
  end

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
    field :calories_in, :integer
    field :fiber_grams, :integer
    field :vo2_max, :decimal
    field :spo2_percent, :decimal
    field :respiratory_rate, :decimal
    field :soreness, :integer
    field :energy, :integer

    field :bmi, :float, virtual: true

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
      :calories_in,
      :fiber_grams,
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

  @doc """
  Returns a 0–100 readiness score, or nil if no scored fields are present.

  Pass `goals` when scoring many entries, so the vault is read once.
  """
  def compute_score(entry, goals \\ goals()) do
    pairs =
      Enum.flat_map(@scored_fields, fn {field, dir, weight} ->
        case Map.get(entry, field) do
          nil ->
            []

          raw ->
            v = to_float(raw)
            pct = score_pct(v, Map.fetch!(goals, field) * 1.0, dir)
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
  # Symmetric band: 100 at the goal, decaying to 0 at ±50% either side.
  defp score_pct(v, goal, :target), do: max(100 - abs(v - goal) / goal * 200, 0)

  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n * 1.0

  @doc """
  BMI from the entry's weight and a height in inches (`height_inches/0` by
  default), or nil without both. Pass the height when deriving many rows.
  """
  def bmi(entry, height \\ height_inches())

  def bmi(%__MODULE__{weight_lbs: w}, height) when not is_nil(w) and is_number(height) do
    Float.round(to_float(w) * 703 / (height * height), 1)
  end

  def bmi(_entry, _height), do: nil

  @doc "Populates the virtual :bmi field."
  def with_bmi(%__MODULE__{} = b), do: %{b | bmi: bmi(b)}
end
