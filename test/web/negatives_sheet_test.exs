defmodule Web.NegativesSheetTest do
  use ExUnit.Case, async: false

  alias Web.Negatives.Sheet
  alias Web.NegativesFixtures, as: Fixture

  # Every one of these is really the same question: when is the archive
  # trustworthy enough to draw on a photograph? The answer has to be
  # conservative, because a mark in the wrong place points at the wrong picture.

  defp sheet(slug, roll \\ "013") do
    %{roll: roll, slug: slug, filename: "#{slug}.png"}
  end

  describe "dimensions/1" do
    setup do
      %{root: Fixture.archive!()}
    end

    test "reads width and height off the PNG header", %{root: root} do
      path = Fixture.put_sheet!(root, "roll001_2026-01-01_120_bw", 3000, 2400)
      assert Sheet.dimensions(path) == {:ok, {3000, 2400}}
    end

    test "refuses anything that is not a PNG", %{root: root} do
      path = Path.join([root, "Contact Sheets", "not-a-sheet.png"])
      File.write!(path, "JFIF, honestly")
      assert Sheet.dimensions(path) == :error
    end

    test "refuses a file too short to carry a header", %{root: root} do
      path = Path.join([root, "Contact Sheets", "truncated.png"])
      File.write!(path, <<137, "PNG", 13, 10, 26, 10>>)
      assert Sheet.dimensions(path) == :error
    end

    test "refuses a file that is not there" do
      assert Sheet.dimensions("/nowhere/at/all.png") == :error
    end
  end

  describe "marks/2 when a roll has prints" do
    setup do
      root = Fixture.archive!()
      {folder, slug} = Fixture.golden_roll!(root)
      %{root: root, folder: folder, slug: slug}
    end

    test "places a printed frame where the assembler put it", %{folder: folder, slug: slug} do
      Fixture.put_print!(folder, 1)

      assert [mark] = Sheet.marks(sheet(slug), [1])
      assert mark.frame == 1

      # Worked by hand: the frame sits at {532, 424, 656, 700} on a 2400x3000
      # sheet, and the mark box is padded by a tenth of the frame's short side
      # so the pencil has somewhere to overshoot.
      pad = 0.1 * 656
      assert_in_delta mark.left, (532 - pad) / 2400 * 100, 0.001
      assert_in_delta mark.top, (424 - pad) / 3000 * 100, 0.001
      assert_in_delta mark.width, (656 + 2 * pad) / 2400 * 100, 0.001
      assert_in_delta mark.height, (700 + 2 * pad) / 3000 * 100, 0.001
    end

    test "marks only the frames asked for", %{folder: folder, slug: slug} do
      for n <- 1..4, do: Fixture.put_print!(folder, n)

      assert Sheet.marks(sheet(slug), [2, 4]) |> Enum.map(& &1.frame) == [2, 4]
    end

    test "a frame on the second strip lands one strip and one gap along",
         %{folder: folder, slug: slug} do
      Fixture.put_print!(folder, 3)

      assert [%{left: left}] = Sheet.marks(sheet(slug), [3])
      pad = 0.1 * 656
      assert_in_delta left, (532 + 656 + 24 - pad) / 2400 * 100, 0.001
    end

    test "every mark carries its own ring", %{folder: folder, slug: slug} do
      for n <- 1..4, do: Fixture.put_print!(folder, n)

      marks = Sheet.marks(sheet(slug), 1..4)
      assert length(marks) == 4

      for mark <- marks do
        assert %{viewbox: _, path_length: 100, strokes: [_, _]} = mark.ring
      end

      # No two frames are circled the same way — the whole point of drawing
      # them rather than stamping an ellipse.
      paths = Enum.map(marks, fn m -> hd(m.ring.strokes).d end)
      assert length(Enum.uniq(paths)) == 4
    end
  end

  describe "marks/2 fast path" do
    setup do
      root = Fixture.archive!()
      {folder, slug} = Fixture.golden_roll!(root)
      %{root: root, folder: folder, slug: slug}
    end

    test "a roll with nothing printed is answered without reading the archive",
         %{folder: folder, slug: slug} do
      # If the empty case touched frames.json this would raise, and the whole
      # cost story for the sheet page rests on it not doing so: nearly every
      # roll in the archive has no prints.
      Fixture.write_analysis!(folder, "{ not json at all")

      assert Sheet.marks(sheet(slug), []) == []
      assert Sheet.marks(sheet(slug), MapSet.new()) == []
    end
  end

  describe "marks/2 gate 1: the analysis has to still describe the roll" do
    setup do
      root = Fixture.archive!()
      {folder, slug} = Fixture.golden_roll!(root)
      Fixture.put_print!(folder, 1)
      %{root: root, folder: folder, slug: slug}
    end

    test "a strip added since the last analysis draws nothing",
         %{folder: folder, slug: slug} do
      # Four rolls in the real archive are in exactly this state — one of them
      # describing a single strip for a roll with seven on disk. The sheet
      # still composes to a paper size, so only this gate catches it.
      assert [_] = Sheet.marks(sheet(slug), [1])

      File.write!(Path.join(folder, "003.tiff"), "a strip scanned later")

      assert Sheet.marks(sheet(slug), [1]) == []
    end

    test "a strip removed since the last analysis draws nothing",
         %{folder: folder, slug: slug} do
      File.rm!(Path.join(folder, "002.tiff"))
      assert Sheet.marks(sheet(slug), [1]) == []
    end

    test "prints and previews beside the strips are not mistaken for strips",
         %{folder: folder, slug: slug} do
      File.mkdir_p!(Path.join(folder, "previews"))
      File.write!(Path.join([folder, "previews", "001.webp"]), "preview")

      assert [_] = Sheet.marks(sheet(slug), [1])
    end

    test "a missing analysis draws nothing", %{folder: folder, slug: slug} do
      File.rm!(Path.join(folder, "frames.json"))
      assert Sheet.marks(sheet(slug), [1]) == []
    end

    test "a malformed analysis draws nothing", %{folder: folder, slug: slug} do
      Fixture.write_analysis!(folder, "{ not json at all")
      assert Sheet.marks(sheet(slug), [1]) == []
    end

    test "an analysis missing its strips draws nothing", %{folder: folder, slug: slug} do
      File.write!(Path.join(folder, "frames.json"), Jason.encode!(%{"roll" => "013"}))
      assert Sheet.marks(sheet(slug), [1]) == []
    end

    test "a strip with no dimensions draws nothing", %{folder: folder, slug: slug} do
      Fixture.write_analysis!(folder, [
        %{"file" => "001.tiff", "frames" => []},
        %{"file" => "002.tiff", "frames" => []}
      ])

      assert Sheet.marks(sheet(slug), [1]) == []
    end
  end

  describe "marks/2 gate 2: the layout has to reproduce the sheet" do
    setup do
      root = Fixture.archive!()
      {folder, slug} = Fixture.golden_roll!(root)
      Fixture.put_print!(folder, 1)
      %{root: root, folder: folder, slug: slug}
    end

    test "a sheet of an unexpected size draws nothing", %{root: root, slug: slug} do
      Fixture.put_sheet!(root, slug, 1234, 567)
      assert Sheet.marks(sheet(slug), [1]) == []
    end

    test "a sheet turned the wrong way draws nothing", %{root: root, slug: slug} do
      # The golden roll composes portrait. A landscape sheet of the same paper
      # means it was not assembled the way this code thinks it was.
      Fixture.put_sheet!(root, slug, 3000, 2400)
      assert Sheet.marks(sheet(slug), [1]) == []
    end

    test "a missing sheet draws nothing", %{root: root, slug: slug} do
      File.rm!(Path.join([root, "Contact Sheets", "#{slug}.png"]))
      assert Sheet.marks(sheet(slug), [1]) == []
    end

    test "the paper is proved, not assumed", %{root: root} do
      # An A4 roll: one 656x2152 strip fits A4 portrait at native size, and
      # nothing about the roll says which paper was used. Composing against
      # each in turn is what identifies it.
      folder = Fixture.put_roll!(root, roll: "014", format: "120", frames: "1")
      Fixture.put_strips!(folder, [{656, 2152, [{1, {0, 0, 656, 700}}]}])
      Fixture.put_print!(folder, 1)
      slug = "roll014_2026-01-01_120_bw"
      Fixture.put_sheet!(root, slug, 2480, 3508)

      assert [%{frame: 1}] = Sheet.marks(sheet(slug, "014"), [1])
    end

    test "an unknown roll draws nothing" do
      assert Sheet.marks(sheet("roll999_2026-01-01_120_bw", "999"), [1]) == []
    end
  end

  describe "aspect_ratio/1" do
    setup do
      %{root: Fixture.archive!()}
    end

    test "is the sheet's own proportions", %{root: root} do
      Fixture.put_sheet!(root, "roll001_2026-01-01_120_bw", 3000, 2400)
      assert Sheet.aspect_ratio(%{filename: "roll001_2026-01-01_120_bw.png"}) == 1.25
    end

    test "is nil when the sheet cannot be read" do
      assert Sheet.aspect_ratio(%{filename: "missing.png"}) == nil
      assert Sheet.aspect_ratio(%{}) == nil
    end
  end

  # marks/2 says [] for every failure alike. status/1 is for whoever has to
  # fix the roll: it names the check that refused.
  describe "status/1" do
    setup do
      root = Fixture.archive!()
      {folder, slug} = Fixture.golden_roll!(root)
      %{root: root, folder: folder, slug: slug}
    end

    test "is :ok for a roll whose marks can be drawn", %{slug: slug} do
      assert Sheet.status(sheet(slug)) == :ok
    end

    test "a roll that is not in the catalog has no folder to read" do
      assert Sheet.status(sheet("roll099_2026-01-01_120_bw", "099")) == {:withheld, :no_folder}
    end

    test "a roll with no frames.json has never been analysed", %{folder: folder, slug: slug} do
      File.rm!(Path.join(folder, "frames.json"))
      assert Sheet.status(sheet(slug)) == {:withheld, :not_analysed}
    end

    test "a strip added since the analysis makes it stale", %{folder: folder, slug: slug} do
      File.write!(Path.join(folder, "999.tiff"), "a strip scanned afterwards")
      assert Sheet.status(sheet(slug)) == {:withheld, :stale_analysis}
    end

    test "a sheet no paper size composes to was built some other way",
         %{root: root, slug: slug} do
      Fixture.put_sheet!(root, slug, 1234, 987)
      assert Sheet.status(sheet(slug)) == {:withheld, :size_mismatch}
    end

    test "a sheet that cannot be read is said to be so", %{root: root, slug: slug} do
      File.write!(Path.join([root, "Contact Sheets", "#{slug}.png"]), "not a png")
      assert Sheet.status(sheet(slug)) == {:withheld, :no_sheet}
    end
  end
end
