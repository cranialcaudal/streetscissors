defmodule Web.Repo.Migrations.CreateMediaItems do
  use Ecto.Migration

  def change do
    create table(:media_items) do
      add :title, :string, null: false
      add :type, :string, null: false
      add :tier, :string, null: false
      add :status, :string, null: false
      add :year_consumed, :integer
      add :notes, :text

      timestamps()
    end

    create index(:media_items, [:type])
    create index(:media_items, [:tier])
    create index(:media_items, [:year_consumed])
  end
end
