defmodule Web.Fitness.WorkoutSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "workout_sessions" do
    field :name, :string
    field :date, :date
    field :is_admin, :boolean, default: false
    field :user_id, :integer

    has_many :workout_sets, Web.Fitness.WorkoutSet

    timestamps()
  end

  @doc false
  def changeset(workout_session, attrs) do
    workout_session
    |> cast(attrs, [:name, :date, :is_admin, :user_id])
    |> validate_required([:date])
  end
end
