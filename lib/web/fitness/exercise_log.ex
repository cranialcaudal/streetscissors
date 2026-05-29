defmodule Web.Fitness.ExerciseLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "exercise_logs" do
    belongs_to :exercise, Web.Fitness.Exercise
    field :date, :date
    field :metrics, :map
    field :note, :string

    timestamps()
  end

  @doc false
  def changeset(exercise_log, attrs) do
    exercise_log
    |> cast(attrs, [:exercise_id, :date, :metrics, :note])
    |> validate_required([:exercise_id, :date, :metrics])
  end
end
