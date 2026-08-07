defmodule Web.Fitness.Rotation do
  @moduledoc """
  Which option of a rotating day is on this week.

  Friday alternates between the office swim and a remote fartlek run; Saturday
  runs a four-week cycle. Both were previously described only in prose in the
  markdown — and `Web.Fitness.Vault.checklist_only/1` strips prose, so the
  public page never showed which week it was, or in Friday's case that a second
  option existed at all.

  The index comes from the **ISO week number**, so there is no anchor date to
  drift, nothing to persist, and no state to get out of step with the calendar.
  Week 1 of any year is option 1.
  """

  @doc """
  Zero-based index of the option in rotation for `date`, given how many options
  the day has.

      iex> Web.Fitness.Rotation.index(2, ~D[2026-01-01])   # ISO week 1
      0
      iex> Web.Fitness.Rotation.index(2, ~D[2026-01-08])   # ISO week 2
      1
  """
  @spec index(pos_integer(), Date.t()) :: non_neg_integer()
  def index(count, date \\ Web.Clock.local_today())

  def index(count, _date) when count <= 1, do: 0

  def index(count, date) do
    rem(week_number(date) - 1, count)
  end

  @doc """
  Marks the option in rotation. Takes a list and returns `{item, active?}`
  pairs, so callers do not have to carry the index around.
  """
  @spec mark([any()], Date.t()) :: [{any(), boolean()}]
  def mark(options, date \\ Web.Clock.local_today())

  def mark([], _date), do: []

  def mark(options, date) do
    active = index(length(options), date)
    Enum.with_index(options, fn option, i -> {option, i == active} end)
  end

  @doc """
  ISO-8601 week number for a date. Weeks belong to the year that owns them, so
  a date can sit in week 53 of the previous year — `:calendar` handles that,
  and the rotation only cares about the week, not the year it belongs to.
  """
  @spec week_number(Date.t()) :: pos_integer()
  def week_number(date) do
    {_iso_year, week} = :calendar.iso_week_number(Date.to_erl(date))
    week
  end
end
