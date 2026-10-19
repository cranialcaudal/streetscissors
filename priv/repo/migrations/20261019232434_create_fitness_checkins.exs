defmodule Web.Repo.Migrations.CreateFitnessCheckins do
  use Ecto.Migration

  # The training block's daily check-in (Web.Fitness.Checkin): how the body
  # is, one row a day, which the guardrails read before a target is given.
  def change do
    create table(:fitness_checkins) do
      add :date, :date, null: false
      add :pain, :integer
      add :sleep_hours, :float
      add :soreness, :integer
      add :energy, :integer
      add :note, :text

      timestamps()
    end

    create unique_index(:fitness_checkins, [:date])
  end
end
