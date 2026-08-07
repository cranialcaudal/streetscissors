defmodule WebWeb.EnglandController do
  use WebWeb, :controller

  @base_path "content/england2026"

  # One entry per trip day (July 2026). `song` is the Beatles track of the day.
  @trip_days [
    %{date: 5, title: "Sacramento → London", song: "Ticket to Ride", icon: "✈️"},
    %{date: 6, title: "Arrive London · Soho Circuit", song: "Magical Mystery Tour", icon: "🕶️"},
    %{date: 7, title: "Euston → Penrith · Evening Hike", song: "Octopus's Garden", icon: "🚂"},
    %{date: 8, title: "The Fred Whitton Challenge", song: "Helter Skelter", icon: "🚴"},
    %{date: 9, title: "Buttermere: Dip · Ride · Fell Run", song: "Here Comes the Sun", icon: "⛰️"},
    %{date: 10, title: "Back to London · AAIC Kickoff", song: "Get Back", icon: "🚂"},
    %{
      date: 11,
      title: "PIA Day · Drinks with James",
      song: "With a Little Help from My Friends",
      icon: "🍻"
    },
    %{date: 12, title: "AAIC Day 1 · British Museum", song: "Paperback Writer", icon: "🔬"},
    %{date: 13, title: "AAIC Day 2 · Tate Modern", song: "Tomorrow Never Knows", icon: "🎨"},
    %{date: 14, title: "AAIC Day 3 · Tower by Night", song: "Good Night", icon: "🏰"},
    %{date: 15, title: "AAIC Final · Rough Trade East", song: "Revolution", icon: "💿"},
    %{date: 16, title: "London → Dover · 134 mi", song: "The Long and Winding Road", icon: "🌊"},
    %{date: 17, title: "London → Sacramento", song: "Golden Slumbers", icon: "🏠"}
  ]

  # NOTE: this action must not be named `call` — controllers are Plugs, and
  # defining call/2 overrides the Plug entry point, 500ing every route here.
  def call_times(conn, _params) do
    render(conn, :call_times,
      page_title: "When to Call — England 2026",
      hide_header: true
    )
  end

  def show(conn, _params) do
    render(conn, :show,
      checklist: read_markdown("checklist.md") |> render_task_lists(),
      itinerary: read_markdown("itinerary.md"),
      calendar_weeks: calendar_weeks(~D[2026-07-01]),
      trip_days: trip_days_by_date(),
      page_title: "England 2026",
      hide_header: true
    )
  end

  defp trip_days_by_date do
    @trip_days
    |> Enum.with_index(1)
    |> Map.new(fn {day, num} -> {day.date, Map.put(day, :num, num)} end)
  end

  # Sunday-first weeks of the given month as lists of day numbers, nil-padded.
  defp calendar_weeks(first_of_month) do
    lead = Date.day_of_week(first_of_month, :sunday) - 1
    cells = List.duplicate(nil, lead) ++ Enum.to_list(1..Date.days_in_month(first_of_month))
    pad = rem(7 - rem(length(cells), 7), 7)
    Enum.chunk_every(cells ++ List.duplicate(nil, pad), 7)
  end

  # Earmark's GFM mode doesn't cover task lists, so `- [ ]` / `- [x]` arrive as
  # literal text inside <li>. Swap the markers for real checkboxes that the
  # page's localStorage persistence script can find and remember.
  defp render_task_lists(html) do
    html
    |> String.replace(~r/<li>\s*\[ \]/, "<li>\n<input type=\"checkbox\">")
    |> String.replace(~r/<li>\s*\[x\]/i, "<li>\n<input type=\"checkbox\" checked>")
  end

  defp read_markdown(filename) do
    path = Path.join(@base_path, filename)

    case File.read(path) do
      {:ok, content} -> Earmark.as_html!(content, gfm: true)
      _ -> ""
    end
  end
end
