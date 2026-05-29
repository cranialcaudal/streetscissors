defmodule Web.Repo.Migrations.CreateAntigravitySchema do
  use Ecto.Migration

  def change do
    create table(:workout_sessions) do
      add :name, :string
      add :date, :date, null: false
      add :is_admin, :boolean, default: false, null: false
      # Optional, for future multi-user support
      add :user_id, :integer

      timestamps()
    end

    create index(:workout_sessions, [:date])

    create table(:workout_sets) do
      add :exercise_id, references(:exercises, on_delete: :nothing), null: false
      add :workout_session_id, references(:workout_sessions, on_delete: :delete_all), null: false

      add :reps, :integer
      add :weight, :decimal
      add :rpe, :integer
      add :notes, :text

      timestamps()
    end

    create index(:workout_sets, [:exercise_id])
    create index(:workout_sets, [:workout_session_id])
  end
end
