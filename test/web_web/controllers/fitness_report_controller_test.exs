defmodule WebWeb.FitnessReportControllerTest do
  use WebWeb.ConnCase, async: false

  alias Web.Fitness.Report

  setup do
    dir = Report.dir()
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "2026-11-01.html"), "<p>week one</p>")
    File.write!(Path.join(dir, "2026-11-08.html"), "<p>week two</p>")
    on_exit(fn -> File.rm_rf!(dir) end)
    :ok
  end

  defp admin(conn), do: init_test_session(conn, %{"admin_user" => true})

  test "the admin gets the newest report, or one by its date", %{conn: conn} do
    assert Report.list() == [~D[2026-11-08], ~D[2026-11-01]]
    assert conn |> admin() |> get("/admin/fitness/report") |> response(200) =~ "week two"

    assert conn |> admin() |> get("/admin/fitness/report/2026-11-01") |> response(200) =~
             "week one"
  end

  test "anyone else, and any date with no report or no date at all, gets a 404", %{conn: conn} do
    assert conn |> get("/admin/fitness/report") |> response(404)
    assert conn |> get("/admin/fitness/report/2026-11-01") |> response(404)
    assert conn |> admin() |> get("/admin/fitness/report/2026-11-15") |> response(404)
    assert conn |> admin() |> get("/admin/fitness/report/..%2F..%2Fsecret") |> response(404)
  end
end
