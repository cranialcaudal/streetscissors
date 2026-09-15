defmodule Web.Audio.Play do
  use Ecto.Schema
  import Ecto.Changeset

  schema "audio_plays" do
    belongs_to :audio_log, Web.Audio.Log
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
