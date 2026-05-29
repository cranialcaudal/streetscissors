defmodule Web.Repo.Migrations.CreateBiometrics do
  use Ecto.Migration

  def change do
    create table(:biometrics) do
      add :date, :date, null: false
      add :weight_lbs, :decimal
      add :resting_hr, :integer
      add :sleep_hours, :decimal
      add :protein_grams, :integer
      add :water_oz, :integer
      add :screentime_hours, :decimal

      timestamps()
    end

    create unique_index(:biometrics, [:date])
  end
end
