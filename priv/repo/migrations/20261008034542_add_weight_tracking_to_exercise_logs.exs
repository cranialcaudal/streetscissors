defmodule Web.Repo.Migrations.AddWeightTrackingToExerciseLogs do
  use Ecto.Migration

  # A log is filed under the exercise wiki's slug (the file's name in
  # content/fitness/exercise-wiki), not a row of the old `exercises` table,
  # which never covered most of the regimen. Weight, sets and reps become
  # numbers so they can be compared; `metrics` keeps the free-text rest.
  def change do
    alter table(:exercise_logs) do
      add :slug, :string
      add :weight, :float
      add :sets, :integer
      add :reps, :integer
    end

    create index(:exercise_logs, [:slug, :date])

    execute(
      "UPDATE exercise_logs SET slug = (SELECT slug FROM exercises WHERE exercises.id = exercise_logs.exercise_id) WHERE slug IS NULL",
      ""
    )
  end
end
