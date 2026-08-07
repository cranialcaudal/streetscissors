defmodule Web.Rides.RidePoint do
  use Ecto.Schema

  schema "ride_points" do
    belongs_to :ride, Web.Rides.Ride
    field :lat, :float
    field :lon, :float
    field :recorded_at, :utc_datetime
    field :altitude_m, :float
    field :speed_mps, :float
    field :accuracy_m, :float
  end
end
