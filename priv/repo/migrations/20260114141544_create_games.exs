defmodule Web.Repo.Migrations.CreateGames do
  use Ecto.Migration

  def change do
    create table(:games) do
      add :opponent, :string, null: false
      add :league, :string, null: false
      add :tier, :string, null: false
      add :date, :date, null: false
      add :stadium, :string
      add :score, :string
      add :notes, :text
      timestamps()
    end

    create index(:games, [:league])
    create index(:games, [:date])
  end
end
