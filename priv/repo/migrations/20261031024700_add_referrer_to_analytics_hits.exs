defmodule Web.Repo.Migrations.AddReferrerToAnalyticsHits do
  use Ecto.Migration

  def change do
    alter table(:analytics_hits) do
      add :referrer, :string
    end

    create index(:analytics_hits, [:referrer])
  end
end
