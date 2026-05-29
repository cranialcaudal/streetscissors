defmodule Web.Repo.Migrations.AddMuscleGroupToExercises do
  use Ecto.Migration

  def change do
    alter table(:exercises) do
      add :muscle_group, :string
    end
  end
end
