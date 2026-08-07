defmodule Web.Clock do
  @moduledoc """
  US Pacific local date without a timezone-database dependency.

  DST rule: UTC-7 (PDT) from 10:00 UTC on the second Sunday of March until
  09:00 UTC on the first Sunday of November; UTC-8 (PST) otherwise. Good
  until Congress changes the rule — acceptable for highlighting today's
  workout.
  """

  @week ~w[monday tuesday wednesday thursday friday saturday sunday]

  def local_today(now \\ DateTime.utc_now()) do
    offset_hours = if dst?(now), do: -7, else: -8

    now
    |> DateTime.add(offset_hours * 3600, :second)
    |> DateTime.to_date()
  end

  @doc "Weekday slug (\"monday\"..\"sunday\") for the Pacific-local date."
  def today_slug(now \\ DateTime.utc_now()) do
    Enum.at(@week, Date.day_of_week(local_today(now)) - 1)
  end

  defp dst?(%DateTime{year: year} = now) do
    dst_start = nth_sunday_at(year, 3, 2, 10)
    dst_end = nth_sunday_at(year, 11, 1, 9)

    DateTime.compare(now, dst_start) != :lt and DateTime.compare(now, dst_end) == :lt
  end

  defp nth_sunday_at(year, month, nth, hour_utc) do
    first = Date.new!(year, month, 1)
    days_until_sunday = rem(7 - Date.day_of_week(first), 7)
    day = 1 + days_until_sunday + (nth - 1) * 7
    DateTime.new!(Date.new!(year, month, day), Time.new!(hour_utc, 0, 0), "Etc/UTC")
  end
end
