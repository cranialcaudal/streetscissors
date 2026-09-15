defmodule Web.Repo.Migrations.DecoupleCaptainsLogs do
  use Ecto.Migration

  @moduledoc """
  Captain's logs become a section of their own rather than an unaddressable
  list: each log gets a `slug` so it can live at `/logs/:slug`, `keywords` so
  it can be filtered the way blog posts are, and a real `recorded_on` date
  (`stardate` stays as display flavour derived from it — the old upload path
  stamped it from `utc_now` regardless of when the log was actually cut).
  """

  def up do
    alter table(:audio_logs) do
      add :slug, :string
      add :keywords, :string
      add :recorded_on, :date
    end

    # No rows exist at write time; kept defensive so this is safe to run
    # against a database that does have them.
    execute "UPDATE audio_logs SET slug = 'log-' || id WHERE slug IS NULL"
    execute "UPDATE audio_logs SET recorded_on = date(inserted_at) WHERE recorded_on IS NULL"

    create unique_index(:audio_logs, [:slug])
  end

  def down do
    drop unique_index(:audio_logs, [:slug])

    alter table(:audio_logs) do
      remove :slug
      remove :keywords
      remove :recorded_on
    end
  end
end
