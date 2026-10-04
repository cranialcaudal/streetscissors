defmodule WebWeb.AlmanacController do
  @moduledoc """
  `/day/:date` and `/almanac/:year` — the site read by date (`Web.Almanac`).

  A day or a year with nothing in it is a 404, not an empty page: the
  calendar is infinite, and a crawler following "next day" links would
  otherwise walk it forever. Previous and next only ever point at days (and
  years) that have work in them, so the chain of links ends where the work
  does.
  """

  use WebWeb, :controller

  alias Web.Almanac

  def index(conn, _params) do
    case Almanac.years() do
      [latest | _] -> redirect(conn, to: ~p"/almanac/#{latest}")
      [] -> not_found(conn)
    end
  end

  def year(conn, %{"year" => raw}) do
    with {year, ""} <- Integer.parse(raw),
         {:ok, almanac} <- Almanac.year(year) do
      description =
        "#{year} at streetscissors, one page: every essay, recording, roll of film and ride, month by month."

      conn
      |> assign(:page_title, "#{year} · Almanac")
      |> assign(:meta_description, description)
      |> assign(:og_description, description)
      |> assign(:canonical_path, ~p"/almanac/#{year}")
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
        return_to: ~p"/almanac/#{date.year}",
        return_label: "back to the #{date.year} almanac"
      )
    else
      _ -> not_found(conn)
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(WebWeb.ErrorHTML)
    |> render("404.html")
  end
end
