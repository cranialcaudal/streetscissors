defmodule Web.Repo.Migrations.KomootShareTokensAndHealthWorkouts do
  use Ecto.Migration

  # Two additions to the activity archive.
  #
  # `rides.share_token` is the Komoot share link of a private tour — the one
  # thing that lets Komoot's embed show a tour that isn't public. The sync
  # asks for it once per private tour.
  #
  # `health_workouts` holds the Apple Health workouts Health Auto Export
  # sends: the heart rate and energy the watch measured on a ride, which
  # Komoot never keeps. They are matched to rides by start time when read,
  # so a workout can arrive before or after its tour syncs. No route data is
  # ever stored — the map is Komoot's.
  def up do
    alter table(:rides) do
      add :share_token, :string
    end

    create table(:health_workouts) do
      add :hk_id, :string, null: false
      add :activity, :string
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :active_kcal, :integer
      add :avg_hr, :integer
      add :max_hr, :integer
      add :hr_trace, {:array, :integer}

      timestamps()
    end

    create unique_index(:health_workouts, [:hk_id])
    create index(:health_workouts, [:started_at])

    # A 304 would otherwise answer the first pass after deploy, and the
    # private tours already on file would wait for their next edit to get a
    # share token. Clearing the ETag makes that pass a full read.
    execute "DELETE FROM site_settings WHERE key = 'komoot_etag_tour_recorded'"
  end

  def down do
    drop table(:health_workouts)

    alter table(:rides) do
      remove :share_token
    end
  end
end
