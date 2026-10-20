defmodule WebWeb.FitnessReportController do
  @moduledoc """
  The weekly training report (`Web.Fitness.Report`), to the admin session
  and no one else: the newest at `/admin/fitness/report`, any other by its
  date. Anyone else, and any date with no report, gets the site's 404.
  """
  use WebWeb, :controller

  alias Web.Fitness.Report

  def show(conn, params) do
    date =
      case params["date"] || List.first(Report.list()) do
        %Date{} = d -> Date.to_iso8601(d)
        other -> other
      end

    with true <- get_session(conn, "admin_user") == true,
         {:ok, path} <- Report.path(date) do
      conn
      |> put_resp_content_type("text/html")
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-robots-tag", "noindex, nofollow")
      |> send_file(200, path)
    else
      _ -> WebWeb.NotFound.render(conn)
    end
  end
end
