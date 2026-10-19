defmodule WebWeb.AdminLive.BlockReportTest do
  use WebWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Web.Fitness.Photos

  # The fixture vault's block (blocks/test-block.md) is running whatever
  # day the suite runs. Not async: the photographs folder is shared.

  setup do
    File.rm_rf!(Photos.dir())
    on_exit(fn -> File.rm_rf!(Photos.dir()) end)
    :ok
  end

  defp admin(conn), do: init_test_session(conn, %{"admin_user" => true})

  test "anonymous visitors are sent away, from the page and from a photograph", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/fitness/block")

    src = Path.join(System.tmp_dir!(), "p.jpg")
    File.write!(src, "jpeg")
    {:ok, _} = Photos.store(~D[2026-10-26], src, ".jpg")

    assert conn |> get("/admin/fitness/photos/2026-10-26/01.jpg") |> response(404)

    assert admin(conn) |> get("/admin/fitness/photos/2026-10-26/01.jpg") |> response(200) ==
             "jpeg"

    assert admin(conn) |> get("/admin/fitness/photos/2026-10-26/02.jpg") |> response(404)
  end

  test "the report has the framing, the weeks and the lifts", %{conn: conn} do
    {:ok, exercise} = Web.Fitness.loggable_exercise("push-ups")

    {:ok, _} =
      Web.Fitness.create_exercise_log(%{
        exercise_id: exercise.id,
        date: Web.Clock.local_today(),
        metrics: %{"weight" => "20 lbs", "sets" => "3", "reps" => "10"}
      })

    {:ok, _} = Web.Fitness.save_checkin(%{date: Web.Clock.local_today(), pain: 3})

    {:ok, view, html} = live(admin(conn), "/admin/fitness/block")

    assert html =~ "Test Block"
    assert html =~ "An invented block"
    assert has_element?(view, "#block-weeks")
    assert has_element?(view, "#block-lifts", "Push-ups")
    assert has_element?(view, "#chart-e1rm")
    refute has_element?(view, "#block-answer"), "a 520-week block is not over"
  end

  test "a photograph is uploaded, shown, and set aside", %{conn: conn} do
    {:ok, view, _html} = live(admin(conn), "/admin/fitness/block")

    photo =
      file_input(view, "#photo-form", :photos, [
        %{name: "front.jpg", content: "jpeg bytes", type: "image/jpeg"}
      ])

    render_upload(photo, "front.jpg")
    view |> form("#photo-form") |> render_submit()

    today = Date.to_iso8601(Web.Clock.local_today())
    assert has_element?(view, "#flash-info", "Photograph kept.")
    assert has_element?(view, ~s(img[src="/admin/fitness/photos/#{today}/01.jpg"]))

    view |> element("button[phx-value-file='01.jpg']") |> render_click()
    refute has_element?(view, "img")
  end
end
