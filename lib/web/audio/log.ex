defmodule Web.Audio.Log do
  use Ecto.Schema
  import Ecto.Changeset

  schema "audio_logs" do
    field :title, :string
    field :stardate, :string
    field :file_path, :string
    field :duration, :integer
    field :description, :string
    field :published, :boolean, default: false

    timestamps()
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:title, :stardate, :file_path, :duration, :description, :published])
    |> validate_required([:title, :stardate, :file_path])
  end
end
