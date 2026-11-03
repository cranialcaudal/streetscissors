defmodule Web.Repo.Migrations.DropHealthWorkouts do
  use Ecto.Migration

  # The Apple Health import is gone, and with it the only writer and reader of
  # this table. It was empty when dropped.
  def up do
    drop table(:health_workouts)
  end

  def down do
    create table(:health_workouts) do
      add :hk_id, :string, null: false
      add :activity, :string
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :active_kcal, :integer
      add :avg_hr, :integer
      add :max_hr, :integer
      add :min_hr, :integer
      add :hr_trace, {:array, :integer}

      timestamps()
    end

    create unique_index(:health_workouts, [:hk_id])
    create index(:health_workouts, [:started_at])
  end
end
