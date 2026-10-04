defmodule Web.Almanac do
  @moduledoc """
  The site read by date: everything made on a day, and a year seen at once.

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
