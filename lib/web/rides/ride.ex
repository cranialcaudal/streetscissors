defmodule Web.Rides.Ride do
  use Ecto.Schema
  import Ecto.Changeset

  schema "rides" do
    field :name, :string
    field :description, :string
    field :source, :string, default: "gpx"
    field :kind, :string, default: "recorded"
    field :sport, :string
    field :komoot_id, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :distance_m, :float
    field :duration_s, :integer
    field :avg_speed_mps, :float
    field :max_speed_mps, :float
    field :ascent_m, :float
    field :descent_m, :float
    field :point_count, :integer, default: 0
    field :time_in_motion_s, :integer
    field :kcal, :integer
    field :visibility, :string, default: "public"
    field :komoot_changed_at, :utc_datetime
    field :map_image_url, :string

    has_many :points, Web.Rides.RidePoint

    timestamps()
  end

  @doc false
  def changeset(ride, attrs) do
    ride
    |> cast(attrs, [
      :name,
      :description,
      :source,
      :kind,
      :sport,
      :komoot_id,
      :started_at,
      :ended_at,
      :time_in_motion_s,
      :kcal,
      :visibility,
      :komoot_changed_at,
      :map_image_url
    ])
    |> validate_inclusion(:source, ~w(gpx komoot))
    |> validate_inclusion(:kind, ~w(recorded planned))
    |> validate_inclusion(:visibility, ~w(public private))
    |> unique_constraint(:komoot_id)
  end
end
