defmodule Web.Repo.Migrations.AddContactAndPinned do
  use Ecto.Migration

  def change do
    # Add pinned flag to blog posts
    alter table(:blog_posts) do
      add :is_pinned, :boolean, default: false, null: false
    end

    create index(:blog_posts, [:is_pinned])

    # Contact messages
    create table(:contact_messages) do
      add :name, :string
      add :email, :string
      add :message, :text
      add :read, :boolean, default: false
      timestamps()
    end
  end
end
