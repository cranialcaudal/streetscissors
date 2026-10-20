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

  @doc "Every entry for an exercise by its slug, exercise loaded; `[]` when it has none."
  def exercise_logs_for(slug) when is_binary(slug) do
    Repo.all(
      from l in ExerciseLog,
        join: e in assoc(l, :exercise),
        where: e.slug == ^slug,
        order_by: [asc: l.date, asc: l.id],
        preload: [exercise: e]
    )
  end

  @doc "A log entry's values in a line: `185 lbs · 3 x 8 @ RPE 8 · 40 m`."
  def entry_line(%{metrics: metrics, note: note}) do
    work =
      case {metrics["sets"], metrics["reps"]} do
        {nil, nil} -> nil
        {sets, nil} -> "#{sets} sets"
        {nil, reps} -> "#{reps} reps"
        {sets, reps} -> "#{sets} x #{reps}"
      end

    work = if(work && metrics["rpe"], do: "#{work} @ RPE #{metrics["rpe"]}", else: work)

    values =
      [metrics["weight"], work, metrics["distance"], metrics["time"], metrics["result"]]
      |> Enum.reject(&is_nil/1)

    Enum.join(values ++ List.wrap(note), " · ")
  end

  @doc "Everything logged on a day, in the order it was entered, exercise loaded."
  def exercise_logs_on(%Date{} = date) do
    Repo.all(
      from l in ExerciseLog, where: l.date == ^date, order_by: [asc: l.id], preload: :exercise
    )
  end

  @doc "One entry by id, its exercise loaded; nil when there is none."
  def get_exercise_log(id) do
    case Repo.get(ExerciseLog, id) do
      nil -> nil
      log -> Repo.preload(log, :exercise)
    end
  end

  @doc "Changes an entry's date, figures or note. Its exercise stays."
  def update_exercise_log(%ExerciseLog{} = log, attrs) do
    log
    |> ExerciseLog.changeset(Map.drop(attrs, [:exercise_id, "exercise_id"]))
    |> Repo.update()
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

  # --- Check-ins (the training block's guardrails read these) ---

  alias Web.Fitness.Checkin

  @doc "The check-in for a day, or nil."
  def checkin_on(%Date{} = date), do: Repo.get_by(Checkin, date: date)

  @doc "Check-ins on or before a day, newest first."
  def recent_checkins(%Date{} = date, limit \\ 14) do
    Repo.all(from c in Checkin, where: c.date <= ^date, order_by: [desc: c.date], limit: ^limit)
  end

  @doc "Check-ins between two days, oldest first."
  def checkins_between(%Date{} = from, %Date{} = to) do
    Repo.all(
      from c in Checkin,
        where: c.date >= ^from and c.date <= ^to,
        order_by: [asc: c.date]
    )
  end

  @doc """
  Records a day's check-in, replacing the one already made that day. The
  date may be a `Date` or the form's ISO string. `checks` are the vault's
  (`Web.Fitness.Checks.all/0`): a number check's answer must be a number.
  """
  def save_checkin(attrs, checks \\ []) do
    existing =
      case attrs["date"] || attrs[:date] do
        %Date{} = date ->
          checkin_on(date)

        text when is_binary(text) ->
          with {:ok, date} <- Date.from_iso8601(text), do: checkin_on(date), else: (_ -> nil)

        _ ->
          nil
      end

    (existing || %Checkin{})
    |> Checkin.changeset(attrs, checks)
    |> Repo.insert_or_update()
  end

  def change_checkin(checkin \\ %Checkin{}, attrs \\ %{}), do: Checkin.changeset(checkin, attrs)
end
