defmodule Web.Repo.Migrations.KomootEmbedAndAppleHealth do
  use Ecto.Migration

  # The activities are Komoot's own embed again, and what the watch measured
  # comes back beside them.
  #
  # The site stopped embedding Komoot because its rendering showed a route
  # whole, home included, and drew its own map from a track it cut itself.
  # Komoot now has a privacy zone around home and applies it to everything a
  # stranger is shown — the embed, the tour page, the static map — so the cut
  # is made at the source and the site's own copy of it is no longer needed.
  #
  # `ride_tracks` goes, and with it the only whole GPS tracks the site ever
  # held. `rides.route_path`/`route_key` were the cut outline drawn from them.
  #
  # `rides.share_token` is the Komoot share link of a private tour, which is
  # what lets the embed show a tour that isn't public. `map_image_url` is the
  # tour's static map *as a stranger is given it*, already cut by the zone.
  # `exposed` is set when a stranger's view of a tour still comes close to a
  # place the site was told is private: that tour is shown without Komoot's
  # rendering until it no longer does (Web.Rides.Privacy).
  #
  # `health_workouts` holds Apple Health workouts: the heart rate and energy
  # the watch measured, which Komoot keeps none of. They are matched to rides
  # by start time when read. No route is ever stored with one.
  def up do
    drop table(:ride_tracks)

    alter table(:rides) do
      remove :route_path
      remove :route_key
      add :share_token, :string
      add :map_image_url, :text
      add :exposed, :boolean, null: false, default: false
    end

    create table(:health_workouts) do
      add :hk_id, :string, null: false
      add :activity, :string
      add :started_at, :utc_datetime, null: false
      add :ended_at, :utc_datetime
      add :active_kcal, :integer
      add :avg_hr, :integer
      add :max_hr, :integer
      add :min_hr, :integer
      add :hr_trace, {:array, :integer}

      timestamps()
    end

    create unique_index(:health_workouts, [:hk_id])
    create index(:health_workouts, [:started_at])

    # A 304 would otherwise answer the first pass after deploy, and no tour
    # would get its share link, its stranger's-eye map or its privacy check
    # until its next edit. Clearing the ETag makes that pass a full read.
    execute "DELETE FROM site_settings WHERE key = 'komoot_etag_tour_recorded'"
  end

  def down do
    drop table(:health_workouts)

    alter table(:rides) do
      remove :share_token
      remove :map_image_url
      remove :exposed
      add :route_path, :text
      add :route_key, :string
    end

    create table(:ride_tracks) do
      add :ride_id, references(:rides, on_delete: :delete_all), null: false
      add :points, :binary, null: false

      timestamps()
    end

    create unique_index(:ride_tracks, [:ride_id])
  end
end
