defmodule Web.Repo.Migrations.AddTagsAndAnalytics do
  use Ecto.Migration

  def change do
    # Analytics
    create table(:analytics_hits) do
      add :path, :string
      add :user_agent, :string
      # privacy preserving
      add :ip_hash, :string
      timestamps(updated_at: false)
    end

    create index(:analytics_hits, [:path])
    create index(:analytics_hits, [:inserted_at])

    # Tags system
    create table(:tags) do
      add :name, :string
      add :slug, :string
      timestamps()
    end

    create unique_index(:tags, [:slug])

    create table(:post_tags, primary_key: false) do
      add :post_id, references(:blog_posts, on_delete: :delete_all)
      add :tag_id, references(:tags, on_delete: :delete_all)
    end

    create index(:post_tags, [:post_id])
    create index(:post_tags, [:tag_id])
    create unique_index(:post_tags, [:post_id, :tag_id])
  end
end
