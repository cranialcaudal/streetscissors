defmodule Web.Cuts.Media do
  @moduledoc """
  A file in a cut's bin: a take (video, kept with its sound) or a sound
  (music or a voice). The file is kept as it came, and the browser plays a
  proxy made from it (`Web.Cuts.make_proxy/1`); the render reads the file.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(video audio)
  @statuses ~w(processing ready failed)

  schema "cut_media" do
    field :kind, :string
    field :name, :string
    field :file, :string
    field :proxy, :string
    field :status, :string, default: "processing"
    field :error, :string
    field :duration_ms, :integer
    field :width, :integer
    field :height, :integer
    field :has_audio, :boolean, default: false

    belongs_to :log_cut, Web.Cuts.Cut

    timestamps()
  end

  def changeset(media, attrs) do
    media
    |> cast(attrs, [
      :kind,
      :name,
      :file,
      :proxy,
      :status,
      :error,
      :duration_ms,
      :width,
      :height,
      :has_audio,
      :log_cut_id
    ])
    |> validate_required([:kind, :name, :file, :status, :log_cut_id])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
  end
end
