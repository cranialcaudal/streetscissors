defmodule Web.Repo.Migrations.AddCheckedToGroceryItems do
  use Ecto.Migration

  def change do
    alter table(:grocery_items) do
      add :checked, :boolean, default: false, null: false
    end
  end
end
