defmodule Web.Repo.Migrations.AddBodyFatToBiometrics do
  use Ecto.Migration

  def change do
    alter table(:biometrics) do
      add :body_fat_percentage, :decimal
    end
  end
end
