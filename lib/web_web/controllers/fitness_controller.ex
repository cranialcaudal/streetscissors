defmodule WebWeb.FitnessController do
  use WebWeb, :controller

  alias Web.Fitness

  @doc "The training log as CSV for R (`Web.Fitness.Export`), to the admin only."
  def export_csv(conn, _params) do
    if get_session(conn, "admin_user") == true do
      filename = "fitness_progress_#{Date.to_string(Web.Clock.local_today())}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s[attachment; filename="#{filename}"])
      |> send_resp(200, Fitness.Export.logs_csv(Fitness.list_exercise_logs()))
    else
      conn
      |> put_flash(:error, "Unauthorized")
      |> redirect(to: "/")
    end
  end
end
