defmodule WebWeb.FitnessReportController do
  @moduledoc """
  The weekly training report (`Web.Fitness.Report`), to the admin session and no one else.

  The newest is at `/admin/fitness/report`, any other at its date. The router's
  `:admin_only` scope turns anyone else away, and a date with no report gets
  the site's 404.
  """
  use WebWeb, :controller

  alias Web.Fitness.Report

  # `Report.path/1` answers for a real date and nothing else.
  # sobelow_skip ["Traversal.SendFile"]
  def show(conn, params) do
    date =
      case params["date"] || List.first(Report.list()) do
        %Date{} = d -> Date.to_iso8601(d)
        other -> other
      end

    case Report.path(date) do
      {:ok, path} ->
        conn
        |> put_resp_content_type("text/html")
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_header("x-robots-tag", "noindex, nofollow")
        |> send_file(200, path)

      _ ->
        WebWeb.NotFound.render(conn)
    end
  end
end
