defmodule Web.Repo.Migrations.AddRecipientCountToNewsletterDrafts do
  use Ecto.Migration

  def change do
    alter table(:newsletter_drafts) do
      add :recipient_count, :integer, null: false, default: 0
    end
  end
end
