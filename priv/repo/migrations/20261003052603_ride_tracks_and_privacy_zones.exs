defmodule Web.Repo.Migrations.RideTracksAndPrivacyZones do
  use Ecto.Migration

  # The site draws its own route map again, so that a track can be cut where
  # it enters a privacy zone — Komoot's embed, its tour page and its static
  # map image all show a route whole.
  #
  # `ride_tracks` holds the track as recorded and is never published.
  # `rides.route_path` is the cut route as a small SVG path for the cards,
  # stored with the fingerprint of the zones it was cut by (`route_key`) so a
  # change of zone discards it.
  #
  # Komoot's map image URL and share token go with the things they fed.
  def up do
    create table(:ride_tracks) do
      add :ride_id, references(:rides, on_delete: :delete_all), null: false
      add :points, :binary, null: false

      timestamps()
    end

    create unique_index(:ride_tracks, [:ride_id])

    alter table(:rides) do
      add :route_path, :text
      add :route_key, :string
      remove :map_image_url
      remove :share_token
    end

    # A full read on the first pass after deploy, so every tour gets its track.
    execute "DELETE FROM site_settings WHERE key = 'komoot_etag_tour_recorded'"
  end

  def down do
    drop table(:ride_tracks)

    alter table(:rides) do
      remove :route_path
      remove :route_key
      add :map_image_url, :string
      add :share_token, :string
    end
  end
end
