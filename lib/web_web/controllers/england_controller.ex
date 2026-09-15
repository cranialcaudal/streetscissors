defmodule WebWeb.EnglandController do
  use WebWeb, :controller

  # Everything that makes this a particular trip — its days, places and the
  # people to call — lives in content/england2026/ (`:england_path`) beside the
  # itinerary, not in code. Without a trip.json the pages still render, empty.
  @default_path "content/england2026"

  @empty_trip %{
    "title" => "Trip",
    "subtitle" => "",
    "month" => nil,
    "call_link" => nil,
    "routes" => [],
    "days" => [],
    "call" => %{
      "page_title" => "When to Call",
      "title" => "When to Call",
      "subtitle" => "",
      "home_label" => "Your time",
      "away_label" => "Their time",
      "home_tz" => "America/Los_Angeles",
      "away_tz" => "Europe/London",
      "window_start" => 9,
      "window_end" => 13,
      "good_now" => "Right now is a good time to call.",
      "wait" => "Not right now."
    }
  }

  # NOTE: this action must not be named `call` — controllers are Plugs, and
  # defining call/2 overrides the Plug entry point, 500ing every route here.
  def call_times(conn, _params) do
    %{"call" => call} = load_trip()

    render(conn, :call_times,
      page_title: call["page_title"],
      call: call,
      call_html: read_markdown("call.md"),
      hide_header: true
    )
  end

  def show(conn, _params) do
    trip = load_trip()
    month = trip_month(trip)

    render(conn, :show,
      trip: trip,
      checklist: read_markdown("checklist.md") |> render_task_lists(),
      itinerary: read_markdown("itinerary.md"),
      calendar_month: month,
      calendar_weeks: calendar_weeks(month),
      trip_days: trip_days_by_date(trip),
      page_title: trip["title"],
      hide_header: true
    )
  end

  defp load_trip do
    with {:ok, json} <- File.read(Path.join(base_path(), "trip.json")),
         {:ok, %{} = trip} <- Jason.decode(json) do
      Map.merge(@empty_trip, trip, fn
        "call", default, given when is_map(given) -> Map.merge(default, given)
        _key, _default, given -> given
      end)
    else
      _ -> @empty_trip
    end
  end

  defp base_path, do: Application.get_env(:web, :england_path) || Path.expand(@default_path)

  defp trip_month(%{"month" => month}) when is_binary(month) do
    case Date.from_iso8601(month) do
      {:ok, date} -> Date.beginning_of_month(date)
      _ -> Date.beginning_of_month(Date.utc_today())
    end
  end

  defp trip_month(_trip), do: Date.beginning_of_month(Date.utc_today())

  defp trip_days_by_date(trip) do
    trip["days"]
    |> Enum.with_index(1)
    |> Map.new(fn {day, num} ->
      {day["date"], %{num: num, title: day["title"], song: day["song"], icon: day["icon"]}}
    end)
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
    case File.read(Path.join(base_path(), filename)) do
      {:ok, content} -> Earmark.as_html!(content, gfm: true)
      _ -> ""
    end
  end
end
