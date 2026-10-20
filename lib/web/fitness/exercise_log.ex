defmodule Web.Fitness.ExerciseLog do
  @moduledoc """
  One logged set of an exercise: the day, the figures (`metrics`: weight,
  sets, reps, RPE and so on, kept as the strings the form took), and a note.
  `Web.Fitness.Progression.parse_log_metrics/1` reads the figures back as
  numbers. The exercise itself is a row of `Web.Fitness.Exercise`, made the
  first time it is logged.
  """

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
