defmodule Web.Repo.Migrations.AddNutritionIntakeToBiometrics do
  use Ecto.Migration

  def change do
    alter table(:biometrics) do
      # Calories *consumed* — distinct from :active_calories, which is expenditure.
      add :calories_in, :integer
      add :fiber_grams, :integer
    end
  end
end
