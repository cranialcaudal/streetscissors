defmodule Web.Repo.Migrations.SimplifyRidesToKomootListing do
  use Ecto.Migration

  # Rides became a mirror of the tours recorded on Komoot, built from the
  # tour listing alone: no stored GPS track, no planned routes, no GPX
  # uploads, no privacy zones, no live link. Everything dropped here either
  # re-derives from Komoot or was never used, so there is no way back down.
  def up do
    drop table(:ride_points)

    execute "DELETE FROM rides WHERE kind <> 'recorded' OR source <> 'komoot' OR komoot_id IS NULL"

    alter table(:rides) do
      remove :kind
      remove :source
      remove :description
      remove :point_count
      remove :max_speed_mps
      remove :ended_at
    end

    # Settings of the removed features, and the listing ETags. Clearing the
    # recorded one makes the first pass after deploy a full read, so every
    # tour is re-checked against the new privacy rule and any tour already
    # deleted on Komoot is dropped.
    execute """
    DELETE FROM site_settings WHERE key IN (
      'komoot_etag_tour_recorded', 'komoot_etag_tour_planned', 'komoot_embed_url',
      'ride_privacy_zones', 'live_ride_url', 'live_ride_started_at', 'live_ride_note',
      'live_ride_ttl_hours'
    )
    """
  end

  def down do
    raise Ecto.MigrationError,
      message: "rides were simplified to the Komoot listing; dropped tracks re-sync from Komoot"
  end
end
