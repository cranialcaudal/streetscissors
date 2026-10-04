defmodule Web.ScannerTest do
  # Not async: the archive path, the stubs' switches and the bed are shared.
  use ExUnit.Case, async: false

  alias Web.Negatives
  alias Web.NegativesFixtures, as: Fixture
  alias Web.Scanner.{Bed, Driver, Pipeline, Simulation}

  @epson "device `epkowa:interpreter:001:050' is a Epson Perfection V550 Photo flatbed scanner"
  @webcam "device `v4l:/dev/video0' is a Noname Integrated Camera virtual device"

  defp with_env(name, value) do
    System.put_env(name, value)
    on_exit(fn -> System.delete_env(name) end)
  end

  defp with_areas(areas) do
    Application.put_env(:web, :scanner_areas, areas)
    on_exit(fn -> Application.delete_env(:web, :scanner_areas) end)
  end

  describe "Driver: devices" do
    test "a webcam is a SANE device too, and is never the scanner" do
      devices = Driver.parse_devices(@webcam <> "\n" <> @epson <> "\n")

      assert [%{type: :webcam}, %{type: :scanner, id: "epkowa:interpreter:001:050"}] = devices
      assert %{name: "Epson Perfection V550 Photo flatbed scanner"} = Driver.pick(devices)
      assert Driver.pick(Driver.parse_devices(@webcam)) == nil
      assert Driver.parse_devices("No scanners were identified.") == []
    end

    test "a pinned prefix chooses among scanners, whatever USB address it is on today" do
      other = "device `genesys:libusb:001:004' is a Canon LiDE 110 flatbed scanner"
      devices = Driver.parse_devices(other <> "\n" <> @epson)

      assert Driver.pick(devices).id =~ "genesys"

      Application.put_env(:web, :scanner_device, "epkowa")
      on_exit(fn -> Application.delete_env(:web, :scanner_device) end)

      assert Driver.pick(devices).id == "epkowa:interpreter:001:050"
    end
  end

  describe "Driver: what a film scan asks for" do
    setup do
      with_areas(%{"35mm" => "20.0,30.0,36.0,226.0", "120" => {80.0, 30.0, 62.0, 200.0}})
    end

    test "every scan goes through the transparency unit as negative film" do
      for args <- [
            Driver.preview_args("dev", "/tmp/p.png"),
            Driver.strip_args("dev", "120", "bw", "/tmp/s.tiff"),
            Driver.keeper_args("dev", "120", "color", nil, "/tmp/k.tiff")
          ] do
        assert ["-d", "dev", "--source", "Transparency Unit", "--film-type", "Negative Film" | _] =
                 args
      end
    end

    test "a strip is cut to its format's holder rectangle at 300 dpi" do
      args = Driver.strip_args("dev", "35mm", "color", "/tmp/s.tiff")

      assert Enum.chunk_every(args, 2, 1) |> Enum.member?(["--resolution", "300"])
      assert Enum.chunk_every(args, 2, 1) |> Enum.member?(["--mode", "Color"])
      assert ["-l", "20.0", "-t", "30.0", "-x", "36.0", "-y", "226.0"] = area_of(args)
      assert List.last(args) == "/tmp/s.tiff"

      # 620 is 120 film and sits in the 120 slot.
      assert area_of(Driver.strip_args("dev", "620", "bw", "/tmp/s.tiff")) ==
               ["-l", "80.0", "-t", "30.0", "-x", "62.0", "-y", "200.0"]
    end

    test "the preview is the whole transparency area; an unset format is not cut either" do
      assert area_of(Driver.preview_args("dev", "/tmp/p.png")) == []
      assert area_of(Driver.strip_args("dev", "110", "bw", "/tmp/s.tiff")) == []
    end

    test "a keeper is cut to its frame, a margin wider, and never past the slot" do
      # A frame 300 px (25.4 mm) into the strip, 600 px (50.8 mm) square.
      assert {l, t, w, h} = Driver.frame_area({80.0, 30.0, 62.0, 200.0}, {0, 300, 600, 600})

      assert_in_delta l, 80.0, 0.01
      assert_in_delta t, 30.0 + 25.4 - 3.0, 0.01
      assert_in_delta w, 50.8 + 3.0, 0.01
      assert_in_delta h, 50.8 + 6.0, 0.01

      args = Driver.keeper_args("dev", "120", "bw", {0, 300, 600, 600}, "/tmp/k.tiff")
      assert Enum.chunk_every(args, 2, 1) |> Enum.member?(["--resolution", "2400"])
      assert ["-l", "80.0", "-t", "52.4" | _] = area_of(args)
    end

    test "areas are read from left,top,width,height and refused when malformed" do
      assert Driver.parse_area("20, 30.5, 36, 226") == {20.0, 30.5, 36.0, 226.0}
      assert Driver.parse_area("20,30,36") == nil
      assert Driver.parse_area("20,30,0,226") == nil
      assert Driver.parse_area("a,b,c,d") == nil
      assert Driver.parse_area(nil) == nil
    end

    test "progress is the last figure in a chunk of redrawn lines" do
      assert Driver.progress("Progress: 10.0%\rProgress: 42.6%\r") == 43
      assert Driver.progress("scanimage: rounded value of br-x") == nil
    end

    defp area_of(args) do
      case Enum.find_index(args, &(&1 == "-l")) do
        nil -> []
        index -> Enum.slice(args, index, 8)
      end
    end
  end

  describe "Bed" do
    setup do
      bed =
        start_supervised!(
          {Bed, name: :"bed_#{System.unique_integer([:positive])}", scan_timeout: 300}
        )

      Bed.subscribe()

      dir = Path.join(System.tmp_dir!(), "bed_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)

      %{bed: bed, target: Path.join(dir, "001.tiff")}
    end

    defp scan(bed, target) do
      job = %{kind: :strip, target: target}
      Bed.scan(bed, job, Driver.strip_args("dev", "120", "bw", Bed.partial(target)))
    end

    test "a scan reports its progress and lands under its real name only when finished",
         %{bed: bed, target: target} do
      assert :ok = scan(bed, target)

      assert_receive {:scanner, :started, %{kind: :strip, target: ^target}}
      assert_receive {:scanner, :progress, _percent}
      assert_receive {:scanner, :done, %{target: ^target}}, 2_000

      assert File.read!(target) == "strip scan"
      refute File.exists?(Bed.partial(target))
      assert %{job: nil} = Bed.status(bed)
    end

    @tag :capture_log
    test "a failed scan leaves no file behind and says why", %{bed: bed, target: target} do
      with_env("STUB_SCANIMAGE_FAIL", "1")

      assert :ok = scan(bed, target)
      assert_receive {:scanner, :failed, %{target: ^target}, reason}, 2_000

      assert reason =~ "exited 1"
      assert reason =~ "Error during device I/O"
      refute File.exists?(target)
      refute File.exists?(Bed.partial(target))
    end

    @tag :capture_log
    test "one scan at a time, and a scan that hangs is stopped", %{bed: bed, target: target} do
      with_env("STUB_SCANIMAGE_HANG", "1")

      assert :ok = scan(bed, target)
      assert {:error, :busy} = scan(bed, target <> ".second")
      assert %{job: %{kind: :strip}} = Bed.status(bed)

      assert_receive {:scanner, :failed, _job, reason}, 2_000
      assert reason =~ "time limit"
      refute File.exists?(target)
      assert %{job: nil} = Bed.status(bed)
    end

    test "devices are listed off the calling process", %{bed: bed} do
      with_env("STUB_SCANIMAGE_DEVICES", @webcam <> "\n" <> @epson)

      assert %{devices: nil} = Bed.status(bed)
      Bed.refresh(bed)

      assert_receive {:scanner, :devices, [%{type: :webcam}, %{type: :scanner}]}, 2_000
      assert %{devices: [_, _], listing?: false} = Bed.status(bed)
    end
  end

  describe "Pipeline" do
    setup do
      %{root: Fixture.archive!()}
    end

    # Two strips: with the analysis stub's 656x2152 they compose to 8x10.
    defp roll_with_strips(roll_num, names \\ ["001.tiff", "002.tiff"]) do
      {:ok, dir} = Pipeline.prepare_roll(roll_num, "2026-10-02", "120", "bw")
      for name <- names, do: File.write!(Path.join(dir, name), "strip scan")
      dir
    end

    test "the next roll is the lowest number neither the catalog nor a folder claims", %{
      root: root
    } do
      assert Pipeline.next_roll_number() == "001"

      Fixture.put_roll!(root, roll: "001")
      File.mkdir_p!(Path.join(root, "35mm Film/roll002_2026-01-01_35mm_bw"))
      Fixture.put_roll!(root, roll: "999")

      assert Pipeline.next_roll_number() == "003"
    end

    test "prepare_roll creates the folder and frames/ inside it" do
      {:ok, dir} = Pipeline.prepare_roll("050", "2026-10-02", "120", "bw")

      assert dir =~ "120 Film/roll050_2026-10-02_120_bw"
      assert File.dir?(Path.join(dir, "frames"))
    end

    test "an uploaded scan becomes the next strip, as it is" do
      dir = roll_with_strips("051", ["001.tiff"])
      upload = Path.join(System.tmp_dir!(), "upload_#{System.unique_integer([:positive])}")
      File.write!(upload, "png bytes")
      on_exit(fn -> File.rm(upload) end)

      assert {:ok, "002.png"} = Pipeline.add_strip(dir, upload, "Scan 4.PNG")
      assert File.read!(Path.join(dir, "002.png")) == "png bytes"

      assert {:error, reason} = Pipeline.add_strip(dir, upload, "notes.txt")
      assert reason =~ "notes.txt"
    end

    test "reordering and deleting renumber strips, keep extensions, and drop the analysis" do
      dir = roll_with_strips("052", ["001.tiff", "002.png", "003.tiff"])
      File.write!(Path.join(dir, "001.tiff"), "first")
      File.write!(Path.join(dir, "002.png"), "second")
      assert {:ok, _} = Pipeline.generate_frames_analysis(dir, "120", "bw")

      assert :ok = Pipeline.reorder_strips(dir, ["002.png", "001.tiff", "003.tiff"])

      assert Enum.map(Pipeline.list_strips(dir), & &1.file) == ["001.png", "002.tiff", "003.tiff"]
      assert File.read!(Path.join(dir, "001.png")) == "second"
      refute File.exists?(Path.join(dir, "frames.json"))

      assert :ok = Pipeline.delete_strip(dir, "001.png")
      assert Enum.map(Pipeline.list_strips(dir), & &1.file) == ["001.tiff", "002.tiff"]
      assert File.read!(Path.join(dir, "001.tiff")) == "first"
    end

    @tag :capture_log
    test "a roll analysed, assembled and passing both gates is published" do
      dir = roll_with_strips("053")

      assert {:ok, _} = Pipeline.generate_frames_analysis(dir, "120", "bw")
      assert {:ok, sheet} = Pipeline.assemble_contact_sheet(dir, "053", "2026-10-02", "120", "bw")
      assert %{conforming?: true, frames_count: 4} = Pipeline.verify_conformance(dir, sheet)

      assert {:ok, "053"} = Pipeline.publish_roll("053", "2026-10-02", "120", "bw")

      # `frames` is the strip count, as the negatives command writes it.
      row = "053,2026-10-02,120,bw,2,120 Film/roll053_2026-10-02_120_bw"
      assert File.read!(Negatives.catalog_path()) |> String.split("\n") |> Enum.member?(row)

      # Publishing twice lists the roll once.
      assert {:ok, "053"} = Pipeline.publish_roll("053", "2026-10-02", "120", "bw")
      assert length(Regex.scan(~r/^053,/m, File.read!(Negatives.catalog_path()))) == 1
    end

    test "a roll that fails a gate is not published" do
      dir = roll_with_strips("054")
      catalog = File.read!(Negatives.catalog_path())

      # No analysis, no sheet.
      assert {:error, :not_conforming} = Pipeline.publish_roll("054", "2026-10-02", "120", "bw")

      # Analysed and assembled, then a strip added: the analysis is stale.
      {:ok, _} = Pipeline.generate_frames_analysis(dir, "120", "bw")
      {:ok, _} = Pipeline.assemble_contact_sheet(dir, "054", "2026-10-02", "120", "bw")
      File.write!(Path.join(dir, "003.tiff"), "late strip")

      assert {:error, :not_conforming} = Pipeline.publish_roll("054", "2026-10-02", "120", "bw")
      assert File.read!(Negatives.catalog_path()) == catalog
    end

    test "a tool that fails is reported, and nothing stands in for it" do
      dir = roll_with_strips("055")

      with_env("STUB_FILM_DEVELOP_FAIL", "1")
      assert {:error, reason} = Pipeline.generate_frames_analysis(dir, "120", "bw")
      assert reason =~ "film-develop exited 3"
      assert reason =~ "could not find the film edge"
      refute File.exists?(Path.join(dir, "frames.json"))

      with_env("STUB_CONTACT_SHEET_FAIL", "1")

      assert {:error, reason} =
               Pipeline.assemble_contact_sheet(dir, "055", "2026-10-02", "120", "bw")

      assert reason =~ "digital-contact-sheet-maker exited 4"

      refute File.exists?(
               Path.join(Negatives.contact_sheets_path(), "roll055_2026-10-02_120_bw.png")
             )
    end

    test "a tool that isn't installed is reported as that" do
      Application.put_env(:web, :film_develop_bin, "no-such-film-develop")

      on_exit(fn ->
        Application.put_env(
          :web,
          :film_develop_bin,
          Path.expand("../support/stub_film_develop", __DIR__)
        )
      end)

      assert {:error, "film-develop is not installed" <> _} =
               Pipeline.generate_frames_analysis(roll_with_strips("056"), "120", "bw")
    end

    test "a keeper's raw scan stays out of frames/ until it is developed" do
      dir = roll_with_strips("057")
      {:ok, _} = Pipeline.generate_frames_analysis(dir, "120", "bw")

      assert Pipeline.frame_region(dir, 3) == {0, 0, 656, 700}
      assert Pipeline.frame_region(dir, 9) == nil

      raw = Pipeline.keeper_raw_path(dir, 3)
      assert raw == Path.join(dir, "raw-frames/frame-03.tiff")
      File.mkdir_p!(Path.dirname(raw))
      File.write!(raw, "raw frame")

      assert File.ls!(Path.join(dir, "frames")) == []
      assert {:ok, print} = Pipeline.develop_keeper(dir, 3)
      assert print == Path.join(dir, "frames/03.png")
      assert File.regular?(print)
    end
  end

  test "simulation is a dev and test thing" do
    assert Simulation.enabled?()

    Application.put_env(:web, :scanner_simulation, false)
    on_exit(fn -> Application.put_env(:web, :scanner_simulation, true) end)

    refute Simulation.enabled?()
  end
end
