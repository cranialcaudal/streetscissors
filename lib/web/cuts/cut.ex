defmodule Web.Cuts.Cut do
  @moduledoc """
  A cut: a captain's log assembled in the cutting room (`Web.Cuts`) from takes,
  prints from the archive, titles and sound. `timeline` is the whole edit
  (`Web.Cuts.Timeline`); `audio_log_id` is the log it was rendered into, once
  it has been.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft rendering failed done)

  schema "log_cuts" do
    field :name, :string
    field :timeline, :map, default: %{}
    field :status, :string, default: "draft"
    field :render_error, :string
    field :rendered_at, :utc_datetime

    belongs_to :audio_log, Web.Audio.Log
    has_many :media, Web.Cuts.Media, foreign_key: :log_cut_id, preload_order: [asc: :id]

    timestamps()
  end

  def changeset(cut, attrs) do
    cut
    |> cast(attrs, [:name, :timeline, :status, :render_error, :rendered_at, :audio_log_id])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :status])
    |> validate_length(:name, max: 120)
    |> validate_inclusion(:status, @statuses)
  end
end
