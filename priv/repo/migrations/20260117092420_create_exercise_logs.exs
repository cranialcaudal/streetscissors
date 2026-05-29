defmodule Web.Repo.Migrations.CreateExerciseLogs do
  use Ecto.Migration

  def change do
    create table(:exercise_logs) do
      add :exercise_id, references(:exercises, on_delete: :delete_all)
      add :date, :date
      add :metrics, :map
      add :note, :text

      timestamps()
    end

    create index(:exercise_logs, [:exercise_id])
    create index(:exercise_logs, [:date])
  end
end
