defmodule Web.Repo.Migrations.CreateRides do
  use Ecto.Migration

  def change do
    create table(:rides) do
      add :name, :string
      add :description, :text
      add :status, :string, null: false, default: "active"
      add :source, :string, null: false, default: "overland"
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime
      add :distance_m, :float
      add :duration_s, :integer
      add :avg_speed_mps, :float
      add :max_speed_mps, :float
      add :ascent_m, :float
      add :descent_m, :float
      add :point_count, :integer, null: false, default: 0

      timestamps()
    end

    create index(:rides, [:status])
    create index(:rides, [:started_at])
  end
end
