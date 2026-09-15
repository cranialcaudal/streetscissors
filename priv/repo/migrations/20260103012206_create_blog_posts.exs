defmodule Web.Repo.Migrations.CreateBlogPosts do
  use Ecto.Migration

  def change do
    execute "DROP TABLE IF EXISTS blog_post_edits"
    execute "DROP TABLE IF EXISTS blog_posts"

    create table(:blog_posts) do
      add :title, :string
      add :slug, :string
      add :content, :text
      add :category, :string
      add :published_at, :naive_datetime

      timestamps()
    end

    create unique_index(:blog_posts, [:slug])
    create index(:blog_posts, [:category])

    create table(:blog_post_edits) do
      add :post_id, references(:blog_posts, on_delete: :delete_all)
      add :summary, :text
      add :editor_ip, :string

      timestamps()
    end

    create index(:blog_post_edits, [:post_id])
  end
end
