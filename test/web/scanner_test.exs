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

    # "Negative Film" would have the backend correct the orange mask before
    # film-develop does.
    test "every scan goes through the transparency unit, unconverted" do
      for args <- [
            Driver.preview_args("dev", "/tmp/p.png"),
            Driver.strip_args("dev", "120", "bw", "/tmp/s.tiff"),
            Driver.keeper_args("dev", "120", "color", nil, "/tmp/k.tiff")
          ] do
        assert ["-d", "dev", "--source", "Transparency Unit", "--film-type", "Positive Film" | _] =
                 args
      end
    end

    # The V550 has no 300: asked for it, scanimage scans at 400 and exits 0.
    test "a strip is cut to its format's holder rectangle, scanned at 400 dpi and kept at 300" do
      args = Driver.strip_args("dev", "35mm", "color", "/tmp/s.tiff")
      assert Driver.strip_resample() == {400, 300}

      assert [
               "tiff:/tmp/s.tiff",
               "-resize",
               "75.0000%",
               "-units",
               "PixelsPerInch",
               "-density",
               "300",
               "tiff:/tmp/s.tiff"
             ] =
               Driver.resample_args("/tmp/s.tiff", {400, 300})

      assert Enum.chunk_every(args, 2, 1) |> Enum.member?(["--resolution", "400"])
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
      assert Enum.chunk_every(args, 2, 1) |> Enum.member?(["--resolution", "1600"])
      assert ["-l", "80.0", "-t", "52.4" | _] = area_of(args)
    end

    test "the look at the holder is the whole glass in colour at the scanner's quickest" do
      args = Driver.pass_args("dev", "/tmp/pass.tiff")

      assert area_of(args) == []
      assert Enum.chunk_every(args, 2, 1) |> Enum.member?(["--resolution", "400"])
      assert Enum.chunk_every(args, 2, 1) |> Enum.member?(["--mode", "Color"])
    end

    test "chosen frames share a crossing of the glass when they are side by side or neighbours" do
      # Two slots, 37 mm apart. Frames 4 and 5 follow one another on the left
      # strip, frame 10 lies beside frame 5 on the right, frame 1 is far up.
      frames = [
        {1, {2.0, 10.0, 25.0, 38.0}},
        {4, {2.0, 126.0, 25.0, 38.0}},
        {5, {2.0, 165.0, 25.0, 38.0}},
        {10, {39.0, 170.0, 25.0, 38.0}}
      ]

      assert [first, second] = Driver.bands(frames)

      assert first.rect == {2.0, 10.0, 25.0, 38.0}
      assert Enum.map(first.frames, &elem(&1, 0)) == [1]

      # One band as wide as both slots and as long as the three frames.
      assert second.rect == {2.0, 126.0, 62.0, 82.0}
      assert Enum.map(second.frames, &elem(&1, 0)) == [4, 5, 10]

      args = Driver.band_args("dev", "color", second.rect, "/tmp/band.tiff")
      assert Enum.chunk_every(args, 2, 1) |> Enum.member?(["--resolution", "1600"])
      assert ["-l", "2.0", "-t", "126.0", "-x", "62.0", "-y", "82.0"] = area_of(args)
      assert Driver.bands([]) == []
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

      assert <<"II*", 0, _rest::binary>> = File.read!(target)
      refute File.exists?(Bed.partial(target))
      assert %{job: nil} = Bed.status(bed)
    end

    test "a scan to be resampled lands at the resolution asked for", %{bed: bed, target: target} do
      job = %{kind: :strip, target: target, resample: {400, 300}}
      assert :ok = Bed.scan(bed, job, Driver.strip_args("dev", "120", "bw", Bed.partial(target)))

      assert_receive {:scanner, :done, %{target: ^target}}, 5_000
      assert <<"II*", 0, _rest::binary>> = File.read!(target)
      refute File.exists?(Bed.partial(target))
    end

    @tag :capture_log
    test "a scan that can't be resampled is a failed scan", %{bed: bed, target: target} do
      with_env("STUB_MAGICK_FAIL", "1")

      job = %{kind: :strip, target: target, resample: {400, 300}}
      assert :ok = Bed.scan(bed, job, Driver.strip_args("dev", "120", "bw", Bed.partial(target)))

      assert_receive {:scanner, :failed, %{target: ^target}, reason}, 5_000
      assert reason =~ "300 dpi"
      refute File.exists?(target)
      refute File.exists?(Bed.partial(target))
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

    test "a roll cut in fives is analysed again at the count that fits" do
      with_env("STUB_FILM_DEVELOP_FIVES", "1")
      dir = roll_with_strips("031", ["001.tiff"])

      assert {:ok, _path} = Pipeline.generate_frames_analysis(dir, "35mm", "color")

      assert [%{frame: 1, mis_split?: false, well_exposed?: true, quality: 0.8}, _] =
               Pipeline.frames(dir)
    end

    test "once a frame is printed the count stays, and the strip's frames are not proposed" do
      with_env("STUB_FILM_DEVELOP_FIVES", "1")
      dir = roll_with_strips("031", ["001.tiff"])
      File.write!(Path.join(dir, "frames/02.png"), "print")

      # Not an error: the tool wrote frames.json and says in it what is wrong.
      assert {:ok, _path} = Pipeline.generate_frames_analysis(dir, "35mm", "color")

      assert [%{frame: 1, mis_split?: true} = first, %{frame: 2, printed?: true}] =
               Pipeline.frames(dir)

      refute Pipeline.suggested?(first)
    end

    test "a frame is proposed when it is well exposed and has no print yet" do
      frame = %{well_exposed?: true, mis_split?: false, printed?: false}

      assert Pipeline.suggested?(frame)
      refute Pipeline.suggested?(%{frame | well_exposed?: false})
      refute Pipeline.suggested?(%{frame | printed?: true})
    end

    test "selections are kept per frame, and a later run leaves the earlier ones" do
      dir = roll_with_strips("031")
      assert {:ok, _path} = Pipeline.generate_frames_analysis(dir, "120", "bw")
      [one, two, three, four] = Pipeline.frames(dir)

      assert :ok = Pipeline.record_selects(dir, [one, two], [2])
      assert :ok = Pipeline.record_selects(dir, [three, four], [3])

      assert %{
               "1" => %{"suggested" => true, "chosen" => false, "quality" => 0.8},
               "2" => %{"suggested" => false, "chosen" => true},
               "3" => %{"suggested" => true, "chosen" => true, "strip" => "002.tiff"},
               "4" => %{"chosen" => false}
             } = Pipeline.read_selects(dir)
    end

    test "a frame lies landscape until it is turned, and its turn outlives a new choice" do
      dir = roll_with_strips("031")
      assert {:ok, _path} = Pipeline.generate_frames_analysis(dir, "120", "bw")

      # The stub's frames are 656 wide by 700 tall: on their side.
      assert Pipeline.rotation(dir, 1) == 270
      assert Pipeline.turn_frame(dir, 1) == 0
      assert Pipeline.turn_frame(dir, 1) == 90

      [one | _] = Pipeline.frames(dir)
      assert :ok = Pipeline.record_selects(dir, [one], [1])

      assert Pipeline.rotation(dir, 1) == 90
      assert %{"1" => %{"rotate" => 90, "chosen" => true}} = Pipeline.read_selects(dir)
      assert Pipeline.rotation(dir, 2) == 270
    end

    test "a frame is found on the glass while its strip is where the pass left it" do
      dir = roll_with_strips("031")
      assert {:ok, _path} = Pipeline.generate_frames_analysis(dir, "120", "bw")
      assert Pipeline.glass_rect(dir, 2, 0.5) == nil

      File.write!(
        Path.join(dir, "holder.json"),
        Jason.encode!(%{"strips" => %{"001.tiff" => [2.0, 9.0, 55.5, 200.0]}})
      )

      assert Pipeline.holder(dir) == %{"001.tiff" => {2.0, 9.0, 55.5, 200.0}}

      # The stub's second frame starts 726 px (61.5 mm) down its 300 dpi strip
      # and is 700 px (59.3 mm) long.
      assert {l, t, w, h} = Pipeline.glass_rect(dir, 2, 0.5)
      assert_in_delta l, 2.0, 0.01
      assert_in_delta t, 9.0 + 61.47 - 0.5, 0.01
      assert_in_delta w, 55.5, 0.01
      assert_in_delta h, 59.27 + 1.0, 0.01

      # A strip on the roll that the pass did not see is not on the glass.
      assert Pipeline.glass_rect(dir, 3, 0.5) == nil

      # Reordering renames the files, not the film: the strip on the glass is
      # still where it was, under its new name.
      Pipeline.reorder_strips(dir, ["002.tiff", "001.tiff"])
      assert Pipeline.holder(dir) == %{"002.tiff" => {2.0, 9.0, 55.5, 200.0}}
    end

    # The suite's strips are not pictures; these three tests turn and analyse real ones.
    if System.find_executable("magick") do
      defp real_roll(roll_num, strips) do
        {:ok, dir} = Pipeline.prepare_roll(roll_num, "2026-10-02", "120", "bw")

        for name <- strips do
          {_, 0} = System.cmd("magick", ["-size", "8x16", "xc:gray50", Path.join(dir, name)])
        end

        File.mkdir_p!(Path.join(dir, "raw-frames"))
        assert {:ok, _path} = Pipeline.generate_frames_analysis(dir, "120", "bw")
        dir
      end

      # A single, as a picture that says which frame it was made from.
      defp put_single(dir, frame, grey) do
        name = String.pad_leading("#{frame}", 2, "0")

        {_, 0} =
          System.cmd("magick", [
            "-size",
            "4x2",
            "xc:gray#{grey}",
            Path.join(dir, "frames/#{name}.png")
          ])

        File.write!(Path.join(dir, "raw-frames/frame-#{name}.tiff"), "raw #{frame}")
      end

      defp grey_of(dir, frame) do
        name = String.pad_leading("#{frame}", 2, "0")

        {out, 0} =
          System.cmd("magick", [
            Path.join(dir, "frames/#{name}.png"),
            "-format",
            "%[fx:round(mean*100)] %w",
            "info:"
          ])

        out
      end

      test "deleting a strip takes its singles and carries the others to their frames' new numbers" do
        # Three strips of two frames: 1-2, 3-4, 5-6.
        dir = real_roll("041", ["001.tiff", "002.tiff", "003.tiff"])
        put_single(dir, 2, 20)
        put_single(dir, 3, 30)
        put_single(dir, 6, 60)
        frames = Pipeline.frames(dir)
        Pipeline.record_selects(dir, frames, [2, 3, 6])
        Pipeline.turn_frame(dir, 6)

        Pipeline.delete_strip(dir, "001.tiff")

        # Frame 3 is now 1 and frame 6 is now 4; frame 2's strip is gone.
        assert Pipeline.printed_frames(dir) == [1, 4]
        assert grey_of(dir, 1) =~ "30 "
        assert grey_of(dir, 4) =~ "60 "
        assert File.read!(Path.join(dir, "raw-frames/frame-04.tiff")) == "raw 6"

        assert File.ls!(Path.join(dir, "raw-frames")) |> Enum.sort() ==
                 ~w(frame-01.tiff frame-04.tiff)

        selects = Pipeline.read_selects(dir)
        assert %{"chosen" => true, "strip" => "001.tiff"} = selects["1"]
        assert %{"chosen" => true, "strip" => "002.tiff", "rotate" => _} = selects["4"]
        assert selects["2"]["chosen"] == false
        refute Map.has_key?(selects, "6")
      end

      test "a new roll begun at a strip takes that strip, what follows, and all that is theirs" do
        # Three strips of two frames: 1-2, 3-4, 5-6. The roll really ended after the first.
        dir = real_roll("044", ["001.tiff", "002.tiff", "003.tiff"])
        put_single(dir, 2, 20)
        put_single(dir, 3, 30)
        put_single(dir, 6, 60)
        Pipeline.record_selects(dir, Pipeline.frames(dir), [2, 3, 6])
        place = [2.0, 9.0, 25.0, 226.0]

        File.write!(
          Path.join(dir, "holder.json"),
          Jason.encode!(%{
            "pending" => true,
            "strips" => %{"002.tiff" => place, "003.tiff" => place}
          })
        )

        assert {:error, _} = Pipeline.split_roll(dir, "001.tiff")
        # The new roll takes the lowest free number and this roll's date and film.
        assert {:ok, {number, "2026-10-02", "120", "bw"}} = Pipeline.split_roll(dir, "002.tiff")
        assert number == "001"
        new = Pipeline.roll_dir(number, "2026-10-02", "120", "bw")

        assert Enum.map(Pipeline.list_strips(dir), & &1.file) == ["001.tiff"]
        assert Enum.map(Pipeline.list_strips(new), & &1.file) == ["001.tiff", "002.tiff"]

        # The old roll keeps frame 2; frames 3 and 6 are the new roll's 1 and 4.
        assert Pipeline.printed_frames(dir) == [2]
        assert Pipeline.printed_frames(new) == [1, 4]
        assert grey_of(new, 1) =~ "30 "
        assert grey_of(new, 4) =~ "60 "
        assert File.read!(Path.join(new, "raw-frames/frame-04.tiff")) == "raw 6"

        assert Map.keys(Pipeline.read_selects(dir)) |> Enum.sort() == ["1", "2"]

        assert %{"1" => %{"chosen" => true, "strip" => "001.tiff"}, "4" => %{"chosen" => true}} =
                 Pipeline.read_selects(new)

        # The glass went with the strips, still to be settled.
        assert Pipeline.holder(dir) == %{}
        assert Pipeline.pending_load(new) == ["001.tiff", "002.tiff"]
      end

      test "a strip laid back in the holder is found: which it is, where, and which way up" do
        {:ok, dir} = Pipeline.prepare_roll("046", "2026-10-02", "35mm", "bw")
        base = Path.dirname(Path.dirname(dir))

        # Two strips with pictures of their own, 25 mm by 190 mm at 300 dpi.
        for {name, seed} <- [{"001.tiff", 7}, {"002.tiff", 23}] do
          {_, 0} =
            System.cmd("magick", [
              "-size",
              "295x2244",
              "-seed",
              "#{seed}",
              "plasma:fractal",
              "-colorspace",
              "Gray",
              "-depth",
              "8",
              Path.join(dir, name)
            ])
        end

        # The glass, 68.58 mm across at 400 dpi: black holder, and strip 2 laid
        # in the second slot, 12 mm further down than a strip starts, and
        # turned end for end.
        glass = Path.join(base, "scanner_pass_again.tiff")

        {_, 0} =
          System.cmd("magick", [
            "-size",
            "1080x3600",
            "xc:black",
            "(",
            Path.join(dir, "002.tiff"),
            "-resize",
            "133.3333%",
            "-rotate",
            "180",
            ")",
            "-geometry",
            "+614+189",
            "-composite",
            "-depth",
            "8",
            glass
          ])

        found = [%{left_mm: 614 / 400 * 25.4, width_mm: 393 / 400 * 25.4}]
        assert {:ok, ["002.tiff"]} = Pipeline.relocate(dir, glass, 400, found, nil)

        assert %{"002.tiff" => {left, top, _width, _tall}} = Pipeline.holder(dir)
        assert_in_delta left, 39.0, 0.1
        assert_in_delta top, 12.0, 1.0
        assert File.read!(Path.join(dir, "holder.json")) =~ ~s("flipped")

        # Film that is none of the roll's is not taken for any of it.
        other = Path.join(base, "scanner_pass_other.tiff")

        {_, 0} =
          System.cmd("magick", [
            "-size",
            "1080x3600",
            "xc:black",
            "(",
            "-size",
            "393x2992",
            "-seed",
            "99",
            "plasma:fractal",
            "-colorspace",
            "Gray",
            ")",
            "-geometry",
            "+614+189",
            "-composite",
            "-depth",
            "8",
            other
          ])

        assert {:ok, []} = Pipeline.relocate(dir, other, 400, found, nil)

        # Asked of every roll at once, the film names its own roll.
        {:ok, elsewhere} = Pipeline.prepare_roll("047", "2026-10-02", "35mm", "bw")

        {_, 0} =
          System.cmd("magick", [
            "-size",
            "295x2244",
            "-seed",
            "51",
            "plasma:fractal",
            "-colorspace",
            "Gray",
            "-depth",
            "8",
            Path.join(elsewhere, "001.tiff")
          ])

        rolls = [%{roll: "047", dir: elsewhere}, %{roll: "046", dir: dir}]
        File.rm!(Path.join(dir, "holder.json"))

        assert {:ok, {%{roll: "046"}, ["002.tiff"]}} =
                 Pipeline.identify(rolls, glass, 400, found, nil)

        assert Map.keys(Pipeline.holder(dir)) == ["002.tiff"]
        assert Pipeline.holder(elsewhere) == %{}
        assert :none = Pipeline.identify(rolls, other, 400, found, fn _roll -> nil end)
      end

      test "reordering strips swaps their singles' numbers without losing either" do
        dir = real_roll("042", ["001.tiff", "002.tiff"])
        put_single(dir, 1, 10)
        put_single(dir, 3, 30)

        Pipeline.reorder_strips(dir, ["002.tiff", "001.tiff"])

        assert Pipeline.printed_frames(dir) == [1, 3]
        assert grey_of(dir, 1) =~ "30 "
        assert grey_of(dir, 3) =~ "10 "
      end

      test "turning a strip over reverses its frames, and each single is turned with its frame" do
        dir = real_roll("043", ["001.tiff", "002.tiff"])
        put_single(dir, 1, 10)
        put_single(dir, 4, 40)
        place = [2.0, 9.0, 25.0, 226.0]

        File.write!(
          Path.join(dir, "holder.json"),
          Jason.encode!(%{"strips" => %{"001.tiff" => place, "002.tiff" => place}})
        )

        assert :ok = Pipeline.rotate_strip(Path.join(dir, "001.tiff"))

        # The turned strip's frames no longer lie where its file says; the
        # other strip's still do.
        assert Map.keys(Pipeline.holder(dir)) == ["002.tiff"]

        # Frame 1 is the strip's second frame now; the other strip is untouched.
        assert Pipeline.printed_frames(dir) == [2, 4]
        assert grey_of(dir, 2) =~ "10 "
        assert grey_of(dir, 4) =~ "40 "
      end
    end

    test "a load is pending until settled, and a pending load can be taken back out" do
      dir = roll_with_strips("031", ["001.tiff", "002.tiff", "003.tiff"])
      put_holder = fn doc -> File.write!(Path.join(dir, "holder.json"), Jason.encode!(doc)) end
      place = [2.0, 9.0, 25.0, 226.0]

      assert Pipeline.pending_load(dir) == []

      # The last two strips came from a look that has not been settled.
      put_holder.(%{"pending" => true, "strips" => %{"002.tiff" => place, "003.tiff" => place}})
      assert Pipeline.pending_load(dir) == ["002.tiff", "003.tiff"]

      assert :ok = Pipeline.confirm_load(dir)
      assert Pipeline.pending_load(dir) == []
      assert Map.keys(Pipeline.holder(dir)) == ["002.tiff", "003.tiff"]

      # Settled strips are the roll's: discarding does nothing to them.
      assert :ok = Pipeline.discard_load(dir)
      assert length(Pipeline.list_strips(dir)) == 3

      put_holder.(%{"pending" => true, "strips" => %{"002.tiff" => place, "003.tiff" => place}})
      File.write!(Path.join(dir, "frames.json"), "{}")
      assert :ok = Pipeline.discard_load(dir)

      assert Enum.map(Pipeline.list_strips(dir), & &1.file) == ["001.tiff"]
      assert Pipeline.holder(dir) == %{}
      refute File.exists?(Path.join(dir, "frames.json"))
    end

    test "a pending load that is not the roll's last strips is kept, not cut out of the middle" do
      dir = roll_with_strips("031", ["001.tiff", "002.tiff", "003.tiff"])

      File.write!(
        Path.join(dir, "holder.json"),
        Jason.encode!(%{"pending" => true, "strips" => %{"001.tiff" => [2.0, 9.0, 25.0, 226.0]}})
      )

      assert :ok = Pipeline.discard_load(dir)
      assert length(Pipeline.list_strips(dir)) == 3
      assert Pipeline.pending_load(dir) == []
    end

    test "a single taken out of the collection leaves its frame, and is recorded as not kept" do
      dir = roll_with_strips("031")
      assert {:ok, _path} = Pipeline.generate_frames_analysis(dir, "120", "bw")
      [one | _] = Pipeline.frames(dir)
      Pipeline.record_selects(dir, [one], [1])

      File.mkdir_p!(Path.join(dir, "frames/previews"))
      File.mkdir_p!(Path.join(dir, "raw-frames"))

      for file <-
            ~w(frames/01.png frames/previews/01.webp frames/previews/01-480.webp raw-frames/frame-01.tiff frames/02.png) do
        File.write!(Path.join(dir, file), "x")
      end

      assert :ok = Pipeline.remove_print(dir, 1)

      assert Pipeline.printed_frames(dir) == [2]
      assert File.ls!(Path.join(dir, "frames/previews")) == []
      refute File.exists?(Path.join(dir, "raw-frames/frame-01.tiff"))
      assert %{"1" => %{"chosen" => false, "removed" => true}} = Pipeline.read_selects(dir)
      assert [%{frame: 1, printed?: false} | _] = Pipeline.frames(dir)
    end

    test "finishing a roll is the analysis, the sheet, the checks and the catalog, or the step that failed" do
      roll_with_strips("031")
      assert {:ok, "031"} = Pipeline.finish_roll("031", "2026-10-02", "120", "bw")
      assert File.read!(Negatives.catalog_path()) =~ "031,2026-10-02,120,bw,2,"

      Pipeline.prepare_roll("032", "2026-10-02", "120", "bw")
      assert {:error, :strips, _} = Pipeline.finish_roll("032", "2026-10-02", "120", "bw")

      roll_with_strips("033")
      with_env("STUB_CONTACT_SHEET_FAIL", "1")
      assert {:error, :sheet, text} = Pipeline.finish_roll("033", "2026-10-02", "120", "bw")
      assert text =~ "digital-contact-sheet-maker"
      refute File.read!(Negatives.catalog_path()) =~ "033,"
    end

    test "a roll's record of the glass holds only until the next look, into any roll", %{
      root: root
    } do
      first = roll_with_strips("031", ["001.tiff"])
      second = roll_with_strips("032", ["001.tiff"])
      place = [2.0, 9.0, 25.0, 226.0]

      put = fn dir, look ->
        File.write!(
          Path.join(dir, "holder.json"),
          Jason.encode!(%{"look" => look, "strips" => %{"001.tiff" => place}})
        )
      end

      put.(first, "scanner_pass_1.tiff")
      File.write!(Path.join(root, ".on-glass"), "scanner_pass_1.tiff")
      assert Map.keys(Pipeline.holder(first)) == ["001.tiff"]

      # The holder is loaded again and looked at, for another roll.
      put.(second, "scanner_pass_2.tiff")
      File.write!(Path.join(root, ".on-glass"), "scanner_pass_2.tiff")

      assert Pipeline.holder(first) == %{}
      assert Map.keys(Pipeline.holder(second)) == ["001.tiff"]

      # So a single chosen on the first roll and never made can no longer be
      # scanned by pressing a button: its film is not there.
      File.write!(
        Path.join(first, "frames.json"),
        Jason.encode!(%{
          "strips" => [
            %{
              "file" => "001.tiff",
              "width" => 300,
              "height" => 900,
              "frames" => [%{"frame" => 1, "region" => [0, 0, 300, 400]}]
            }
          ]
        })
      )

      File.write!(
        Path.join(first, "selects.json"),
        Jason.encode!(%{"frames" => %{"1" => %{"chosen" => true}}})
      )

      assert [%{frame: 1, on_glass?: false}] = Pipeline.owed_singles(first)
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

      # Set upright, so the stub's print, which is no picture, is not turned.
      assert Pipeline.turn_frame(dir, 3) == 0

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

  describe "a slide's singles are scanned deep" do
    alias Web.Scanner.Driver

    test "sixteen bits when asked, eight otherwise" do
      band = Driver.band_args("dev", "color", {1.0, 2.0, 30.0, 40.0}, "out.tiff")
      deep = Driver.band_args("dev", "color", {1.0, 2.0, 30.0, 40.0}, "out.tiff", deep: true)

      refute "--depth" in band
      assert ["--depth", "16"] == deep |> Enum.drop_while(&(&1 != "--depth")) |> Enum.take(2)
      assert deep -- ["--depth", "16"] == band
    end

    test "a roll is a slide roll once its analysis says so" do
      dir = Path.join(System.tmp_dir!(), "slide-roll-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)

      refute Web.Scanner.slide?(dir)
      File.write!(Path.join(dir, "frames.json"), ~s({"mode": "color", "strips": []}))
      refute Web.Scanner.slide?(dir)
      File.write!(Path.join(dir, "frames.json"), ~s({"mode": "slide", "strips": []}))
      assert Web.Scanner.slide?(dir)
    end
  end
end
