defmodule Web.Rides.Track do
  @moduledoc """
  The GPS track Komoot recorded for a ride, exactly as recorded: a list of
  `{lat, lng, alt_m, t_ms}` (altitude and time may be nil).

  This is the **uncut** track and never leaves the server. Nothing renders
  from it directly — `Web.Rides.Route` is the only reader, and it publishes
  what `Web.Rides.Privacy` leaves.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "ride_tracks" do
    field :points, :binary
    belongs_to :ride, Web.Rides.Ride

    timestamps()
  end

  @doc false
  def changeset(track, attrs) do
    track
    |> cast(attrs, [:ride_id, :points])
    |> validate_required([:ride_id, :points])
    |> unique_constraint(:ride_id)
  end

  def encode(points), do: :erlang.term_to_binary(points, [:compressed])

  def decode(binary) when is_binary(binary), do: :erlang.binary_to_term(binary, [:safe])
end
