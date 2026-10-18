defmodule WebWeb.AdminLive.DarkroomTest do
  use WebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Web.NegativesFixtures

  alias Web.Darkroom

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  setup do
    root = archive!()
    folder = put_roll!(root, roll: "007", format: "35mm", color: "color")
    put_sheet!(root, "roll007_2026-01-01_35mm_color", 300, 200)
    File.mkdir_p!(Path.join(folder, "frames"))

    for n <- [2, 3],
        do: File.write!(Path.join([folder, "frames", "0#{n}.png"]), png_bytes(30, 20))

    {:ok, folder: folder}
  end

  test "anonymous visitors are sent away", %{conn: conn} do
    assert {:error, {:redirect, _}} = live(conn, ~p"/admin/darkroom")
    assert {:error, {:redirect, _}} = live(conn, ~p"/admin/darkroom/007/3")
  end

  test "the prints of a roll, the edited ones marked", %{conn: conn, folder: folder} do
    :ok = Darkroom.save(folder, 3, %{controls: %{"light.exposure" => 0.4}, crop: nil})

    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/darkroom?roll=007")
    assert has_element?(view, ~s|a[href="/admin/darkroom/007/2"]|)
    assert has_element?(view, "#print-3", "edited")
    refute has_element?(view, "#print-2", "edited")
  end

  test "the bench draws LightCraft's sliders and shows each new picture",
       %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/darkroom/007/3")

    assert has_element?(view, ~s|input[type=range][name="light.exposure"]|)
    assert has_element?(view, ~s|input[name="effects.clarity"]|)
    # The engine's own sliders that describe nothing on film are not offered.
    refute has_element?(view, ~s|input[name="hdr.maxEv"]|)

    view |> form("#adjust", %{"light.exposure" => "0.75"}) |> render_change()
    assert has_element?(view, "output", "0.75")

    picture = wait_for_picture(view)
    assert picture =~ ~r|^/admin/darkroom/picture/[a-f0-9]{32}/p-\d+\.jpg$|
    assert conn |> admin_conn() |> get(picture) |> response(200)
    assert conn |> get(picture) |> response(404)
  end

  test "a picture is served by its token and its own name only", %{conn: conn} do
    conn = admin_conn(conn)

    assert conn
           |> get("/admin/darkroom/picture/#{String.duplicate("a", 32)}/p-1.jpg")
           |> response(404)

    assert conn |> get("/admin/darkroom/picture/notatoken/p-1.jpg") |> response(404)

    assert conn
           |> get("/admin/darkroom/picture/#{String.duplicate("a", 32)}/x.png")
           |> response(404)
  end

  test "Save prints the recipe and Revert puts the print back", %{conn: conn, folder: folder} do
    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/darkroom/007/3")

    view |> form("#adjust", %{"light.exposure" => "-1.5"}) |> render_change()
    view |> element("button", "Save") |> render_click()
    render_async(view)

    assert Darkroom.recipe(folder, 3).controls == %{"light.exposure" => -1.5}
    assert render(view) =~ "Printed."

    view |> element("button", "Revert") |> render_click()
    render_async(view)

    refute Darkroom.edited?(folder, 3)
    assert render(view) =~ "back as it was developed"
  end

  test "the crop opens on the whole picture and is kept when it is closed",
       %{conn: conn, folder: folder} do
    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/darkroom/007/3")

    view |> element("button", "Crop") |> render_click()
    assert has_element?(view, "#crop-box[data-rect='0.0,0.0,1.0,1.0']")

    render_hook(view, "crop_rect", %{"rect" => [0.1, 0.2, 0.7, 0.9]})
    view |> form("#straighten", %{"angle" => "2.5"}) |> render_change()
    assert has_element?(view, "#crop-box[data-rect='0.1,0.2,0.7,0.9']")

    view |> element("button", "Done") |> render_click()
    refute has_element?(view, "#crop-box")

    view |> element("button", "Save") |> render_click()
    render_async(view)
    assert Darkroom.recipe(folder, 3).crop == %{rect: [0.1, 0.2, 0.7, 0.9], angle: 2.5}
  end

  test "dust is found by LightCraft, healed, and taken off by hand", %{conn: conn, folder: folder} do
    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/darkroom/007/3")

    view |> element("button", "Dust") |> render_click()
    assert has_element?(view, "#dust-box")

    view |> form("#dust", %{"sensitivity" => "60"}) |> render_submit()
    assert render(view) =~ "Found 2 specks; 2 new."
    assert view |> element("#dust-box") |> render() |> String.contains?("Speck 2")

    # Found again, the same specks are not healed twice.
    view |> form("#dust", %{"sensitivity" => "60"}) |> render_submit()
    assert render(view) =~ "0 new"

    render_hook(view, "add_spot", %{"x" => 0.5, "y" => 0.5})
    render_hook(view, "remove_spot", %{"index" => "0"})
    assert has_element?(view, "output", "2 healed")

    view |> element("button", "Save") |> render_click()
    render_async(view)
    assert [%{x: 0.75, y: 0.2}, %{x: 0.5, y: 0.5}] = Web.Darkroom.recipe(folder, 3).spots
  end

  test "an unknown print is not a page", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/darkroom"}}} =
             live(admin_conn(conn), ~p"/admin/darkroom/007/9")
  end

  # The picture arrives as a message from the session; the view renders it
  # when it does.
  defp wait_for_picture(view, tries \\ 50) do
    html = render(view)

    case Regex.run(~r|src="(/admin/darkroom/picture/[^"]+/p-\d+\.jpg)"|, html) do
      [_, src] ->
        src

      nil when tries > 0 ->
        Process.sleep(20)
        wait_for_picture(view, tries - 1)

      nil ->
        flunk("no picture arrived: #{html}")
    end
  end
end
