defmodule Web.Rides.Ride do
  @moduledoc """
  One tour recorded on Komoot. Every field comes from Komoot's tour listing,
  so a ride is exactly as current as the last sync — nothing here is edited
  on the site.

  `visibility` mirrors the tour's Komoot privacy. It no longer hides a ride
  (the archive lists every recorded tour). Komoot's embed refuses anything
  not public, so a private tour is embedded through its `share_token`, which
  the sync asks Komoot for once.

  `health` is never stored: `Web.Rides.attach_health/1` fills it with the
  Apple Health workout recorded alongside the tour, or leaves it nil.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "rides" do
    field :komoot_id, :string
    field :name, :string
    field :sport, :string
    field :started_at, :utc_datetime
    field :distance_m, :float
    field :duration_s, :integer
    field :time_in_motion_s, :integer
    field :avg_speed_mps, :float
    field :ascent_m, :float
    field :descent_m, :float
    field :kcal, :integer
    field :visibility, :string, default: "public"
    field :komoot_changed_at, :utc_datetime
    field :map_image_url, :string
    field :share_token, :string
    field :health, :any, virtual: true

    timestamps()
  end

  @fields ~w(komoot_id name sport started_at distance_m duration_s time_in_motion_s
             avg_speed_mps ascent_m descent_m kcal visibility komoot_changed_at
             map_image_url share_token)a

  @doc false
  def changeset(ride, attrs) do
    ride
    |> cast(attrs, @fields)
    |> validate_required([:komoot_id, :started_at])
    |> validate_inclusion(:visibility, ~w(public private))
    |> unique_constraint(:komoot_id)
  end
end
