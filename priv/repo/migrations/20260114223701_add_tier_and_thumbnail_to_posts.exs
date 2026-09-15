defmodule Web.Repo.Migrations.AddTierAndThumbnailToPosts do
  use Ecto.Migration

  def change do
    alter table(:blog_posts) do
      add :tier, :string
      add :thumbnail, :string
    end
  end
end
