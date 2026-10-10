defmodule WebWeb.AlmanacController do
  @moduledoc """
  The site read by date, as an engagement calendar (`Web.Almanac`):
  `/daybook` is this week, `/daybook/:year/week/:week` any week,
  `/day/:date` one day, and `/daybook/:year` the year at a glance.

  A day, a week or a year with nothing in it is a 404, not an empty page:
  the calendar is infinite, and a crawler following "next" links would
  otherwise walk it forever. Previous and next only ever point at days,
  weeks and years that have work in them, so the chain of links ends where
  the work does. The one exception is the week it is now, which is always a
  page: an engagement calendar is open at this week whether or not anything
  is written in it yet.
  """

  use WebWeb, :controller

  alias Web.Almanac

  def index(conn, _params) do
    today = Web.Clock.local_today()
    {:ok, week} = Almanac.week(today, Almanac.entries(), today)

    conn
    |> assign(:canonical_path, ~p"/daybook")
    |> render_week(week, today)
  end

  def week(conn, %{"year" => raw_year, "week" => raw_week}) do
    today = Web.Clock.local_today()

    with {year, ""} <- Integer.parse(raw_year),
         {number, ""} <- Integer.parse(raw_week),
         {:ok, monday} <- Almanac.monday_of(year, number),
         {:ok, week} <- Almanac.week(monday, Almanac.entries(), today) do
      conn
      |> assign(:canonical_path, Almanac.week_path(monday))
      |> render_week(week, today)
    else
      _ -> not_found(conn)
    end
  end

  defp render_week(conn, week, today) do
    span = WebWeb.AlmanacHTML.week_span(week.monday)
    description = "The week of #{span} at streetscissors: what was made on each day of it."

    conn
    |> assign(:page_title, "#{span} · Daybook")
    |> assign(:meta_description, description)
    |> assign(:og_description, description)
    |> render(:week, week: week, today: today)
  end

  def year(conn, %{"year" => raw}) do
    with {year, ""} <- Integer.parse(raw),
         {:ok, almanac} <- Almanac.year(year) do
      description =
        "#{year} at streetscissors, one page: every essay, recording, roll of film and ride, month by month."

      conn
      |> assign(:page_title, "#{year} · Daybook")
      |> assign(:meta_description, description)
      |> assign(:og_description, description)
      |> assign(:canonical_path, ~p"/daybook/#{year}")
      |> render(:year, almanac: almanac)
    else
      _ -> not_found(conn)
    end
  end

  def day(conn, %{"date" => raw}) do
    with {:ok, date} <- Date.from_iso8601(raw),
         {:ok, day} <- Almanac.day(date) do
      title = Calendar.strftime(date, "%A, %-d %B %Y")
      description = "Everything made at streetscissors on #{title}."

      conn
      |> assign(:page_title, title)
      |> assign(:meta_description, description)
      |> assign(:og_description, description)
      |> assign(:canonical_path, ~p"/day/#{Date.to_iso8601(date)}")
      |> render(:day,
        day: day,
        return_to: Almanac.week_path(date),
        return_label: "back to the week"
      )
    else
      _ -> not_found(conn)
    end
  end

  defp not_found(conn), do: WebWeb.NotFound.render(conn)
end
