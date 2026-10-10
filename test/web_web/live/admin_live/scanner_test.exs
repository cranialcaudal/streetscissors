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

    for id <- ~w(hardware-scan roll-config strips keeper-rescan collection) do
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
      |> form(~s(#roll-config form[phx-change="update_roll_config"]))
      |> render_change(%{"format" => "35mm", "color" => "color", "roll_num" => "042"})

    assert html =~ "35mm Film/roll042_#{today()}_35mm_color"

    html =
      render_change(form(view, ~s(#roll-config form[phx-change="update_roll_config"])), %{
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

  test "the roll's settings and its strips are drawers, one open at a time", %{conn: conn} do
    view = open_studio(conn)

    assert has_element?(view, "#roll-config[hidden]")
    assert has_element?(view, "#strips[hidden]")

    view |> element("#hardware-scan button", "Strips") |> render_click()
    refute has_element?(view, "#strips[hidden]")

    view |> element("#hardware-scan button", "Roll") |> render_click()
    refute has_element?(view, "#roll-config[hidden]")
    assert has_element?(view, "#strips[hidden]")

    view |> element("#hardware-scan button", "Roll") |> render_click()
    assert has_element?(view, "#roll-config[hidden]")
  end

  test "what is known about the roll is kept with it, from before it has a folder", %{
    conn: conn,
    root: root
  } do
    view = open_studio(conn)

    # Said before the roll is begun: held, and nothing written anywhere.
    view
    |> form("#roll-meta")
    |> render_change(%{
      "shot" => "2023",
      "camera" => "Olympus XA",
      "notes" => "Found in a drawer."
    })

    refute File.exists?(roll_dir(root))

    view |> element("button", "Create the folder") |> render_click()

    assert %{"shot" => "2023", "camera" => "Olympus XA"} =
             Jason.decode!(File.read!(Path.join(roll_dir(root), "roll.json")))

    assert has_element?(view, "#hardware-scan .adm-scan-roll", "shot 2023")

    # A date that is not one is said, and what was there stays.
    html = view |> form("#roll-meta") |> render_change(%{"shot" => "summer 2023"})
    assert html =~ "is not a date"
    assert Web.Negatives.RollMeta.read(roll_dir(root)).shot == "2023"

    view |> form("#roll-meta") |> render_change(%{"shot" => "2023-06-14", "notes" => ""})

    assert %{shot: "2023-06-14", camera: "Olympus XA", notes: nil} =
             Web.Negatives.RollMeta.read(roll_dir(root))

    # A reload reads it back.
    view = open_studio(conn)
    assert has_element?(view, ~s(#roll-meta input[name="shot"][value="2023-06-14"]))
    assert has_element?(view, "#hardware-scan .adm-scan-roll", "shot June 14, 2023")
  end

  test "a reload carries on with the roll begun, and a new roll is asked for", %{
    conn: conn,
    root: root
  } do
    # Published rolls are not work in progress; a folder the catalog lacks is.
    Fixture.put_roll!(root, roll: "001")
    File.mkdir_p!(Path.join(root, "35mm Film/roll002_2026-10-01_35mm_color/frames"))

    view = open_studio(conn)
    assert render(view) =~ "35mm Film/roll002_2026-10-01_35mm_color"

    view |> element("button", "Start a new roll") |> render_click()
    assert render(view) =~ "120 Film/roll003_#{today()}_120_bw"
  end

  describe "with no scanner and no simulation, as on the live site" do
    setup do
      without_simulation()
    end

    test "the page says so, scans nothing, and still takes uploads", %{conn: conn, root: root} do
      view = open_studio(conn)

      assert render(view) =~ "No scanner connected"
      assert has_element?(view, "#hardware-scan button[disabled]", "Preview")
      assert has_element?(view, "#strips .adm-drop")

      # Even an event sent past the disabled button scans nothing.
      view |> element("button", "Create the folder") |> render_click()
      html = render_click(view, "preview")

      assert html =~ "No scanner is connected."
      assert File.ls!(roll_dir(root)) == ["frames"]
    end

    test "a strip can be uploaded and is kept as it was", %{conn: conn, root: root} do
      view = open_studio(conn)

      upload =
        file_input(view, "#strips", :strip_scans, [
          %{name: "strip.tiff", content: "tiff bytes", type: "image/tiff"}
        ])

      render_upload(upload, "strip.tiff")

      assert File.read!(Path.join(roll_dir(root), "001.tiff")) == "tiff bytes"
      assert has_element?(view, ".adm-scan-strip", "001.tiff")
    end
  end

  describe "the loop for each load of the holder" do
    setup do
      with_env("STUB_SCANIMAGE_DEVICES", @webcam <> "\n" <> @epson)
      without_simulation()
    end

    test "the Epson is the scanner, not the webcam listed before it", %{conn: conn} do
      view = open_studio(conn)

      assert has_element?(view, ".adm-pill", "Epson Perfection V550")
      refute render(view) =~ "No scanner"
    end

    test "it begins at Load, with Preview the one thing to press", %{conn: conn} do
      view = open_studio(conn)

      assert has_element?(view, "#hardware-scan .adm-scan-steps li.is-current", "Preview")
      assert has_element?(view, "#hardware-scan button.adm-scan-go", "Preview")
      assert has_element?(view, "#keeper-rescan", "Load the holder and press Preview.")
      assert has_element?(view, "#hardware-scan button[disabled]", "Publish roll")
      assert has_element?(view, "#collection", "No singles yet")
    end

    test "a preview of empty glass adds nothing and leaves the roll as it was set", %{
      conn: conn,
      root: root
    } do
      view = open_studio(conn)

      view |> element("button", "Preview") |> render_click()
      assert_receive {:scanner, :done, %{kind: :pass}}, 5_000

      assert render_async(view, 5_000) =~ "No film could be read on the glass"
      refute File.exists?(roll_dir(root))

      assert has_element?(
               view,
               ~s(#roll-config select[name="format"] option[value="120"][selected])
             )

      assert has_element?(view, "#hardware-scan button.adm-scan-go", "Preview")
    end

    # The stub hands back a file; reading and cutting it takes the real ImageMagick.
    if System.find_executable("magick") do
      # The transparency unit at the look's 400 dpi is 1080 px across. Film is
      # drawn in the columns given, the holder black around it.
      defp glass!(bands) do
        row =
          for x <- 0..1079, into: <<>> do
            case Enum.find(bands, fn {range, _colour} -> x in range end) do
              {_range, {r, g, b}} -> <<r + rem(x, 9), g, b>>
              nil -> <<0, 0, 0>>
            end
          end

        path = Path.join(System.tmp_dir!(), "glass_#{System.unique_integer([:positive])}.ppm")
        File.write!(path, ["P6\n1080 1400\n255\n", :binary.copy(row, 1400)])
        on_exit(fn -> File.rm(path) end)
        with_env("STUB_SCANIMAGE_IMAGE", path)
      end

      defp preview(view) do
        view |> element("button", "Preview") |> render_click()
        assert_receive {:scanner, :done, %{kind: :pass}}, 10_000
        render_async(view, 20_000)
      end

      # A load settled with no singles taken: whatever was proposed is
      # unticked first, since the button reads "Scan N singles" until then.
      defp no_singles(view) do
        for [tag] <- Regex.scan(~r/<input[^>]*>/, view |> element("#keeper-rescan") |> render()),
            tag =~ "checked",
            [_, frame] <- [Regex.run(~r/phx-value-frame="(\d+)"/, tag)] do
          view |> element(~s(#keeper-rescan input[phx-value-frame="#{frame}"])) |> render_click()
        end

        view |> element("button", "No singles, next load") |> render_click()
      end

      defp roll_35(root), do: Path.join(root, "35mm Film/roll001_#{today()}_35mm_color")

      @orange {200, 120, 60}

      test "Preview reads the film, names the roll, adds every strip, and moves on to Select", %{
        conn: conn,
        root: root
      } do
        # Both slots of the 35mm holder: two orange strips 24.9 mm wide.
        glass!([{32..423, @orange}, {615..1006, @orange}])
        view = open_studio(conn)

        html = preview(view)

        assert html =~ "Read off the glass: 35mm, colour. Added 001.tiff and 002.tiff."
        assert html =~ "4 frames found, 2 ticked."

        dir = roll_35(root)
        assert <<"II*", 0, _::binary>> = File.read!(Path.join(dir, "001.tiff"))
        assert File.regular?(Path.join(dir, "002.tiff"))

        # Where each strip lies is kept, so a chosen frame can be found again,
        # and the load is not settled yet.
        assert %{"001.tiff" => {left, +0.0, width, _}, "002.tiff" => {right, _, _, _}} =
                 Web.Scanner.holder(dir)

        assert_in_delta left, 2.0, 0.3
        assert_in_delta width, 24.9, 0.4
        assert_in_delta right, 39.1, 0.3
        assert Web.Scanner.pending_load(dir) == ["001.tiff", "002.tiff"]

        # Select: the load's frames, the well exposed ones ticked, one button.
        assert has_element?(view, "#hardware-scan .adm-scan-steps li.is-current", "Select")
        assert has_element?(view, ~s(#keeper-rescan input[phx-value-frame="1"][checked]))
        assert has_element?(view, ~s(#keeper-rescan input[phx-value-frame="3"][checked]))
        assert has_element?(view, "#hardware-scan button.adm-scan-go", "Scan 2 singles")
        refute has_element?(view, "#hardware-scan button.adm-scan-go", "Preview")

        # A frame the wrong way up is turned where it is shown, and stays turned.
        # (The stub's frames are taller than wide, so they start a quarter back.)
        assert Web.Scanner.rotation(dir, 1) == 270
        view |> element(~s(#keeper-rescan button[phx-value-frame="1"])) |> render_click()
        assert Web.Scanner.rotation(dir, 1) == 0

        # So is the picture of the holder, which lies landscape to begin with.
        assert has_element?(view, "#keeper-rescan .adm-scan-glass img")
        view |> element("#keeper-rescan .adm-scan-glass button", "Turn") |> render_click()
      end

      test "a load looked at again replaces itself, and a reload finds it still to be settled", %{
        conn: conn,
        root: root
      } do
        glass!([{32..423, @orange}, {615..1006, @orange}])
        view = open_studio(conn)
        preview(view)

        dir = roll_35(root)
        assert length(Web.Scanner.list_strips(dir)) == 2

        # The page reloaded mid-load opens where it was.
        view = open_studio(conn)
        assert has_element?(view, "#hardware-scan .adm-scan-steps li.is-current", "Select")
        assert has_element?(view, ~s(#keeper-rescan input[phx-value-frame="3"][checked]))

        # The holder was misloaded: one strip this time. The first look's two
        # strips come back out; nothing is added on top of them.
        glass!([{32..423, @orange}])
        render_click(view, "preview")
        assert_receive {:scanner, :done, %{kind: :pass}}, 10_000
        html = render_async(view, 20_000)
        assert html =~ "Added 001.tiff. 2 frames found, 1 ticked."

        assert Enum.map(Web.Scanner.list_strips(dir), & &1.file) == ["001.tiff"]
        assert Web.Scanner.pending_load(dir) == ["001.tiff"]
      end

      test "Scan sends the scanner back for the singles, then the bench is clear for the next load",
           %{conn: conn, root: root} do
        glass!([{32..423, @orange}])
        view = open_studio(conn)
        preview(view)

        # Frame 1 is the proposal. (The stub hands the same picture back for
        # the band, which only frame 1's corner of the glass falls inside.)
        view |> element("button", "Scan 1 single") |> render_click()

        assert_receive {:scanner, :started, %{kind: :band, meta: %{band: band}}}, 5_000
        assert [{1, _rect}] = band.frames

        assert_receive {:scanner, :done, %{kind: :band}}, 10_000
        html = render_async(view, 20_000)
        assert html =~ "Scanned frame 1. Load the next strips and press Preview."

        dir = roll_35(root)
        assert File.ls!(Path.join(dir, "frames")) == ["01.png"]
        assert Web.Scanner.pending_load(dir) == []

        assert %{
                 "1" => %{"suggested" => true, "chosen" => true, "strip" => "001.tiff"},
                 "2" => %{"suggested" => false, "chosen" => false}
               } = Web.Scanner.read_selects(dir)

        # Back at Load: nothing to choose from, Preview to press, and the
        # single in the collection, where it can be turned or taken out.
        assert has_element?(view, "#hardware-scan button.adm-scan-go", "Preview")
        refute has_element?(view, "#keeper-rescan input")
        assert has_element?(view, "#keeper-rescan", "Load the next strips and press Preview.")

        render_async(view, 10_000)
        assert has_element?(view, "#collection .adm-scan-single", "Frame 1")
        assert has_element?(view, ~s(#collection img[alt="Single, frame 1"]))
        assert has_element?(view, "#hardware-scan .adm-scan-roll", "1 strip of 7 · 1 single")

        view |> element(~s(#collection button[phx-click="turn_frame"])) |> render_click()
        assert Web.Scanner.rotation(dir, 1) == 0

        # The film is still on the glass, so more can be picked from it.
        view |> element("button", "Pick more singles") |> render_click()
        assert has_element?(view, ~s(#keeper-rescan input[phx-value-frame="2"]))
        assert has_element?(view, "#hardware-scan button.adm-scan-go", "No singles, next load")

        view |> element("button", "No singles, next load") |> render_click()
        assert has_element?(view, "#hardware-scan button.adm-scan-go", "Preview")

        view |> element(~s(#collection button[phx-click="remove_single"])) |> render_click()
        assert File.ls!(Path.join(dir, "frames")) == []
        assert has_element?(view, "#collection", "No singles yet")
        assert %{"1" => %{"chosen" => false, "removed" => true}} = Web.Scanner.read_selects(dir)
      end

      test "Publish with frames ticked scans them first, so no chosen single is left out", %{
        conn: conn,
        root: root
      } do
        glass!([{32..423, @orange}])
        view = open_studio(conn)
        preview(view)

        assert has_element?(
                 view,
                 ~s(button[phx-click="publish"][data-confirm^="Scan the 1 single ticked, then publish"])
               )

        view |> element(~s(button[phx-click="publish"])) |> render_click()

        assert_receive {:scanner, :started, %{kind: :band}}, 5_000
        assert_receive {:scanner, :done, %{kind: :band}}, 10_000
        render_async(view, 20_000)

        dir = roll_35(root)
        assert File.ls!(Path.join(dir, "frames")) == ["01.png"]
        assert %{"1" => %{"chosen" => true}} = Web.Scanner.read_selects(dir)

        # The roll goes out once its single is in, and the next one is begun.
        html = render_async(view, 20_000)
        assert html =~ "Roll 001 is on /negatives."
        assert File.read!(Negatives.catalog_path()) =~ "001,#{today()},35mm,color,1,35mm Film/"
      end

      test "the next load adds to the roll and shows only its own frames", %{
        conn: conn,
        root: root
      } do
        glass!([{32..423, @orange}])
        view = open_studio(conn)

        assert preview(view) =~ "Added 001.tiff."
        view |> element(~s(#keeper-rescan input[phx-value-frame="1"])) |> render_click()
        view |> element("button", "No singles, next load") |> render_click()
        assert render(view) =~ "No singles from this load."

        assert preview(view) =~ "Added 002.tiff. 2 frames found, 1 ticked."

        dir = roll_35(root)
        assert length(Web.Scanner.list_strips(dir)) == 2
        assert has_element?(view, ~s(#keeper-rescan input[phx-value-frame="3"][checked]))
        refute has_element?(view, ~s(#keeper-rescan input[phx-value-frame="1"]))

        # Only the strip still on the glass is where the scanner saw it.
        assert Map.keys(Web.Scanner.holder(dir)) == ["002.tiff"]

        # Film of another width is not this roll's.
        view |> element(~s(#keeper-rescan input[phx-value-frame="3"])) |> render_click()
        view |> element("button", "No singles, next load") |> render_click()
        glass!([{50..930, {120, 120, 120}}])

        assert preview(view) =~
                 "reads as 120, black and white, but this roll is 35mm, colour. Nothing was added."

        assert length(Web.Scanner.list_strips(dir)) == 2
      end
    end

    if System.find_executable("magick") do
      test "the bench is free the moment the scanner stops, before the singles are developed", %{
        conn: conn,
        root: root
      } do
        glass!([{32..423, @orange}])
        view = open_studio(conn)
        preview(view)

        view |> element("button", "Scan 1 single") |> render_click()
        assert_receive {:scanner, :done, %{kind: :band}}, 10_000

        # Rendered once, with the developing still to come back: already at Load.
        html = render(view)
        assert html =~ "Scanned frame 1. Load the next strips and press Preview."
        assert has_element?(view, "#hardware-scan button.adm-scan-go", "Preview")

        render_async(view, 20_000)
        assert File.ls!(Path.join(roll_35(root), "frames")) == ["01.png"]
      end

      test "a run cut short is found again: its singles are put back up, ticked, on reload", %{
        conn: conn,
        root: root
      } do
        glass!([{32..423, @orange}])
        view = open_studio(conn)
        preview(view)
        dir = roll_35(root)

        # Chosen, the load settled, and then the service restarted under the
        # scan: the choosing is on disk and nothing else is.
        Web.Scanner.confirm_load(dir)
        Web.Scanner.record_selects(dir, Web.Scanner.frames(dir), [1, 2])

        assert [%{frame: 1, on_glass?: true}, %{frame: 2, on_glass?: true}] =
                 Web.Scanner.owed_singles(dir)

        view = open_studio(conn)

        assert render(view) =~ "Chosen but not yet scanned: frames 1, 2."
        assert has_element?(view, ~s(#keeper-rescan input[phx-value-frame="1"][checked]))
        assert has_element?(view, ~s(#keeper-rescan input[phx-value-frame="2"][checked]))
        assert has_element?(view, "#hardware-scan button.adm-scan-go", "Scan 2 singles")

        # Once the film has gone from the glass they can only be said.
        File.rm!(Path.join(dir, "holder.json"))
        view = open_studio(conn)

        assert has_element?(view, "#hardware-scan button.adm-scan-go", "Preview")

        assert has_element?(
                 view,
                 "#collection .adm-scan-fault",
                 "Chosen but never scanned: frames 1, 2"
               )
      end

      test "a load can be taken back out, and film already on the roll is noticed", %{
        conn: conn,
        root: root
      } do
        glass!([{32..423, @orange}])
        view = open_studio(conn)
        preview(view)
        view |> element(~s(#keeper-rescan input[phx-value-frame="1"])) |> render_click()
        view |> element("button", "No singles, next load") |> render_click()

        # The same film again, after its load was settled: it is added, and said.
        html = preview(view)
        assert html =~ "Added 002.tiff."

        dir = roll_35(root)
        assert length(Web.Scanner.list_strips(dir)) == 2

        view |> element("button", "Discard this load") |> render_click()
        render_async(view, 10_000)

        assert Enum.map(Web.Scanner.list_strips(dir), & &1.file) == ["001.tiff"]
        assert has_element?(view, "#hardware-scan button.adm-scan-go", "Preview")
      end

      # A sleeve holds so many strips. Nothing is decided at the look and
      # nothing is published until Publish is pressed.
      test "a roll with its sleeve's worth waits to be published, and the next look begins the next roll",
           %{conn: conn, root: root} do
        Web.SiteSettings.put_setting("scanner_strips_per_roll", "2")
        # One wide grey strip: 120, black and white.
        glass!([{50..930, {120, 120, 120}}])
        view = open_studio(conn)

        assert has_element?(view, ~s(#roll-batch input[name="strips"][value="2"]))

        preview(view)
        no_singles(view)
        preview(view)
        html = no_singles(view)

        # Full, and still on the bench: not published, not asked anything.
        refute html =~ "is being published"
        refute has_element?(view, "#roll-end")
        assert has_element?(view, "#hardware-scan .adm-scan-roll", "Roll 001")
        refute File.read!(Negatives.catalog_path()) =~ "001,#{today()}"

        # The next look is the next roll's; the full one is listed, waiting.
        preview(view)
        assert has_element?(view, "#hardware-scan .adm-scan-roll", "Roll 002")
        assert length(Web.Scanner.list_strips(roll_dir(root))) == 2
        assert has_element?(view, "#waiting-rolls", "Roll 001")

        view
        |> element(~s(#waiting-rolls button[phx-value-roll="001"]), "Publish")
        |> render_click()

        render_async(view, 20_000)
        assert File.read!(Negatives.catalog_path()) =~ "001,#{today()},120,bw,2,120 Film/"

        # Blank turns the count off.
        view |> form("#roll-batch") |> render_change(%{"strips" => ""})
        refute has_element?(view, "#hardware-scan .adm-scan-roll", " of ")
      end

      test "a load that takes a roll past its sleeve joins it whole, and the roll's end is asked after",
           %{conn: conn, root: root} do
        Web.SiteSettings.put_setting("scanner_strips_per_roll", "2")
        glass!([{32..423, @orange}])
        view = open_studio(conn)
        preview(view)
        no_singles(view)

        # Both slots filled: the roll's second strip and one more.
        glass!([{32..423, @orange}, {615..1006, @orange}])
        preview(view)

        # Nothing was divided at the look: all three are this roll's, and
        # both of the load's strips are offered for singles.
        assert length(Web.Scanner.list_strips(roll_35(root))) == 3
        refute has_element?(view, "#roll-end")
        refute File.dir?(Path.join(root, "35mm Film/roll002_#{today()}_35mm_color"))

        no_singles(view)

        # Settled: now it asks, with the last strip chosen, and holds Preview.
        assert has_element?(view, "#roll-end", "a sleeve holds 2")
        assert has_element?(view, ~s(#roll-end button.is-chosen), "strip 3")
        assert has_element?(view, ~s(#roll-end button[phx-value-file]), "strip 2")

        assert view |> element("button", "Preview") |> render_click() =~
                 "Say which begins roll 002"

        refute File.read!(Negatives.catalog_path()) =~ "001,#{today()}"

        html = view |> element("#end-roll") |> render_click()
        render_async(view, 20_000)

        assert html =~ "Roll 001 keeps 2 strips and waits to be published"
        assert has_element?(view, "#hardware-scan .adm-scan-roll", "Roll 002")
        assert length(Web.Scanner.list_strips(roll_35(root))) == 2

        assert length(
                 Web.Scanner.list_strips(
                   Path.join(root, "35mm Film/roll002_#{today()}_35mm_color")
                 )
               ) == 1

        assert has_element?(view, "#waiting-rolls", "Roll 001")
        refute File.read!(Negatives.catalog_path()) =~ "001,#{today()}"
      end

      test "the other strip of the load can be the one that begins the next roll", %{
        conn: conn,
        root: root
      } do
        Web.SiteSettings.put_setting("scanner_strips_per_roll", "2")
        glass!([{32..423, @orange}])
        view = open_studio(conn)
        preview(view)
        no_singles(view)
        glass!([{32..423, @orange}, {615..1006, @orange}])
        preview(view)
        no_singles(view)

        before =
          for name <- ["002.tiff", "003.tiff"], do: File.read!(Path.join(roll_35(root), name))

        view |> element(~s(#roll-end button[phx-value-file="002.tiff"])) |> render_click()
        assert has_element?(view, ~s(#roll-end button.is-chosen), "strip 2")
        view |> element("#end-roll") |> render_click()
        render_async(view, 20_000)

        # What was the second strip is the next roll's first; the third took its place.
        [second, third] = before
        next = Path.join(root, "35mm Film/roll002_#{today()}_35mm_color")
        assert File.read!(Path.join(next, "001.tiff")) == second
        assert File.read!(Path.join(roll_35(root), "002.tiff")) == third
      end
    end

    @tag :capture_log
    test "a failed scan is reported and leaves the roll as it was", %{conn: conn, root: root} do
      with_env("STUB_SCANIMAGE_FAIL", "1")
      view = open_studio(conn)
      view |> element("button", "Create the folder") |> render_click()

      view |> element("button", "Preview") |> render_click()
      assert_receive {:scanner, :failed, _job, _reason}, 5_000

      assert render(view) =~ "Scan failed: scanimage exited 1"
      assert File.ls!(roll_dir(root)) == ["frames"]
      assert has_element?(view, "#hardware-scan button.adm-scan-go", "Preview")
    end
  end

  describe "from strips to a published roll" do
    defp put_strips(root, names) do
      dir = roll_dir(root)
      File.mkdir_p!(Path.join(dir, "frames"))
      for name <- names, do: File.write!(Path.join(dir, name), "strip scan")
      dir
    end

    @tag :capture_log
    test "Publish is one press: the frames are found, the sheet made and checked, the roll listed",
         %{conn: conn, root: root} do
      put_strips(root, ["001.tiff", "002.tiff"])
      view = open_studio(conn)

      view |> element("button", "Publish roll") |> render_click()
      assert render_async(view, 10_000) =~ "Roll 001 is on /negatives."

      assert has_element?(view, ~s(#keeper-rescan a[href="/negatives/roll/001"]))
      assert File.read!(Negatives.catalog_path()) =~ "001,#{today()},120,bw,2,120 Film/"

      # The roll is done: the one thing to press is the next roll.
      assert has_element?(view, "#hardware-scan button.adm-scan-go", "Start the next roll")
      refute has_element?(view, "#hardware-scan button", "Publish roll")

      view |> element("button", "Start the next roll") |> render_click()
      assert render(view) =~ "120 Film/roll002_#{today()}_120_bw"
      assert has_element?(view, "#hardware-scan button.adm-scan-go", "Preview")
    end

    test "a tool that fails names the step, and nothing is published or invented", %{
      conn: conn,
      root: root
    } do
      dir = put_strips(root, ["001.tiff", "002.tiff"])
      with_env("STUB_FILM_DEVELOP_FAIL", "1")
      view = open_studio(conn)

      view |> element("button", "Publish roll") |> render_click()
      html = render_async(view, 10_000)

      assert html =~ "Not published. Finding the frames: film-develop exited 3"
      assert has_element?(view, "#collection .adm-scan-fault", "Finding the frames")
      refute File.exists?(Path.join(dir, "frames.json"))
      refute File.read!(Negatives.catalog_path()) =~ "001,"
      assert has_element?(view, "#hardware-scan button", "Publish roll")
    end

    test "a sheet that fails its checks is not published, and the check is named", %{
      conn: conn,
      root: root
    } do
      # One strip composes to a different sheet from the 8x10 the stub writes.
      put_strips(root, ["001.tiff", "002.tiff", "003.tiff", "004.tiff", "005.tiff"])
      view = open_studio(conn)

      view |> element("button", "Publish roll") |> render_click()
      html = render_async(view, 10_000)

      assert html =~
               "Not published. The checks: the sheet is not the size those strips compose to"

      refute File.read!(Negatives.catalog_path()) =~ "001,"
    end

    test "a roll with no strips has nothing to publish", %{conn: conn} do
      view = open_studio(conn)

      assert render_click(view, "publish") |> then(fn _ -> render_async(view) end) =~
               "Not published. Strips: the roll has no strips yet"
    end

    test "a strip put back by hand has its singles picked from its row, and scanned one by one",
         %{conn: conn, root: root} do
      dir = put_strips(root, ["001.tiff", "002.tiff"])
      view = open_studio(conn)

      view |> element("button", "Analyse strips") |> render_click()
      render_async(view)

      # Analysing does not put anything up for choosing: nothing is on the glass.
      refute has_element?(view, "#keeper-rescan input")

      view
      |> element(~s(#strips button[phx-click="pick_singles"][phx-value-file="002.tiff"]))
      |> render_click()

      assert has_element?(view, ~s(#keeper-rescan input[phx-value-frame="3"][checked]))
      refute has_element?(view, ~s(#keeper-rescan input[phx-value-frame="1"]))

      view |> element("button", "Scan 1 single") |> render_click()

      assert render_async(view) =~ "Scanned frame 3. Load the next strips and press Preview."
      assert File.regular?(Path.join(dir, "raw-frames/frame-03.tiff"))
      assert File.ls!(Path.join(dir, "frames")) == ["03.png"]
      assert has_element?(view, "#collection .adm-scan-single", "Frame 3")
    end
  end
end
