defmodule Web.NegativesSheetLayoutTest do
  use ExUnit.Case, async: true

  alias Web.Negatives.SheetLayout

  # Pure arithmetic, so the numbers here are worked by hand from the rules in
  # film-contact-sheet.scm rather than read off a fixture. Invented rolls
  # throughout — the same sums run against the real archive in test/private/.

  defp strip(w, h, frames), do: %{width: w, height: h, frames: frames}
  defp frame(n, region), do: %{frame: n, region: region}
  defp eightby10, do: {2400, 3000}

  describe "layout_for_path/1" do
    test "35mm strips of six stack top to bottom" do
      assert SheetLayout.layout_for_path("/archive/35mm Film/roll014_2026-01-01_35mm_bw") ==
               :rows
    end

    test "120 and 620 stand side by side" do
      assert SheetLayout.layout_for_path("/archive/120 Film/roll001") == :columns
      assert SheetLayout.layout_for_path("/archive/620 Film/roll019") == :columns
    end

    test "anything else is left to the shape of the scans" do
      assert SheetLayout.layout_for_path("/archive/110 Film/roll031") == :auto
      assert SheetLayout.layout_for_path("/archive/Other/roll032") == :auto
    end

    test "the case statement is ordered, so 35mm wins over a 120 later in the path" do
      assert SheetLayout.layout_for_path("/archive/35mm Film/roll120") == :rows
    end
  end

  describe "compose/3 placement" do
    test "two 120 strips centre on an 8x10 sheet at native size" do
      # Content is 656 + 24 + 656 = 1336 wide by 2152 tall. Both orientations
      # fit without shrinking, so the scale is 1 and the tie sends the sheet
      # portrait. The run is centred: (2400 - 1336) / 2 = 532, and each strip
      # is centred across it: (3000 - 2152) / 2 = 424.
      strips = [
        strip(656, 2152, [frame(1, {0, 0, 656, 700})]),
        strip(656, 2152, [frame(2, {0, 0, 656, 700})])
      ]

      assert {:ok, plan} = SheetLayout.compose(strips, :columns, eightby10())
      assert plan.sheet == {2400, 3000}
      assert plan.scale == 1.0

      assert [%{frame: 1, rect: first}, %{frame: 2, rect: second}] = plan.rects
      assert first == {532.0, 424.0, 656, 700}
      # The next strip starts one strip-width and one gap along.
      assert second == {532.0 + 656 + 24, 424.0, 656, 700}
    end

    test "a wide stack turns the sheet landscape" do
      # Four strips side by side need 2672px, which does not fit 2400 minus
      # margins but does fit 3000. Landscape wins outright, no tie.
      strips = for n <- 1..4, do: strip(656, 2152, [frame(n, {0, 0, 656, 700})])

      assert {:ok, plan} = SheetLayout.compose(strips, :columns, eightby10())
      assert plan.sheet == {3000, 2400}
      assert plan.scale == 1.0
    end

    test "a stack too big for either orientation shrinks by one uniform factor" do
      strips = for n <- 1..4, do: strip(2000, 2152, [frame(n, {0, 0, 2000, 700})])

      assert {:ok, plan} = SheetLayout.compose(strips, :columns, eightby10())
      assert plan.scale < 1.0
      # Every strip shrinks by the same factor, so the run still fits the paper.
      {sheet_w, _} = plan.sheet
      assert Enum.all?(plan.rects, fn %{rect: {x, _, w, _}} -> x + w <= sheet_w end)
    end

    test "35mm strips stack, centred across the sheet" do
      # Six 2687x288 strips lying down: the run is 6*288 + 5*24 = 1848 tall,
      # centred on a 2400 edge at 276, and each strip is centred across 3000.
      strips = for n <- 1..6, do: strip(2687, 288, [frame(n, {0, 0, 440, 288})])

      assert {:ok, plan} = SheetLayout.compose(strips, :rows, eightby10())
      assert plan.sheet == {3000, 2400}

      assert [%{frame: 1, rect: {x, y, _, _}} | _] = plan.rects
      assert x == (3000 - 2687) / 2
      assert y == 276.0
    end

    test "an empty roll places nothing" do
      assert SheetLayout.compose([], :columns, eightby10()) == :error
    end
  end

  describe "compose/3 rotation" do
    # A strip is turned onto the sheet before it is measured, so its frames
    # have to turn with it. Getting this wrong puts every 35mm mark on the
    # wrong photograph while still producing a sheet of the right size — which
    # is exactly why it is asserted on its own here.

    test "a portrait strip on a rows sheet turns 270 degrees" do
      # 288x2687 standing up becomes 2687x288 lying down. A region 100px down
      # the standing strip is 100px along the lying one, and the region's own
      # width and height swap.
      strips = [strip(288, 2687, [frame(1, {0, 100, 288, 440})])]

      assert {:ok, plan} = SheetLayout.compose(strips, :rows, eightby10())
      assert [%{rect: {x, y, w, h}}] = plan.rects

      # Placement of a single strip: centred both ways.
      {sheet_w, sheet_h} = plan.sheet
      assert x == (sheet_w - 2687) / 2 + 100
      assert y == (sheet_h - 288) / 2 + (288 - (0 + 288))
      assert {w, h} == {440, 288}
    end

    test "a landscape strip on a columns sheet turns 90 degrees" do
      # 2687x288 lying down becomes 288x2687 standing up. The region's x
      # measures down from the top after the turn; its far edge measures from
      # the bottom before it.
      strips = [strip(2687, 288, [frame(1, {100, 0, 440, 288})])]

      assert {:ok, plan} = SheetLayout.compose(strips, :columns, eightby10())
      assert [%{rect: {x, y, w, h}}] = plan.rects

      {sheet_w, sheet_h} = plan.sheet
      assert x == (sheet_w - 288) / 2 + (288 - (0 + 288))
      assert y == (sheet_h - 2687) / 2 + 100
      assert {w, h} == {288, 440}
    end

    test "a strip already the right way round is left alone" do
      strips = [strip(2687, 288, [frame(1, {100, 0, 440, 288})])]

      assert {:ok, plan} = SheetLayout.compose(strips, :rows, eightby10())
      assert [%{rect: {_, _, w, h}}] = plan.rects
      assert {w, h} == {440, 288}
    end
  end

  describe "compose/3 with :auto" do
    test "a majority of standing strips are placed side by side" do
      strips = [
        strip(656, 2152, [frame(1, {0, 0, 656, 700})]),
        strip(656, 2152, [frame(2, {0, 0, 656, 700})]),
        strip(2152, 656, [frame(3, {0, 0, 700, 656})])
      ]

      assert {:ok, plan} = SheetLayout.compose(strips, :auto, eightby10())
      # Placed as columns: the frames advance along x, not y.
      assert [%{rect: {x1, y1, _, _}}, %{rect: {x2, y2, _, _}} | _] = plan.rects
      assert x2 > x1
      assert y1 == y2
    end

    test "a majority of lying strips are stacked, and nothing is rotated" do
      strips = [
        strip(2152, 656, [frame(1, {0, 0, 700, 656})]),
        strip(2152, 656, [frame(2, {0, 0, 700, 656})]),
        strip(656, 2152, [frame(3, {0, 0, 656, 700})])
      ]

      assert {:ok, plan} = SheetLayout.compose(strips, :auto, eightby10())
      assert [%{rect: {_, y1, w1, h1}}, %{rect: {_, y2, _, _}} | _] = plan.rects
      assert y2 > y1
      # :auto never calls contact-sheet--orient, so the frames keep their shape.
      # This stack is taller than the paper, so everything shrinks by one
      # factor — what matters is that a landscape frame stayed landscape.
      assert w1 > h1
    end
  end

  describe "papers/0 and strip_exts/0" do
    test "the three paper sizes the assembler offers, portrait" do
      assert SheetLayout.papers() == [{2400, 3000}, {2480, 3508}, {2550, 3300}]
    end

    test "A4 and Letter compose too" do
      strips = [strip(656, 2152, [frame(1, {0, 0, 656, 700})])]

      for paper <- SheetLayout.papers() do
        assert {:ok, %{sheet: sheet}} = SheetLayout.compose(strips, :columns, paper)
        assert sheet == paper or sheet == {elem(paper, 1), elem(paper, 0)}
      end
    end

    test "tiff is a strip extension, webp is, and m3u8 is not" do
      assert ".tiff" in SheetLayout.strip_exts()
      assert ".webp" in SheetLayout.strip_exts()
      refute ".m3u8" in SheetLayout.strip_exts()
    end
  end
end
