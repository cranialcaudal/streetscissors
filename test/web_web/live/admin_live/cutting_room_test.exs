defmodule WebWeb.AdminLive.CuttingRoomTest do
  use WebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Web.NegativesFixtures

  alias Web.Cuts

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  setup do
    root = archive!()
    folder = put_roll!(root, roll: "065", format: "35mm", color: "color")
    put_sheet!(root, "roll065_2026-01-01_35mm_color", 300, 200)
    File.mkdir_p!(Path.join(folder, "frames"))
    File.write!(Path.join([folder, "frames", "06.png"]), png_bytes(30, 20))
    :ok
  end

  defp new_cut do
    {:ok, cut} = Cuts.create_cut("Ferry")
    on_exit(fn -> File.rm_rf(Cuts.bin(cut.id)) end)
    cut
  end

  test "anonymous visitors are sent away", %{conn: conn} do
    cut = new_cut()
    assert {:error, {:redirect, _}} = live(conn, ~p"/admin/cuts")
    assert {:error, {:redirect, _}} = live(conn, ~p"/admin/cuts/#{cut.id}")
  end

  test "a cut is begun from the list", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/cuts")

    assert {:error, {:live_redirect, %{to: "/admin/cuts/" <> id}}} =
             view |> form("#new-cut", %{"name" => "Low tide"}) |> render_submit()

    assert Cuts.get_cut(String.to_integer(id)).name == "Low tide"
  end

  test "a take dropped in the bin goes on the picture track; a print and a title join it",
       %{conn: conn} do
    cut = new_cut()
    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/cuts/#{cut.id}")

    take =
      file_input(view, "#upload-form", :media, [
        %{name: "take one.mov", content: "a recording", type: "video/quicktime"}
      ])

    assert render_upload(take, "take one.mov") =~ "take one.mov"
    assert has_element?(view, "#cut-media-ready, li[id^=media-]", "take · 0:12")

    view |> element("button", "Add to picture") |> render_click()
    assert has_element?(view, ".adm-cut-block--take", "take one.mov")

    view |> form("#roll-picker", %{"roll" => "065"}) |> render_change()
    view |> element("button[phx-value-frame='065/6']") |> render_click()
    assert has_element?(view, ".adm-cut-block--still", "Roll 065 · 6")

    render_hook(view, "add_title", %{"at" => 1000})
    assert has_element?(view, "#inspector h2", "Title")
    view |> form("#inspector", %{"text" => "Ferry to Bainbridge"}) |> render_change()
    assert has_element?(view, ".adm-cut-block--title", "Ferry to Bainbridge")

    cut = Cuts.get_cut(cut.id)
    assert [%{"kind" => "take"}, %{"kind" => "still"}] = cut.timeline["clips"]
    assert [%{"text" => "Ferry to Bainbridge", "at" => 1000}] = cut.timeline["titles"]
    assert render(view) =~ "0:16"
  end

  test "the hand's edits: split, move, trim and delete", %{conn: conn} do
    cut = new_cut()
    {:ok, take} = Cuts.add_media(cut, tmp_file("take.mov"), "take.mov")
    cut = Cuts.get_cut(cut.id)

    {:ok, cut} =
      Cuts.save_timeline(
        cut,
        Web.Cuts.Timeline.add_take(Web.Cuts.Timeline.empty(), Web.Repo.reload!(take))
      )

    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/cuts/#{cut.id}")

    render_hook(view, "split", %{"at" => 4000})
    [first, second] = Cuts.get_cut(cut.id).timeline["clips"]
    assert {first["out"], second["in"]} == {4000, 4000}

    render_hook(view, "move", %{"id" => second["id"], "index" => 0})
    assert [%{"in" => 4000}, %{"in" => 0}] = Cuts.get_cut(cut.id).timeline["clips"]

    render_hook(view, "trim", %{"id" => second["id"], "edge" => "left", "delta" => 1500})
    assert %{"in" => 5500} = Web.Cuts.Timeline.find(Cuts.get_cut(cut.id).timeline, second["id"])

    render_hook(view, "select", %{"id" => first["id"]})
    render_hook(view, "delete", %{})
    assert [%{"id" => id}] = Cuts.get_cut(cut.id).timeline["clips"]
    assert id == second["id"]
  end

  test "sounds that overlap each get a row, so neither hides the other", %{conn: conn} do
    cut = new_cut()
    {:ok, song} = Cuts.add_media(cut, tmp_file("song.mp3"), "song.mp3")
    song = Web.Repo.reload!(song)
    cut = Cuts.get_cut(cut.id)

    timeline =
      Web.Cuts.Timeline.empty()
      |> Web.Cuts.Timeline.add_sound(song, 0)
      |> Web.Cuts.Timeline.add_sound(song, 2_000)
      |> Web.Cuts.Timeline.add_sound(song, 20_000)

    {:ok, cut} = Cuts.save_timeline(cut, timeline)
    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/cuts/#{cut.id}")

    html = render(view)
    assert html =~ "--lanes: 2"

    assert [0, 1, 0] =
             Regex.scan(~r/adm-cut-block--sound.*?--lane: (\d)/s, html)
             |> Enum.map(fn [_, n] -> String.to_integer(n) end)
  end

  test "Render and publish makes the log, and says so", %{conn: conn} do
    cut = new_cut()
    {:ok, take} = Cuts.add_media(cut, tmp_file("take.mov"), "take.mov")
    cut = Cuts.get_cut(cut.id)

    {:ok, cut} =
      Cuts.save_timeline(
        cut,
        Web.Cuts.Timeline.add_take(Web.Cuts.Timeline.empty(), Web.Repo.reload!(take))
      )

    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/cuts/#{cut.id}")

    view
    |> form("#publish-form", %{"recorded_on" => "2026-10-12", "caption" => ""})
    |> render_submit()

    assert render(view) =~ "Rendered into the log of Monday, 12 October 2026"
    assert %{status: "done", audio_log_id: log_id} = Cuts.get_cut(cut.id)
    assert %{status: "pending"} = Web.Logs.get_log!(log_id)
    assert has_element?(view, "button", "Render again")
  end

  test "the bin's proxies are served to the admin alone, with Range", %{conn: conn} do
    cut = new_cut()
    {:ok, take} = Cuts.add_media(cut, tmp_file("take.mov"), "take.mov")
    take = Web.Repo.reload!(take)
    path = ~p"/admin/cuts/#{cut.id}/media/#{take.proxy}"

    assert conn |> get(path) |> response(404)
    assert conn |> admin_conn() |> get(path) |> response(200) == "stub-media"

    ranged = conn |> admin_conn() |> put_req_header("range", "bytes=0-3") |> get(path)
    assert response(ranged, 206) == "stub"

    # The file as it came is never served, nor anything outside the bin.
    assert conn
           |> admin_conn()
           |> get(~p"/admin/cuts/#{cut.id}/media/#{take.file}")
           |> response(404)

    assert conn
           |> admin_conn()
           |> get("/admin/cuts/#{cut.id}/media/..%2F..%2Fsecret")
           |> response(404)
  end

  defp tmp_file(name) do
    path =
      Path.join(System.tmp_dir!(), "cut_upload_#{System.unique_integer([:positive])}_#{name}")

    File.write!(path, "a recording")
    path
  end
end
