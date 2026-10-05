defmodule Web.Rides.Workout do
  @moduledoc """
  One Apple Health workout: the heart rate and energy the watch measured
  while Komoot recorded the tour. Komoot keeps neither, so this is the only
  place they live.

  A workout is not tied to a ride when stored: `Web.Rides.attach_health/1`
  pairs them by start time when read, so it doesn't matter which of the two
  arrives first. `hk_id` identifies the workout to whatever sent it — an
  export's own id, or its activity and start — which makes a second import of
  the same workout an update rather than a duplicate.

  `hr_trace` is the heart rate over the workout as a flat list of
  `offset_s, bpm` pairs — `[0, 96, 60, 118, …]` — downsampled when stored.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "health_workouts" do
    field :hk_id, :string
    field :activity, :string
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime
    field :active_kcal, :integer
    field :avg_hr, :integer
    field :max_hr, :integer
    field :min_hr, :integer
    field :hr_trace, {:array, :integer}, default: []

    timestamps()
  end

  @fields ~w(hk_id activity started_at ended_at active_kcal avg_hr max_hr min_hr hr_trace)a

  @doc false
  def changeset(workout, attrs) do
    workout
    |> cast(attrs, @fields)
    |> validate_required([:hk_id, :started_at])
    |> unique_constraint(:hk_id)
  end

  @doc "The trace as `[{offset_s, bpm}]` pairs."
  def trace(%__MODULE__{hr_trace: flat}) when is_list(flat) do
    flat |> Enum.chunk_every(2, 2, :discard) |> Enum.map(fn [t, bpm] -> {t, bpm} end)
  end

  def trace(_workout), do: []

  @doc "How long the workout ran, in seconds, or nil when it has no end."
  def duration_s(%__MODULE__{started_at: %DateTime{} = from, ended_at: %DateTime{} = to}),
    do: max(DateTime.diff(to, from), 0)

  def duration_s(_workout), do: nil
end
