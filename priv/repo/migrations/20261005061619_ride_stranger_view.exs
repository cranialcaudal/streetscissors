defmodule Web.Repo.Migrations.RideStrangerView do
  use Ecto.Migration

  # What a stranger is given of a tour is one of three things, and the site
  # now records which, in place of the single `exposed` flag:
  #
  #   * "clear"   — a route, nowhere near a place the site was told is private
  #   * "exposed" — a route that does come near one (Web.Rides.Privacy)
  #   * "hidden"  — nothing at all: the tour lies inside Komoot's privacy
  #                 zone, and Komoot answers a stranger with a refusal
  #   * NULL      — not asked yet
  #
  # The first pass after the embeds came back turned up the third: two short
  # tours that never leave the zone. With only a flag to record an answer in,
  # a refusal could only be a failure, so those two failed every hour and the
  # hourly pass could never go back to costing nothing.
  #
  # NULL matters as much. Only a "clear" tour gets Komoot's rendering, so a
  # tour nobody has looked at as a stranger shows its figures and waits.
  #
  # A ride that was looked at and not exposed has a map on file; that is what
  # marks it clear here. The rest are left unasked, and the listing's ETag is
  # dropped so the next pass asks.
  def up do
    alter table(:rides) do
      add :stranger_view, :string
    end

    execute "UPDATE rides SET stranger_view = 'exposed' WHERE exposed = 1"

    execute "UPDATE rides SET stranger_view = 'clear' WHERE exposed = 0 AND map_image_url IS NOT NULL"

    alter table(:rides) do
      remove :exposed
    end

    execute "DELETE FROM site_settings WHERE key = 'komoot_etag_tour_recorded'"
  end

  def down do
    alter table(:rides) do
      add :exposed, :boolean, null: false, default: false
    end

    execute "UPDATE rides SET exposed = 1 WHERE stranger_view = 'exposed'"

    alter table(:rides) do
      remove :stranger_view
    end
  end
end
