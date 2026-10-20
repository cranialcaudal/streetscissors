defmodule Web.Repo.Migrations.CreatePageWitnesses do
  use Ecto.Migration

  # Where a post's all-time readers are kept once the hits that showed them
  # are pruned (Web.Analytics.prune/0): one row per page and visitor hash.
  def change do
    create table(:page_witnesses) do
      add :page, :string, null: false
      add :ip_hash, :string, null: false
      timestamps(updated_at: false)
    end

    create unique_index(:page_witnesses, [:page, :ip_hash])
  end
end
