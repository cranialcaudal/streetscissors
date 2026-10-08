defmodule Web.Fitness.ExerciseLog do
  @moduledoc """
  One entry in the training log: what was done of one exercise on one day.

  `slug` is the exercise's file name in the vault's wiki. `weight` is in
  pounds; with `sets` and `reps` it is the part of an entry that can be
  compared with the last one. Distance, time and a free "result" stay as text
  in `metrics`, as the CSV export has always read them. `exercise_id` is the
  old link to the `exercises` table and is no longer needed.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @metric_keys ~w(distance time result)

  schema "exercise_logs" do
    belongs_to :exercise, Web.Fitness.Exercise
    field :slug, :string
    field :date, :date
    field :weight, :float
    field :sets, :integer
    field :reps, :integer
    field :metrics, :map, default: %{}
    field :note, :string

    timestamps()
  end

  def metric_keys, do: @metric_keys

  @doc false
  def changeset(exercise_log, attrs) do
    exercise_log
    |> cast(attrs, [:exercise_id, :slug, :date, :weight, :sets, :reps, :metrics, :note])
    |> update_change(:note, &blank_to_nil/1)
    |> validate_required([:slug, :date])
    |> validate_number(:weight, greater_than_or_equal_to: 0, less_than: 2000)
    |> validate_number(:sets, greater_than: 0, less_than: 100)
    |> validate_number(:reps, greater_than: 0, less_than: 1000)
    |> validate_says_something()
  end

  # An entry with nothing in it is a slip of the thumb, not a record.
  defp validate_says_something(changeset) do
    filled? =
      Enum.any?([:weight, :sets, :reps, :note], &get_field(changeset, &1)) or
        (get_field(changeset, :metrics) || %{}) != %{}

    if filled?, do: changeset, else: add_error(changeset, :base, "is empty")
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(text), do: if(String.trim(text) == "", do: nil, else: String.trim(text))
end
