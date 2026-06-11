defmodule Web.Repo.Migrations.CreateRidePoints do
  use Ecto.Migration

  def change do
    create table(:ride_points) do
      add :ride_id, references(:rides, on_delete: :delete_all), null: false
      add :lat, :float, null: false
      add :lon, :float, null: false
      add :recorded_at, :utc_datetime, null: false
      add :altitude_m, :float
      add :speed_mps, :float
      add :accuracy_m, :float
    end

    # Idempotency key: Overland re-sends whole batches until acknowledged.
    create unique_index(:ride_points, [:ride_id, :recorded_at])
  end
end
