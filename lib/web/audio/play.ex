defmodule Web.Audio.Play do
  @moduledoc """
  One view of a captain's log, counted the way a video site counts: a row is
  written after 30 seconds of real playing, at most once per browser per log
  per half hour (`Web.Audio.record_play/4`). `witness` is an anonymous id the
  browser keeps, so repeat views can be told apart without an account.

  **What it stores about the viewer:** the IP address and user agent. The
  `country`, `city`, `latitude` and `longitude` columns are left over from an
  earlier version and are no longer filled in.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "audio_plays" do
    belongs_to :audio_log, Web.Audio.Log
    field :witness, :string
    field :ip_address, :string
    field :user_agent, :string
    field :country, :string
    field :city, :string
    field :latitude, :float
    field :longitude, :float

    timestamps()
  end

  def changeset(play, attrs) do
    play
    |> cast(attrs, [
      :audio_log_id,
      :witness,
      :ip_address,
      :user_agent,
      :country,
      :city,
      :latitude,
      :longitude
    ])
    |> validate_required([:audio_log_id])
  end
end
