defmodule Web.Repo.Migrations.CreateNewsletterDrafts do
  use Ecto.Migration

  def change do
    create table(:newsletter_drafts) do
      add :subject, :string
      add :body, :text
      # draft, sent
      add :status, :string, default: "draft"
      add :sent_at, :naive_datetime

      timestamps()
    end
  end
end
