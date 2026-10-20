defmodule Web.Fitness.Checkin do
  @moduledoc """
  A day's check-in: one answer per check the vault defines
  (`Web.Fitness.Checks`, from `content/fitness/checkins.md`), keyed by the
  check's id — `%{"achilles" => "talking", "bodyweight" => "171.4"}` — and a
  note. One a day. The admin's only: no public page reads this table.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "fitness_checkins" do
    field :date, :date
    field :answers, :map, default: %{}
    field :note, :string

    timestamps()
  end

  @doc false
  def changeset(checkin, attrs, checks \\ []) do
    checkin
    |> cast(attrs, [:date, :answers, :note])
    |> validate_required([:date])
    |> update_change(:answers, &clean/1)
    |> validate_numbers(checks)
    |> unique_constraint(:date)
  end

  # A number check's answer is a measurement: "171.4", never "heavy".
  defp validate_numbers(changeset, checks) do
    answers = get_field(changeset, :answers) || %{}

    Enum.reduce(checks, changeset, fn
      %{kind: :number, id: id, label: label}, cs ->
        case answers[id] do
          nil ->
            cs

          text ->
            if Regex.match?(~r/\A-?\d+(?:\.\d+)?\z/, text),
              do: cs,
              else: add_error(cs, :answers, "#{label} must be a number")
        end

      _check, cs ->
        cs
    end)
  end

  # Blank answers are no answer: a check skipped today says nothing.
  defp clean(answers) when is_map(answers) do
    for {k, v} <- answers,
        v = String.trim(to_string(v)),
        v != "",
        into: %{},
        do: {to_string(k), v}
  end

  defp clean(_), do: %{}
end
