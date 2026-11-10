defmodule WebWeb.FitnessController do
  @moduledoc """
  The training log as a CSV download (`/fitness/export/csv`), for analysis in R or a spreadsheet.

  Admin only: the route is in the router's `:admin_only` scope, which answers
  the site's 404 to anyone else. The same CSV comes from `mix fitness.export`
  at the terminal.
  """

  use WebWeb, :controller

  alias Web.Fitness

  @doc "The training log as CSV for R (`Web.Fitness.Export`)."
  def export_csv(conn, _params) do
    filename = "fitness_progress_#{Date.to_string(Web.Clock.local_today())}.csv"

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s[attachment; filename="#{filename}"])
    |> send_resp(200, Fitness.Export.logs_csv(Fitness.list_exercise_logs()))
  end
end
