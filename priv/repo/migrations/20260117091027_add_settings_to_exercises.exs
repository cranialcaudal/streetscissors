defmodule Web.Repo.Migrations.AddSettingsToExercises do
  use Ecto.Migration

  def change do
    alter table(:exercises) do
      add :settings, :map, default: %{}
    end
  end
end
