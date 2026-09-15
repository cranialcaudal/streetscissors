defmodule Web.Repo.Migrations.AddPublishedToPosts do
  use Ecto.Migration

  def change do
    alter table(:blog_posts) do
      add :published, :boolean, default: true
    end
  end
end
