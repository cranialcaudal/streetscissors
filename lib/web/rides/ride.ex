defmodule Web.Rides.Ride do
  @moduledoc """
  One tour recorded on Komoot. Every field comes from Komoot, so a ride is
  exactly as current as the last sync — nothing here is edited on the site.

  `visibility` mirrors the tour's Komoot privacy. It does not hide a ride (the
  archive lists every recorded tour). Komoot's embed refuses anything not
  public, so a private tour is embedded through its `share_token`, which the
  sync asks Komoot for once.

  `map_image_url` is Komoot's static map of the tour **as a stranger is given
  it**, never as its owner is: the owner's shows the route whole, and a
  stranger's has Komoot's privacy zones cut out of it.

  `stranger_view` is what a stranger is given of the tour, as of the last
  time the sync asked as one:

    * `"clear"` — a route, nowhere near a place the site was told is private.
      Only a clear tour is shown through Komoot's embed, map and link.
    * `"exposed"` — a route that begins or ends near one, which a working
      zone would have trimmed: the tripwire (`Web.Rides.Privacy`), and an
      alarm.
    * `"passing"` — a route whose ends are trimmed and which comes back near
      one in between, which no zone trims. Held back, and not an alarm.
    * `"hidden"` — nothing at all. The tour lies inside Komoot's privacy
      zone, and Komoot refuses a stranger the whole of it.
    * `nil` — not asked yet.

  Anything but clear keeps its figures and loses everything Komoot would draw.

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
    field :share_token, :string
    field :map_image_url, :string
    field :stranger_view, :string
    field :health, :any, virtual: true

    timestamps()
  end

  @fields ~w(komoot_id name sport started_at distance_m duration_s time_in_motion_s
             avg_speed_mps ascent_m descent_m kcal visibility komoot_changed_at
             share_token map_image_url stranger_view)a

  @doc false
  def changeset(ride, attrs) do
    ride
    |> cast(attrs, @fields)
    |> validate_required([:komoot_id, :started_at])
    |> validate_inclusion(:visibility, ~w(public private))
    |> validate_inclusion(:stranger_view, ~w(clear passing exposed hidden))
    |> unique_constraint(:komoot_id)
  end
end
