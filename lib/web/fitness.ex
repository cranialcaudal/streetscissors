defmodule Web.Fitness do
  @moduledoc """
  The Fitness context.
  """

  import Ecto.Query, warn: false
  alias Web.Repo

  alias Web.Fitness.Exercise

  @doc """
  Returns the list of exercises.
  """
  def list_exercises do
    Repo.all(Exercise)
  end

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

  alias Web.Fitness.ExerciseLog

  @doc """
  The exercise a log entry is filed under, for a slug from the regimen:
  `{:ok, %Exercise{}}` or `:error`.

  **The wiki is what says an exercise exists**, not this table. The
  `exercises` table was seeded once, long before the wiki was rewritten, and
  by October 2026 it knew 17 of the wiki's 126 exercises, so the Log button
  on nearly every line answered "not wired up for logging". A log needs a row
  to hang from, so the row is made the first time an exercise is logged,
  from the wiki's own name and muscle group.
  """
  def loggable_exercise(slug) when is_binary(slug) do
    case get_exercise_by_slug(slug) do
      %Exercise{} = exercise ->
        {:ok, exercise}

      nil ->
        with {:ok, wiki, _body} <- Web.Fitness.Vault.get_exercise_raw(slug),
             {:ok, exercise} <-
               create_exercise(%{
                 slug: slug,
                 name: wiki.name,
                 muscle_group: wiki.muscle_group && to_string(wiki.muscle_group)
               }) do
          {:ok, exercise}
        else
          # Two presses at once: the other one made the row.
          {:error, %Ecto.Changeset{}} ->
            case get_exercise_by_slug(slug) do
              %Exercise{} = exercise -> {:ok, exercise}
              nil -> :error
            end

          _ ->
            :error
        end
    end
  end

  def loggable_exercise(_slug), do: :error

  def create_exercise_log(attrs \\ %{}) do
    %ExerciseLog{}
    |> ExerciseLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc "The most recent entry for an exercise, or nil: what there is to beat."
  def last_exercise_log(exercise_id) do
    Repo.one(
      from l in ExerciseLog,
        where: l.exercise_id == ^exercise_id,
        order_by: [desc: l.date, desc: l.id],
        limit: 1
    )
  end

  @doc "Everything logged on a day, in the order it was entered, exercise loaded."
  def exercise_logs_on(%Date{} = date) do
    Repo.all(
      from l in ExerciseLog, where: l.date == ^date, order_by: [asc: l.id], preload: :exercise
    )
  end

  def delete_exercise_log(id) do
    case Repo.get(ExerciseLog, id) do
      nil -> {:ok, nil}
      log -> Repo.delete(log)
    end
  end

  def list_exercise_logs do
    Repo.all(ExerciseLog)
    |> Repo.preload(:exercise)
  end
end
