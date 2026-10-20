defmodule Web.Logs.Play do
  @moduledoc """
  One view of a captain's log, counted the way a video site counts: a row is
  written after 30 seconds of real playing, at most once per browser per log
  per half hour (`Web.Logs.record_play/3`). `witness` is an anonymous id the
  browser keeps, so repeat views can be told apart without an account.

  **What it stores about the viewer:** the witness token and, at most, the
  user agent. Never the IP address.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "audio_plays" do
    belongs_to :audio_log, Web.Logs.Log
    field :witness, :string
    field :user_agent, :string

    timestamps()
  end

  def changeset(play, attrs) do
    play
    |> cast(attrs, [:audio_log_id, :witness, :user_agent])
    |> validate_required([:audio_log_id])
  end
end
