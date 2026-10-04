defmodule Web.Repo.Migrations.CreateWebmentions do
  use Ecto.Migration

  # Webmentions received: another site saying "this page links to yours"
  # (Web.Webmentions). One row per source/target pair, re-verified whenever
  # the source pings again. `status` runs pending → held (verified, awaiting
  # the author) → approved | rejected, or gone once the link disappears.
  def change do
    create table(:webmentions) do
      add :source, :string, null: false
      add :target, :string, null: false
      add :piece, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :title, :string
      add :author_name, :string
      add :source_host, :string
      add :verified_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:webmentions, [:source, :target])
    create index(:webmentions, [:piece, :status])
  end
end
