defmodule Web.Repo.Migrations.CreateWebmentionsSent do
  use Ecto.Migration

  # Webmentions sent: this site telling another "my page links to yours"
  # (Web.Webmentions.Outgoing). One row per link a post makes to another
  # site, so each is announced once. `source` is our page's path, `target`
  # the page it cites, `endpoint` where the mention was posted if the target
  # advertises one. `status` runs queued → sent | no_endpoint | failed, and
  # withdrawn once the link has left the post and the target has been told.
  def change do
    create table(:webmentions_sent) do
      add :source, :string, null: false
      add :target, :string, null: false
      add :endpoint, :string
      add :status, :string, null: false, default: "queued"
      add :detail, :string
      add :sent_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:webmentions_sent, [:source, :target])
    create index(:webmentions_sent, [:status])
  end
end
