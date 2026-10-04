defmodule WebWeb.AdminLive.ScannerTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Web.Negatives
  alias Web.NegativesFixtures, as: Fixture
  alias Web.Scanner.Bed

  @epson "device `epkowa:interpreter:001:050' is a Epson Perfection V550 Photo flatbed scanner"
  @webcam "device `v4l:/dev/video0' is a Noname Integrated Camera virtual device"

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  defp with_env(name, value) do
    System.put_env(name, value)
    on_exit(fn -> System.delete_env(name) end)
  end

  defp without_simulation do
    Application.put_env(:web, :scanner_simulation, false)
    on_exit(fn -> Application.put_env(:web, :scanner_simulation, true) end)
  end

  # Mounts the page and waits for the device listing its mount asked for.
  defp open_studio(conn) do
    Bed.subscribe()
    {:ok, view, _html} = live(admin_conn(conn), "/admin/scanner")
    assert_receive {:scanner, :devices, _devices}, 5_000
    view
  end

  defp roll_dir(root), do: Path.join(root, "120 Film/roll001_#{today()}_120_bw")
  defp today, do: Date.to_iso8601(Web.Clock.local_today())

  setup do
    %{root: Fixture.archive!()}
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/scanner")
  end

  test "the studio mounts, on its rail link, without a utility class in sight", %{conn: conn} do
    view = open_studio(conn)
    html = render(view)

    for id <- ~w(roll-config hardware-scan virtual-canvas conformance-publish keeper-rescan) do
      assert has_element?(view, "##{id}")
    end

    assert has_element?(
             view,
             ~s(#adm-rail a[href="/admin/scanner"][aria-current="page"]),
             "Scanner"
           )

    # Tailwind generates no utilities here, so one in the markup is unstyled.
    utility =
      ~r/class="(?:[^"]*\s)?(?:flex|grid|text-xs|font-mono|rounded|space-y-\d|(?:bg|text|border)-\S+)(?:\s[^"]*)?"/

    refute html =~ utility
  end

  test "the roll's name follows the form, and nonsense is ignored", %{conn: conn} do
    view = open_studio(conn)

    html =
      view
      |> form("#roll-config form")
      |> render_change(%{"format" => "35mm", "color" => "color", "roll_num" => "042"})

    assert html =~ "35mm Film/roll042_#{today()}_35mm_color"

    html =
      render_change(form(view, "#roll-config form"), %{
        "roll_num" => "../../etc",
        "date" => "soon"
      })

    assert html =~ "35mm Film/roll042_#{today()}_35mm_color"
  end

  test "the tabs are addresses", %{conn: conn, root: root} do
    Fixture.golden_roll!(root)
    view = open_studio(conn)

    view |> element(~s(nav.adm-tabs a[href="/admin/scanner?tab=archive"])) |> render_click()
    assert has_element?(view, "#archive-table", "013")

    view |> element(~s(nav.adm-tabs a[href="/admin/scanner?tab=setup"])) |> render_click()
    assert has_element?(view, "#setup-areas", "SCANNER_AREA_120")
    assert has_element?(view, "#setup-scanner", "Integrated Camera")
  end

  describe "with no scanner and no simulation, as on the live site" do
    setup do
      without_simulation()
    end

    test "the page says so, scans nothing, and still takes uploads", %{conn: conn, root: root} do
      view = open_studio(conn)

      assert render(view) =~ "No scanner connected"
      assert has_element?(view, "#hardware-scan button[disabled]", "Bed preview")
      assert has_element?(view, "#hardware-scan button[disabled]", "Scan strip 1")
      assert has_element?(view, "#hardware-scan .adm-drop")

      # Even an event sent past the disabled button scans nothing.
      view |> element("button", "Create the folder") |> render_click()
      html = render_click(view, "scan_next_strip")

      assert html =~ "No scanner is connected."
      assert File.ls!(roll_dir(root)) == ["frames"]
    end

    test "a strip can be uploaded and is kept as it was", %{conn: conn, root: root} do
      view = open_studio(conn)

      upload =
        file_input(view, "#hardware-scan form, #hardware-scan", :strip_scans, [
          %{name: "strip.tiff", content: "tiff bytes", type: "image/tiff"}
        ])

      render_upload(upload, "strip.tiff")

      assert File.read!(Path.join(roll_dir(root), "001.tiff")) == "tiff bytes"
      assert has_element?(view, ".adm-scan-strip", "001.tiff")
    end
  end

  describe "with the scanner connected" do
    setup do
      with_env("STUB_SCANIMAGE_DEVICES", @webcam <> "\n" <> @epson)
      without_simulation()
    end

    test "the Epson is the scanner, not the webcam listed before it", %{conn: conn} do
      view = open_studio(conn)

      assert has_element?(view, ".adm-pill", "Epson Perfection V550")
      refute render(view) =~ "No scanner"
    end

    test "a strip scan runs off the page and lands in the roll", %{conn: conn, root: root} do
      view = open_studio(conn)
      view |> element("button", "Create the folder") |> render_click()

      view |> element("button", "Scan strip 1") |> render_click()
      assert_receive {:scanner, :started, %{kind: :strip}}, 2_000
      assert_receive {:scanner, :done, _job}, 5_000

      assert File.read!(Path.join(roll_dir(root), "001.tiff")) == "strip scan"
      assert has_element?(view, ".adm-scan-strip", "001.tiff")
      assert has_element?(view, "button", "Scan strip 2")
      refute has_element?(view, ".adm-scan-job")
    end

    @tag :capture_log
    test "a failed scan is reported and leaves the roll as it was", %{conn: conn, root: root} do
      with_env("STUB_SCANIMAGE_FAIL", "1")
      view = open_studio(conn)
      view |> element("button", "Create the folder") |> render_click()

      view |> element("button", "Scan strip 1") |> render_click()
      assert_receive {:scanner, :failed, _job, _reason}, 5_000

      assert render(view) =~ "Scan failed: scanimage exited 1"
      assert File.ls!(roll_dir(root)) == ["frames"]
    end
  end

  describe "from strips to a published roll" do
    defp put_strips(root, names) do
      dir = roll_dir(root)
      File.mkdir_p!(Path.join(dir, "frames"))
      for name <- names, do: File.write!(Path.join(dir, name), "strip scan")
      dir
    end

    # A folder for roll 001 exists, so the studio opens on 002; go back to it.
    defp open_roll_001(conn) do
      view = open_studio(conn)
      view |> form("#roll-config form") |> render_change(%{"roll_num" => "001"})
      view
    end

    @tag :capture_log
    test "analyse, assemble, pass both gates, publish", %{conn: conn, root: root} do
      put_strips(root, ["001.tiff", "002.tiff"])
      view = open_roll_001(conn)

      # Nothing to publish until the gates pass.
      assert has_element?(view, "button[disabled]", "Publish the roll")
      assert has_element?(view, "button[disabled]", "Assemble sheet")

      view |> element("button", "Analyse strips") |> render_click()
      assert render_async(view) =~ "frames.json written"

      view |> element("button", "Assemble sheet") |> render_click()
      assert render_async(view) =~ "Contact sheet assembled"

      assert has_element?(view, "#gate-1.is-pass")
      assert has_element?(view, "#gate-2.is-pass")

      view |> element("button", "Publish the roll") |> render_click()

      assert has_element?(view, ~s(a[href="/negatives/roll/001"]))
      assert File.read!(Negatives.catalog_path()) =~ "001,#{today()},120,bw,2,120 Film/"
    end

    test "a tool that fails says so and nothing is invented in its place", %{
      conn: conn,
      root: root
    } do
      dir = put_strips(root, ["001.tiff", "002.tiff"])
      with_env("STUB_FILM_DEVELOP_FAIL", "1")
      view = open_roll_001(conn)

      view |> element("button", "Analyse strips") |> render_click()

      assert render_async(view) =~ "Analysis failed: film-develop exited 3"
      refute File.exists?(Path.join(dir, "frames.json"))
      assert has_element?(view, "button[disabled]", "Assemble sheet")
    end

    test "publishing past a failed gate is refused", %{conn: conn, root: root} do
      put_strips(root, ["001.tiff", "002.tiff"])
      view = open_roll_001(conn)

      assert render_click(view, "publish_to_site") =~ "Not published"
      refute File.read!(Negatives.catalog_path()) =~ "001,"
    end

    test "a simulated keeper is scanned outside frames/ and developed into it", %{
      conn: conn,
      root: root
    } do
      dir = put_strips(root, ["001.tiff", "002.tiff"])
      view = open_roll_001(conn)

      view |> element("button", "Analyse strips") |> render_click()
      render_async(view)

      view |> form("#keeper-rescan form") |> render_change(%{"frame" => "3"})
      view |> element("button", "Rescan frame 3") |> render_click()

      assert render_async(view) =~ "Frame 3 developed"
      assert File.regular?(Path.join(dir, "raw-frames/frame-03.tiff"))
      assert File.ls!(Path.join(dir, "frames")) == ["03.png"]
      assert has_element?(view, "#keeper-rescan", "Printed: 3")
    end
  end
end
