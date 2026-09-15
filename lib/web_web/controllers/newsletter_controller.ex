defmodule WebWeb.NewsletterController do
  use WebWeb, :controller

  alias Web.Newsletter

  def export_csv(conn, _params) do
    if get_session(conn, "admin_user") do
      headers = ["email", "status", "joined"]

      rows =
        Newsletter.list_subscribers()
        |> Enum.map(fn sub ->
          [
            sub.email,
            if(sub.active, do: "active", else: "unsubscribed"),
            NaiveDateTime.to_string(sub.inserted_at)
          ]
        end)

      csv_content =
        [headers | rows]
        |> Enum.map(fn row -> Enum.map(row, &escape_csv_field/1) |> Enum.join(",") end)
        |> Enum.join("\n")

      filename = "subscribers_#{Date.to_string(Date.utc_today())}.csv"

      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header("content-disposition", ~s[attachment; filename="#{filename}"])
      |> send_resp(200, csv_content)
    else
      conn
      |> put_flash(:error, "Unauthorized")
      |> redirect(to: "/")
    end
  end

  defp escape_csv_field(nil), do: ""

  defp escape_csv_field(val) when is_binary(val) do
    if String.contains?(val, [",", "\"", "\n"]) do
      "\"#{String.replace(val, "\"", "\"\"")}\""
    else
      val
    end
  end

  defp escape_csv_field(val), do: to_string(val)
end
