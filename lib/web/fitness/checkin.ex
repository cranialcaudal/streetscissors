defmodule Web.Fitness.Checkin do
  @moduledoc """
  A day's check-in during a training block: pain (the Achilles, or the
  worst joint) and soreness and energy out of ten, hours slept, and a note.
  One a day. The admin's only: no public page reads this table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "fitness_checkins" do
    field :date, :date
    field :pain, :integer
    field :sleep_hours, :float
    field :soreness, :integer
    field :energy, :integer
    field :note, :string

    timestamps()
  end

  @doc false
  def changeset(checkin, attrs) do
    checkin
    |> cast(attrs, [:date, :pain, :sleep_hours, :soreness, :energy, :note])
    |> validate_required([:date])
    |> validate_number(:pain, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:soreness, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:energy, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:sleep_hours, greater_than_or_equal_to: 0, less_than_or_equal_to: 24)
    |> unique_constraint(:date)
  end
end
