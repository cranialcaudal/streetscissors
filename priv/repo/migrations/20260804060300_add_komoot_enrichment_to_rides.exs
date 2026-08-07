defmodule Web.Repo.Migrations.AddKomootEnrichmentToRides do
  use Ecto.Migration

  def change do
    alter table(:rides) do
      add :time_in_motion_s, :integer
      add :kcal, :integer
      add :visibility, :string, null: false, default: "public"
      add :komoot_changed_at, :utc_datetime
      add :map_image_url, :string
    end

    create index(:rides, [:visibility])
  end
end
