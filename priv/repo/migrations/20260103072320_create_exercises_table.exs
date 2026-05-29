defmodule Web.Repo.Migrations.CreateExercisesTable do
  use Ecto.Migration

  def change do
    create table(:exercises) do
      add :name, :string
      add :slug, :string
      add :description, :text
      add :video_url, :string
      add :resources, :text

      timestamps()
    end

    create unique_index(:exercises, [:slug])
  end
end
