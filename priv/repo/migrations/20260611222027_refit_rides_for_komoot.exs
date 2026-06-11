defmodule Web.Repo.Migrations.RefitRidesForKomoot do
  use Ecto.Migration

  def change do
    drop index(:rides, [:status])

    alter table(:rides) do
      add :komoot_id, :string
      add :kind, :string, null: false, default: "recorded"
      add :sport, :string
      remove :status, :string, null: false, default: "active"
    end

    create unique_index(:rides, [:komoot_id])

    execute "UPDATE rides SET source = 'gpx' WHERE source = 'overland'", ""
  end
end
