defmodule Web.Fitness do
  @moduledoc """
  The Fitness context.
  """

  import Ecto.Query, warn: false
  alias Web.Repo

  alias Web.Fitness.Exercise
  alias Web.Fitness.Biometric

  @doc """
  Returns the list of exercises.
  """
  def list_exercises do
    Repo.all(Exercise)
  end

  @doc """
  Gets a single exercise.

  Raises `Ecto.NoResultsError` if the Exercise does not exist.
  """
  def get_exercise!(id), do: Repo.get!(Exercise, id)

  @doc """
  Gets a single exercise by slug.
  """
  def get_exercise_by_slug(slug) do
    Repo.get_by(Exercise, slug: slug)
  end

  @doc """
  Creates a exercise.
  """
  def create_exercise(attrs \\ %{}) do
    %Exercise{}
    |> Exercise.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a exercise.
  """
  def update_exercise(%Exercise{} = exercise, attrs) do
    exercise
    |> Exercise.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a exercise.
  """
  def delete_exercise(%Exercise{} = exercise) do
    Repo.delete(exercise)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking exercise changes.
  """
  def change_exercise(%Exercise{} = exercise, attrs \\ %{}) do
    Exercise.changeset(exercise, attrs)
  end

  alias Web.Fitness.ExerciseLog

  def create_exercise_log(attrs \\ %{}) do
    %ExerciseLog{}
    |> ExerciseLog.changeset(attrs)
    |> Repo.insert()
  end

  def list_exercise_logs do
    Repo.all(ExerciseLog)
    |> Repo.preload(:exercise)
  end

  def list_biometrics do
    Repo.all(from b in Biometric, order_by: [desc: b.date])
  end

  def get_latest_biometric do
    Repo.one(from b in Biometric, order_by: [desc: b.date], limit: 1)
  end

  def get_biometric!(id), do: Repo.get!(Biometric, id)

  def change_biometric(%Biometric{} = biometric, attrs \\ %{}) do
    Biometric.changeset(biometric, attrs)
  end

  def create_biometric(attrs \\ %{}) do
    %Biometric{}
    |> Biometric.changeset(attrs)
    |> Repo.insert()
  end

  def update_biometric(%Biometric{} = biometric, attrs) do
    biometric
    |> Biometric.changeset(attrs)
    |> Repo.update()
  end

  def delete_biometric(%Biometric{} = biometric) do
    Repo.delete(biometric)
  end

  alias Web.Fitness.WorkoutSession
  alias Web.Fitness.WorkoutSet

  def create_workout_session(attrs \\ %{}) do
    %WorkoutSession{}
    |> WorkoutSession.changeset(attrs)
    |> Repo.insert()
  end

  def get_or_create_todays_session do
    today = Date.utc_today()

    case Repo.get_by(WorkoutSession, date: today) do
      nil -> create_workout_session(%{date: today, name: "Daily Workout"})
      session -> {:ok, session}
    end
  end

  def add_workout_set(attrs \\ %{}) do
    %WorkoutSet{}
    |> WorkoutSet.changeset(attrs)
    |> Repo.insert()
  end

  def get_last_set_for_exercise(exercise_id) do
    Repo.one(
      from s in WorkoutSet,
        where: s.exercise_id == ^exercise_id,
        order_by: [desc: s.inserted_at],
        limit: 1
    )
  end

  def list_recent_active_muscles(days \\ 2) do
    cutoff = Date.utc_today() |> Date.add(-days)

    query =
      from s in WorkoutSet,
        join: sess in assoc(s, :workout_session),
        join: e in assoc(s, :exercise),
        where: sess.date >= ^cutoff,
        distinct: true,
        select: e.muscle_group

    Repo.all(query)
  end
end
