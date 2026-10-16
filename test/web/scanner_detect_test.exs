defmodule Web.Scanner.DetectTest do
  use ExUnit.Case, async: true

  alias Web.Scanner.Detect

  # A scan `width` pixels across at 10 px to the mm, black holder all round,
  # with film of the given colours in the columns given.
  defp glass(width, bands, rows \\ 30) do
    row =
      for x <- 0..(width - 1), into: <<>> do
        case Enum.find(bands, fn {range, _colour} -> x in range end) do
          {_range, colour} when is_function(colour) -> colour.(x)
          {_range, {r, g, b}} -> <<r, g, b>>
          nil -> <<0, 0, 0>>
        end
      end

    :binary.copy(row, rows)
  end

  defp read(width, bands), do: Detect.classify(glass(width, bands), width, 0.1)

  test "35mm colour: a strip under 40 mm wide with the orange mask" do
    assert {:ok, %{format: "35mm", color: "color", width_mm: 25.0}} =
             read(680, [{20..269, {200, 120, 60}}])
  end

  test "120 black and white: a wide strip with no cast" do
    assert {:ok, %{format: "120", color: "bw", width_mm: 56.0, cast: 1.0}} =
             read(680, [{60..619, {120, 120, 120}}])
  end

  test "both slots of a 35mm holder filled are two strips, not one wide one" do
    assert {:ok, %{format: "35mm"}} =
             read(680, [{20..269, {200, 120, 60}}, {390..639, {200, 120, 60}}])
  end

  test "a tinted black and white strip is still black and white" do
    # The bluest in the archive read 0.70 red over blue, evenly.
    assert {:ok, %{color: "bw"}} = read(680, [{20..269, {105, 125, 150}}])
  end

  test "a film whose base is not orange is colour when its colour varies" do
    # Roll 027: pink base, red over blue near 1.1, but orange here and blue there.
    varied = fn x -> if rem(div(x, 40), 2) == 0, do: <<210, 120, 90>>, else: <<120, 130, 215>> end

    assert {:ok, %{color: "color", cast: cast}} = read(680, [{20..269, varied}])
    assert cast < 1.5
  end

  # A scan whose rows differ: `parts` is [{share of the rows, bands}].
  defp glass_in_parts(width, parts, rows \\ 40) do
    for {share, bands} <- parts, into: <<>>, do: glass(width, bands, round(rows * share))
  end

  describe "reversal film, which is black where a negative is clear" do
    # Roll 037: night pictures on slide film, as dark as the holder nearly
    # everywhere, with bare glass past the strip's ends.
    test "a slot of black film is found by the glass at its ends" do
      scan =
        glass_in_parts(680, [
          {0.1, [{20..269, {250, 250, 250}}]},
          {0.8, [{20..269, {6, 4, 4}}]},
          {0.1, [{20..269, {250, 250, 250}}]}
        ])

      assert {:ok, %{format: "35mm", color: "color", slide: true, strips: [strip]}} =
               Detect.classify(scan, 680, 0.1)

      assert strip == %{left_mm: 2.0, width_mm: 25.0}
    end

    test "a negative is not taken for one" do
      assert {:ok, %{slide: false}} = read(680, [{20..269, {200, 120, 60}}])
    end

    test "an empty slot, all glass, is still no film" do
      assert read(680, [{20..269, {250, 250, 250}}]) == :none
    end
  end

  describe "a negative as black as a slide" do
    # A look as the scanner page reads it: a row to the millimetre, a strip
    # 25 mm wide in a 30 mm slot, glass past both ends of the film, and five
    # 36 mm frames with a 2 mm gap after each. `stripes` is [{rows, bands}].
    defp look(stripes), do: for({rows, bands} <- stripes, into: <<>>, do: glass(300, bands, rows))

    defp strip_of(frames, gap) do
      glass = [{20..269, {250, 250, 250}}]

      [{10, []}, {10, glass}] ++
        Enum.flat_map(frames, &[{36, [{20..269, &1}]}, {2, [{20..269, gap}]}]) ++
        [{20, glass}, {10, []}]
    end

    test "is told by its gaps, which are its clearest film" do
      # Roll 071: black and white left with a veil, its clear film at about
      # 20 of 255 and a little warm, its pictures at the scanner's floor.
      scan = look(strip_of(List.duplicate({5, 4, 4}, 5), {21, 18, 16}))

      assert {:ok, %{slide: false, color: "bw", format: "35mm"}} =
               Detect.classify(scan, 300, 0.1, 1.0)
    end

    test "a slide's gaps are its blackest, so it stays a slide" do
      # Night pictures with a lamp here and there, and black between frames.
      lamp = fn x -> if x in 120..150, do: <<90, 70, 50>>, else: <<5, 4, 4>> end
      frames = [{5, 4, 4}, lamp, {6, 5, 5}, {5, 4, 4}, lamp]
      scan = look(strip_of(frames, {2, 2, 2}))

      assert {:ok, %{slide: true, color: "color"}} = Detect.classify(scan, 300, 0.1, 1.0)
    end

    test "film too short to hold two frames is not read for gaps" do
      scan = look(strip_of(List.duplicate({5, 4, 4}, 5), {21, 18, 16}))

      # Rows as tall as a pixel is wide make the film 19 mm long, and dark
      # film with no gaps to read is taken for a slide, as before.
      assert {:ok, %{slide: true}} = Detect.classify(scan, 300, 0.1)
    end
  end

  test "bare glass, an empty holder and a sliver are no film" do
    assert :none = read(680, [{0..679, {250, 250, 250}}])
    assert :none = read(680, [])
    assert :none = read(680, [{20..99, {200, 120, 60}}])
  end

  test "a PPM is read by its header, whatever whitespace divides it" do
    assert {:ok, 2, 1, <<1, 2, 3, 4, 5, 6>>} =
             Detect.parse_ppm("P6\n2 1\n255\n" <> <<1, 2, 3, 4, 5, 6>>)

    assert {:ok, 1, 1, <<9, 9, 9>>} = Detect.parse_ppm("P6 1 1 255 " <> <<9, 9, 9>>)
    assert :error = Detect.parse_ppm("P6\n2 2\n255\n" <> <<1, 2, 3>>)
    assert :error = Detect.parse_ppm("not an image")
  end
end
