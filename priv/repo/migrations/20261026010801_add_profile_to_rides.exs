defmodule Web.Repo.Migrations.AddProfileToRides do
  use Ecto.Migration

  # A tour's speed and climb without its places: the time, the distance
  # covered and the altitude at each point of a stranger's view of the route
  # (Web.Rides.Profile). analysis/ride_power.R estimates power from it.
  def change do
    alter table(:rides) do
      add :profile, :map
    end
  end
end
