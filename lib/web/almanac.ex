defmodule Web.Almanac do
  @moduledoc """
  The daybook (`/daybook`; "the almanac" until 2026-10-07, and this module
  keeps that name). The site read by date, in the manner of an engagement calendar: a week to
  an opening, a picture facing seven ruled days, with a day's page behind
  each date and the year at a glance at the front.

  A feed slices a person into formats and hands them over one at a time. The
  almanac does the opposite — it puts the essay, the recording, the roll of
  film and the ride from one day side by side, and lays a whole year out like
  a contact sheet. Nothing new is stored: every section already dates its
  work, and this only reads those dates.

    * posts — `Web.Blog`, the frontmatter `date` (or the file's mtime)
    * logs — `Web.Audio`, `recorded_on`, published and transcoded only
    * rolls — `Web.Negatives`, the sheet's date, which is the day the roll
      was scanned: the day it came out of the tank, not the day it was shot
    * activities — `Web.Rides`, the Pacific-local day it started

  **Only dates, never times.** The public site does not say when he is out
  of the house (see `WebWeb.FitnessWeek`), so an activity is a day and a
  distance here, never an hour.
  """

  alias Web.{Audio, Blog, Negatives, Rides}
  alias Web.Audio.Log
  alias Web.Rides.Units

  # Order within a day, and the order kinds are listed in everywhere.
  @kinds [:post, :log, :roll, :ride]

  @type entry :: %{
          kind: :post | :log | :roll | :ride,
          date: Date.t(),
          title: String.t(),
          path: String.t(),
          note: String.t() | nil,
          image: String.t() | nil
        }

  def kinds, do: @kinds

  @doc "Every dated piece on the site, newest day first."
  @spec entries() :: [entry()]
  def entries do
    (posts() ++ logs() ++ rolls() ++ rides())
    |> Enum.sort_by(&{Date.to_gregorian_days(&1.date) * -1, kind_index(&1.kind)})
  end

  @doc """
  One day: its entries in kind order, plus the nearest days either side that
  have anything on them (`nil` at the ends). `:error` when the day is empty —
  an empty day is not a page.
  """
  def day(%Date{} = date, entries \\ entries()) do
    case Enum.filter(entries, &(&1.date == date)) do
      [] ->
        :error

      on_day ->
        dates = entries |> Enum.map(& &1.date) |> Enum.uniq()

        {:ok,
         %{
           date: date,
           entries: Enum.sort_by(on_day, &kind_index(&1.kind)),
           previous:
             dates
             |> Enum.filter(&(Date.compare(&1, date) == :lt))
             |> Enum.max(Date, fn -> nil end),
           next:
             dates
             |> Enum.filter(&(Date.compare(&1, date) == :gt))
             |> Enum.min(Date, fn -> nil end)
         }}
    end
  end

  @doc """
  One week, Monday to Sunday, as an engagement calendar lays it out:

      %{monday, year, week, days: [%{date, entries, observance, training}],
        plate, month, previous, next}

  `year` and `week` are the ISO week's, which is what the address carries.
  Each day has its entries, the day the Church keeps when it is more than a
  weekday (`observance`, as a printed calendar marks its holidays), and, from
  `today` on, the regimen's one word for that weekday (`training`): what is
  written in a diary ahead of time. Days already gone say only what was made.

  `plate` is the picture facing the week: a roll or recording from the week
  itself, else a roll from the archive chosen by the week's number, so the
  same week always shows the same picture. `previous` and `next` are the
  nearest weeks either side that have work in them, as with days.

  `:error` for a week with nothing in it, unless it is the week `today` is
  in: the current week is always a page, blank lines and all.
  """
  def week(%Date{} = date, entries \\ entries(), today \\ Web.Clock.local_today()) do
    monday = Date.beginning_of_week(date)
    days = Date.range(monday, Date.add(monday, 6))
    by_day = entries |> Enum.filter(&(&1.date in days)) |> Enum.group_by(& &1.date)

    if by_day == %{} and monday != Date.beginning_of_week(today) do
      :error
    else
      {year, week} = :calendar.iso_week_number(Date.to_erl(monday))
      mondays = entries |> Enum.map(&Date.beginning_of_week(&1.date)) |> Enum.uniq()
      themes = training_themes()

      {:ok,
       %{
         monday: monday,
         year: year,
         week: week,
         days:
           for day <- days do
             %{
               date: day,
               entries: by_day |> Map.get(day, []) |> Enum.sort_by(&kind_index(&1.kind)),
               observance: observance(day),
               training: Date.compare(day, today) != :lt && themes[Date.day_of_week(day)]
             }
           end,
         plate: plate(by_day, week),
         # The month most of the week is in.
         month: monday |> Date.add(3) |> Date.beginning_of_month(),
         work_days: entries |> Enum.map(& &1.date) |> MapSet.new(),
         previous:
           mondays
           |> Enum.filter(&(Date.compare(&1, monday) == :lt))
           |> Enum.max(Date, fn -> nil end),
         next:
           mondays
           |> Enum.filter(&(Date.compare(&1, monday) == :gt))
           |> Enum.min(Date, fn -> nil end)
       }}
    end
  end

  @doc "The Monday of an ISO week, or `:error` when that year has no such week."
  def monday_of(year, week) when is_integer(year) and is_integer(week) and week in 1..53 do
    # The fourth of January is always in week one.
    with {:ok, fourth} <- Date.new(year, 1, 4) do
      monday = fourth |> Date.beginning_of_week() |> Date.add((week - 1) * 7)

      case :calendar.iso_week_number(Date.to_erl(monday)) do
        {^year, ^week} -> {:ok, monday}
        _ -> :error
      end
    end
  end

  def monday_of(_year, _week), do: :error

  @doc "The address of the week a date falls in."
  def week_path(%Date{} = date) do
    {year, week} =
      date |> Date.beginning_of_week() |> Date.to_erl() |> :calendar.iso_week_number()

    "/daybook/#{year}/week/#{week}"
  end

  # What a printed calendar puts in small type beside the date. A weekday of
  # the season is no observance; a Sunday is, by its own name.
  defp observance(date) do
    case Web.Liturgy.Calendar.day(date).celebration do
      %{rank: :weekday} -> nil
      %{title: title} -> title
    end
  rescue
    _ -> nil
  end

  # The regimen's word for each weekday (1 = Monday), from the vault.
  defp training_themes do
    slugs = ~w(monday tuesday wednesday thursday friday saturday sunday)

    for day <- Web.Fitness.Vault.list_days(),
        index = Enum.find_index(slugs, &(&1 == day.slug)),
        is_binary(day.theme) and day.theme != "",
        into: %{},
        do: {index + 1, day.theme}
  rescue
    _ -> %{}
  end

  defp plate(by_day, week) do
    made =
      by_day
      |> Enum.sort_by(fn {date, _} -> date end, Date)
      |> Enum.flat_map(fn {_, list} -> list end)
      |> Enum.filter(& &1.image)

    case Enum.find(made, &(&1.kind == :roll)) || List.first(made) do
      nil ->
        archive_plate(week)

      entry ->
        %{
          image: entry.image,
          kind: entry.kind,
          title: entry.title,
          path: entry.path,
          of_week: true
        }
    end
  end

  defp archive_plate(week) do
    case Negatives.list_contact_sheets() do
      [] ->
        nil

      sheets ->
        sheet = Enum.at(sheets, rem(week, length(sheets)))

        %{
          image: sheet.preview_url,
          kind: :roll,
          title: "Roll #{sheet.roll}",
          path: "/negatives/roll/#{sheet.roll}",
          of_week: false
        }
    end
  rescue
    _ -> nil
  end

  @doc "Years with anything in them, newest first."
  def years(entries \\ entries()) do
    entries |> Enum.map(& &1.date.year) |> Enum.uniq() |> Enum.sort(:desc)
  end

  @doc """
  A year laid out month by month: `%{year, months, totals, previous, next}`,
  where each month is `%{month, first, days}` and `days` maps a date to its
  entries. `:error` for a year with nothing in it.
  """
  def year(year, entries \\ entries()) when is_integer(year) do
    in_year = Enum.filter(entries, &(&1.date.year == year))

    if in_year == [] do
      :error
    else
      by_day = Enum.group_by(in_year, & &1.date)
      years = years(entries)

      months =
        for month <- 1..12 do
          first = Date.new!(year, month, 1)

          %{
            month: month,
            first: first,
            days:
              by_day
              |> Enum.filter(fn {date, _} -> date.month == month end)
              |> Map.new(fn {date, list} -> {date, Enum.sort_by(list, &kind_index(&1.kind))} end)
          }
        end

      {:ok,
       %{
         year: year,
         months: months,
         totals: totals(in_year, year),
         previous: years |> Enum.filter(&(&1 < year)) |> Enum.max(fn -> nil end),
         next: years |> Enum.filter(&(&1 > year)) |> Enum.min(fn -> nil end)
       }}
    end
  end

  defp totals(in_year, year) do
    counts = Enum.frequencies_by(in_year, & &1.kind)

    distance =
      Rides.list_rides()
      |> Rides.yearly_totals()
      |> Enum.find_value(0.0, &(&1.year == year && &1.distance_m))

    Map.merge(Map.new(@kinds, &{&1, Map.get(counts, &1, 0)}), %{
      distance: Units.distance(distance),
      days: in_year |> Enum.map(& &1.date) |> Enum.uniq() |> length()
    })
  end

  # --- Sources ---

  defp posts do
    for post <- Blog.list_posts() do
      %{
        kind: :post,
        date: post.date,
        title: post.title,
        path: "/blog/#{post.slug}",
        note: "#{post.word_count} words",
        image: nil
      }
    end
  end

  defp logs do
    for log <- Audio.list_ready_logs(), %Date{} <- [log.recorded_on] do
      %{
        kind: :log,
        date: log.recorded_on,
        title: log_title(log),
        path: "/logs/#{log.slug}",
        note: log_note(log),
        image: Log.poster_url(log)
      }
    end
  end

  defp rolls do
    for sheet <- Negatives.list_contact_sheets(),
        {:ok, date} <- [Date.from_iso8601(to_string(sheet.date))] do
      %{
        kind: :roll,
        date: date,
        title: "Roll #{sheet.roll}",
        path: "/negatives/roll/#{sheet.roll}",
        note: "#{sheet.format} #{color_word(sheet.color)}",
        image: sheet.preview_url
      }
    end
  end

  defp rides do
    for ride <- Rides.list_rides() do
      %{
        kind: :ride,
        date: Web.Clock.local_today(ride.started_at),
        title: ride.name || Units.sport(ride.sport),
        path: "/fitness/rides/#{ride.id}",
        note: "#{Units.sport(ride.sport)} · #{Units.distance(ride.distance_m)}",
        image: nil
      }
    end
  end

  # A log's own title *is* its date, which a day page already says, so it is
  # named by its caption when it has one and by what it is when it doesn't.
  defp log_title(%Log{caption: caption} = log) when is_binary(caption) and caption != "" do
    if Log.ordinal(log), do: "Entry #{Log.ordinal(log)} — #{caption}", else: caption
  end

  defp log_title(%Log{} = log) do
    kind = if Log.video?(log), do: "Video log", else: "Audio log"
    if Log.ordinal(log), do: "#{kind}, entry #{Log.ordinal(log)}", else: kind
  end

  defp log_note(%Log{duration: seconds} = log) when is_integer(seconds) and seconds > 0 do
    "#{if Log.video?(log), do: "video", else: "audio"} · #{div(seconds, 60)}:#{String.pad_leading("#{rem(seconds, 60)}", 2, "0")}"
  end

  defp log_note(log), do: if(Log.video?(log), do: "video", else: "audio")

  defp color_word("bw"), do: "black and white"
  defp color_word("color"), do: "colour"
  defp color_word(other), do: other

  defp kind_index(kind), do: Enum.find_index(@kinds, &(&1 == kind))
end
