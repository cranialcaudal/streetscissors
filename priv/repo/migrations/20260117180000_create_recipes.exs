defmodule Web.Repo.Migrations.CreateRecipes do
  use Ecto.Migration

  def change do
    create table(:recipes) do
      add :title, :string
      add :commentary, :text
      # map or {:array, :map} depending on DB. SQLite/Postgres support map/jsonb.
      add :ingredients, :map
      add :steps, :map

      timestamps()
    end
  end
end
