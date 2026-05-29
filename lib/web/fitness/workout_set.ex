defmodule Web.Fitness.WorkoutSet do
  use Ecto.Schema
  import Ecto.Changeset

  schema "workout_sets" do
    field :reps, :integer
    field :weight, :decimal
    field :rpe, :integer
    field :notes, :string

    belongs_to :exercise, Web.Fitness.Exercise
    belongs_to :workout_session, Web.Fitness.WorkoutSession

    timestamps()
  end

  @doc false
  def changeset(workout_set, attrs) do
    workout_set
    |> cast(attrs, [:reps, :weight, :rpe, :notes, :exercise_id, :workout_session_id])
    |> validate_required([:exercise_id, :workout_session_id])
  end
end
