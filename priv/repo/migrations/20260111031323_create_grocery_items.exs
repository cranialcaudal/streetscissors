defmodule Web.Repo.Migrations.CreateGroceryItems do
  use Ecto.Migration

  def change do
    create table(:grocery_items) do
      add :name, :string
      add :category, :string
      add :description, :text

      timestamps(type: :utc_datetime)
    end
  end
end
