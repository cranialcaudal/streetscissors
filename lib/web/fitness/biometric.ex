defmodule Web.Fitness.Biometric do
  use Ecto.Schema
  import Ecto.Changeset

  schema "biometrics" do
    field :date, :date
    field :weight_lbs, :decimal
    field :resting_hr, :integer
    field :protein_grams, :integer
    field :water_oz, :integer
    field :sleep_hours, :decimal
    field :screentime_hours, :decimal
    field :body_fat_percentage, :decimal

    # Virtual field for BMI calculation (optional, or can be calculated in view)
    field :bmi, :decimal, virtual: true

    timestamps()
  end

  @doc false
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
      :body_fat_percentage
    ])
    |> validate_required([:date])
    |> unique_constraint(:date)
  end
end
