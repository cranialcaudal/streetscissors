defmodule Web.Fitness.Exercise do
  @moduledoc """
  An exercise as the database knows it: one row per exercise that has ever been
  logged, linking the training log to the wiki page of the same `slug`. The
  wiki page in `content/fitness/exercise-wiki/` is the real description; this
  row exists so log entries have something to belong to
  (`Web.Fitness.loggable_exercise/1` makes it on first use).
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "exercises" do
    field :name, :string
    field :slug, :string
    field :description, :string
    field :video_url, :string
    field :resources, :string
    field :muscle_group, :string

    field :settings, :map, default: %{}

    timestamps()
  end

  @doc false
  def changeset(exercise, attrs) do
    exercise
    |> cast(attrs, [:name, :slug, :description, :video_url, :resources, :muscle_group, :settings])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
    |> validate_format(:slug, ~r/^[a-z0-9-]+$/,
      message: "must countain only lowercase letters, numbers, and hyphens"
    )
  end
end
