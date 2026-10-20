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

  test "Undo takes back one change at a time, a dragged slider being one", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/darkroom/007/3")
    assert has_element?(view, "#undo[disabled]")

    view |> form("#adjust", %{"light.exposure" => "0.5"}) |> render_change()
    view |> form("#adjust", %{"light.exposure" => "0.75"}) |> render_change()
    view |> form("#adjust", %{"effects.clarity" => "20"}) |> render_change()

    assert has_element?(view, "output", "20")
    view |> element("#undo") |> render_click()
    refute has_element?(view, "output", "20")
    assert has_element?(view, "output", "0.75")

    view |> element("#undo") |> render_click()
    refute has_element?(view, "output", "0.75")
    assert has_element?(view, "#undo[disabled]")
  end

  test "one print's sliders are copied, pasted, and applied to the roll on confirming",
       %{conn: conn, folder: folder} do
    :ok = Darkroom.save(folder, 2, %{controls: %{"light.exposure" => 0.4}, crop: nil, spots: []})

    {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/darkroom/007/3")
    view |> form("#adjust", %{"light.exposure" => "-1.5"}) |> render_change()

    view |> element("button", "Copy sliders") |> render_click()
    assert Darkroom.copied_controls() == %{"light.exposure" => -1.5}

    view |> element("button", "Apply to the roll") |> render_click()
    # Frame 2's own edit is named before anything is printed over it.
    assert has_element?(view, "#roll-apply", "frames 2")
    assert Darkroom.recipe(folder, 2).controls == %{"light.exposure" => 0.4}

    view |> element("#roll-apply button", "Print them") |> render_click()
    render_async(view)

    assert Darkroom.recipe(folder, 2).controls == %{"light.exposure" => -1.5}
    assert render(view) =~ "printed with these sliders"
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

  # The repair stub (test/support/stub_film_repair) draws its mask with
  # ImageMagick, so the print must be a picture it can read.
  if System.find_executable("magick") do
    test "a scanner line is found, repaired, and the repair undone", %{conn: conn, folder: folder} do
      print = Path.join([folder, "frames", "03.png"])
      {_, 0} = System.cmd("magick", ["-size", "30x20", "gradient:white-gray", print])

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/darkroom/007/3")
      view |> element("button", "Repair") |> render_click()
      assert has_element?(view, "#repair-box canvas")
      assert has_element?(view, "button[phx-click=lama][disabled]")

      view |> element("button", "Find scanner lines") |> render_click()
      render_async(view)
      assert render(view) =~ "Found a scanner line; it is marked."
      assert conn |> admin_conn() |> get(~p"/admin/darkroom/mask/007/3") |> response(200)
      assert conn |> get(~p"/admin/darkroom/mask/007/3") |> response(404)

      view |> element("button", "Repair what is marked") |> render_click()
      render_async(view)
      assert render(view) =~ "Repaired: 1 scanner line corrected, 1 place painted."
      assert Darkroom.source_path(folder, 3) == Darkroom.repaired_path(folder, 3)

      # A repair is worth saving on its own, though the recipe is unchanged.
      refute has_element?(view, "button[phx-click=save][disabled]")
      view |> element("button[phx-click=save]") |> render_click()
      render_async(view)
      assert render(view) =~ "Printed."
      assert has_element?(view, "button[phx-click=save][disabled]")
      assert has_element?(view, "button", "Revert")

      view |> element("button", "Undo the repair") |> render_click()
      refute File.exists?(Darkroom.repaired_path(folder, 3))
      assert File.exists?(Darkroom.mask_path(folder, 3))
      refute has_element?(view, "button[phx-click=save][disabled]")
    end

    test "Stable Diffusion's fill is looked at, then kept or discarded", %{
      conn: conn,
      folder: folder
    } do
      print = Path.join([folder, "frames", "03.png"])
      {_, 0} = System.cmd("magick", ["-size", "30x20", "gradient:white-gray", print])

      {:ok, view, _html} = live(admin_conn(conn), ~p"/admin/darkroom/007/3")
      view |> element("button", "Repair") |> render_click()
      assert has_element?(view, "button[phx-click=diffuse][disabled]")
      view |> element("button", "Find scanner lines") |> render_click()
      render_async(view)

      view |> element("button", "Fill with Stable Diffusion") |> render_click()
      render_async(view)
      assert render(view) =~ "Stable Diffusion filled 1 place."
      assert has_element?(view, ~s|#candidate-box img[src^="/admin/darkroom/candidate/007/3"]|)
      refute has_element?(view, "#repair-box")
      assert conn |> admin_conn() |> get(~p"/admin/darkroom/candidate/007/3") |> response(200)
      assert conn |> get(~p"/admin/darkroom/candidate/007/3") |> response(404)

      view |> element("button", "Show before") |> render_click()
      assert has_element?(view, ~s|#candidate-box img[src="/admin/darkroom/developed/007/3"]|)

      view |> element("button", "Discard it") |> render_click()
      refute File.exists?(Darkroom.candidate_path(folder, 3))
      assert has_element?(view, "#repair-box")

      view |> element("button", "Fill with Stable Diffusion") |> render_click()
      render_async(view)
      view |> element("button", "Keep the fill") |> render_click()
      assert render(view) =~ "The fill is the repair now."
      assert Darkroom.source_path(folder, 3) == Darkroom.repaired_path(folder, 3)
      refute has_element?(view, "button[phx-click=save][disabled]")
    end
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
