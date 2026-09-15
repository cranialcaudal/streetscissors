defmodule Web.Repo.Migrations.AddPostSlugToMediaAndGames do
  use Ecto.Migration

  def change do
    alter table(:media_items) do
      add :post_slug, :string
    end

    alter table(:games) do
      add :post_slug, :string
    end
  end
end
