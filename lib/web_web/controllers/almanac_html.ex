defmodule WebWeb.AlmanacHTML do
  @moduledoc """
  The daybook's pages: a week as an engagement calendar opens to it
  (`week.html.heex`), one day (`day.html.heex`), and the year at a glance,
  laid out like a contact sheet (`year.html.heex`). Styled by `assets/css/daybook.css`, which
  also carries the year's print rules — the printed page is the edition.
  """

  use WebWeb, :html

  embed_templates "almanac_html/*"

  @doc """
  An entry's picture at the size a day page shows it: 160 pixels wide. A
  roll's is its contact sheet, so it is asked for at the narrowest width the
  archive keeps rather than as the full preview; a log's poster is small as
  it is.
  """
  def thumb(%{kind: :roll, image: image}), do: Web.Negatives.sized_url(image, 480)
  def thumb(%{image: image}), do: image

  @doc "What a section of a day is called."
  def kind_heading(:post), do: "Writing"
  def kind_heading(:log), do: "Captain's logs"
  def kind_heading(:roll), do: "Film"
  def kind_heading(:ride), do: "Activities"

  @doc "The same, counted: `3 posts`, `1 roll`."
  def kind_count(:post, n), do: plural(n, "post")
  def kind_count(:log, n), do: plural(n, "log")
  def kind_count(:roll, n), do: plural(n, "roll")
  def kind_count(:ride, n), do: plural(n, "activity", "activities")

  defp plural(n, one, many \\ nil)
  defp plural(1, one, _many), do: "1 #{one}"
  defp plural(n, one, nil), do: "#{n} #{one}s"
  defp plural(n, _one, many), do: "#{n} #{many}"

  @doc """
  The year in a sentence, naming only what there was:
  `36 days with work in them: 2 posts and 48 activities, 536.2 mi out and about.`
  Built as one string so template whitespace can't wedge a space before the
  punctuation.
  """
  def year_summary(totals) do
    counts =
      Web.Almanac.kinds()
      |> Enum.filter(&(totals[&1] > 0))
      |> Enum.map(&kind_count(&1, totals[&1]))
      |> join_list()

    distance = if totals.ride > 0, do: ", #{totals.distance} out and about", else: ""
    days = if totals.days == 1, do: "1 day", else: "#{totals.days} days"

    "#{days} with work in them: #{counts}#{distance}."
  end

  defp join_list([one]), do: one
  defp join_list(items), do: Enum.join(Enum.drop(items, -1), ", ") <> " and " <> List.last(items)

  @doc "The address of the week a date falls in."
  def week_path(%Date{} = date), do: Web.Almanac.week_path(date)

  @doc """
  A week in words, as the head of its page: `5–11 October 2026`,
  `28 September – 4 October 2026`, `29 December 2025 – 4 January 2026`.
  """
  def week_span(%Date{} = monday) do
    sunday = Date.add(monday, 6)

    cond do
      monday.month == sunday.month ->
        "#{monday.day}–#{Calendar.strftime(sunday, "%-d %B %Y")}"

      monday.year == sunday.year ->
        "#{Calendar.strftime(monday, "%-d %B")} – #{Calendar.strftime(sunday, "%-d %B %Y")}"

      true ->
        "#{Calendar.strftime(monday, "%-d %B %Y")} – #{Calendar.strftime(sunday, "%-d %B %Y")}"
    end
  end

  @doc "The plate facing a week, at the width the spread shows it."
  def plate_src(%{kind: :roll, image: image}), do: Web.Negatives.sized_url(image, 960)
  def plate_src(%{image: image}), do: image

  @doc "The address of a day."
  def day_path(%Date{} = date), do: ~p"/day/#{Date.to_iso8601(date)}"

  @doc """
  A month as calendar cells, Monday first (the regimen's week): leading
  `nil`s for the days before the 1st, then every date of the month.
  """
  def calendar_cells(%Date{} = first) do
    blanks = List.duplicate(nil, Date.day_of_week(first) - 1)
    blanks ++ Enum.to_list(Date.range(first, Date.end_of_month(first)))
  end

  @doc "What a screen reader hears for a day cell: `18 September: 1 post, 1 activity`."
  def cell_label(date, entries) do
    counts =
      entries
      |> Enum.frequencies_by(& &1.kind)
      |> Enum.sort_by(fn {kind, _} -> Enum.find_index(Web.Almanac.kinds(), &(&1 == kind)) end)
      |> Enum.map_join(", ", fn {kind, n} -> kind_count(kind, n) end)

    "#{Calendar.strftime(date, "%-d %B")}: #{counts}"
  end

  @doc "The kinds present in a day's entries, in the daybook's order, once each."
  def kinds_on(entries) do
    present = MapSet.new(entries, & &1.kind)
    Enum.filter(Web.Almanac.kinds(), &MapSet.member?(present, &1))
  end
end
