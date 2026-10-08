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
  alias Web.Fitness.Vault

  # --- The training log ---
  #
  # Entries are filed under the exercise wiki's slugs (`Web.Fitness.Vault`),
  # so anything the regimen links to can be logged. Reading and writing are
  # the admin's alone; callers gate on the session.

  @doc """
  Records what was done of the wiki's exercise `slug`. `attrs` are the log
  form's string keys: `"weight"` (pounds), `"sets"`, `"reps"`, the free-text
  `"distance"`, `"time"` and `"result"`, `"note"`, and `"date"` (today by the
  Pacific clock when absent). `{:error, :unknown_exercise}` when the wiki has
  no such file.
  """
  def log_exercise(slug, attrs) when is_binary(slug) and is_map(attrs) do
    if MapSet.member?(Vault.exercise_slugs(), slug) do
      metrics =
        for key <- ExerciseLog.metric_keys(),
            value = String.trim(to_string(attrs[key] || "")),
            value != "",
            into: %{},
            do: {key, value}

      %ExerciseLog{}
      |> ExerciseLog.changeset(%{
        "slug" => slug,
        "date" => presence(attrs["date"]) || Web.Clock.local_today(),
        "weight" => attrs["weight"],
        "sets" => attrs["sets"],
        "reps" => attrs["reps"],
        "note" => attrs["note"],
        "metrics" => metrics
      })
      |> Repo.insert()
    else
      {:error, :unknown_exercise}
    end
  end

  @doc """
  The log, newest first. `slug:` keeps one exercise, `limit:` the newest so
  many.
  """
  def list_exercise_logs(opts \\ []) do
    ExerciseLog
    |> order_by([l], desc: l.date, desc: l.id)
    |> then(fn query ->
      case opts[:slug] do
        nil -> query
        slug -> where(query, [l], l.slug == ^slug)
      end
    end)
    |> then(fn query ->
      case opts[:limit] do
        nil -> query
        limit -> limit(query, ^limit)
      end
    end)
    |> Repo.all()
  end

  @doc "The heaviest weight on file for an exercise, or nil."
  def best_weight(slug) do
    Repo.one(from l in ExerciseLog, where: l.slug == ^slug, select: max(l.weight))
  end

  @doc "Every slug with an entry, and how many, most logged first."
  def logged_exercises do
    Repo.all(
      from l in ExerciseLog,
        where: not is_nil(l.slug),
        group_by: l.slug,
        order_by: [desc: count(l.id), asc: l.slug],
        select: {l.slug, count(l.id)}
    )
  end

  def delete_exercise_log(id) do
    case Repo.get(ExerciseLog, id) do
      nil -> {:error, :not_found}
      log -> Repo.delete(log)
    end
  end

  @doc """
  An entry in a line: `135 lb · 3 × 8 · 2 miles`. The note is not part of it.
  """
  def describe_log(%ExerciseLog{} = log) do
    volume =
      case {log.sets, log.reps} do
        {nil, nil} -> nil
        {sets, nil} -> "#{sets} sets"
        {nil, reps} -> "#{reps} reps"
        {sets, reps} -> "#{sets} × #{reps}"
      end

    rest = for key <- ExerciseLog.metric_keys(), value = (log.metrics || %{})[key], do: value

    [log.weight && "#{format_weight(log.weight)} lb", volume | rest]
    |> Enum.filter(& &1)
    |> Enum.join(" · ")
  end

  @doc "Pounds without a needless decimal: `135`, `22.5`."
  def format_weight(weight) when is_number(weight) do
    if weight == trunc(weight),
      do: Integer.to_string(trunc(weight)),
      else: weight |> Float.round(2) |> Float.to_string()
  end

  defp presence(nil), do: nil
  defp presence(%Date{} = date), do: date
  defp presence(text), do: if(String.trim(text) == "", do: nil, else: text)

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
