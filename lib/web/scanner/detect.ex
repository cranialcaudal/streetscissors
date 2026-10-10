defmodule Web.Scanner.Detect do
  @moduledoc """
  Reads the film's format and whether it is colour off a scan of the glass,
  so the roll does not have to be told.

  The figures below were fitted to the archive on 2026-10-07: 85 strip scans
  in colour from 30 rolls, each labelled by its folder's name.

    * **Format is the width of the film.** 35mm strips measured 22.4 to
      25.7 mm across and 120 strips 53.5 to 58.3 mm, with nothing between,
      so the line is drawn at 40. **620 is 120 film on a thinner spool** and
      measures the same (54.2 to 56.9 mm): it cannot be read off the film,
      and is answered as 120.
    * **Colour is the orange mask.** Red over blue across the film was 0.70
      to 1.09 on black and white and 2.60 or more on C-41, bar one roll
      (027), whose base is pink and reads as low as 1.11. That roll gives
      itself away differently: its colour varies across the strip (a spread
      of 0.13 or more, against at most 0.10 on any black and white strip).
      Either sign makes a strip colour, which sorts all 85 correctly. The
      second margin is narrow and was drawn around one roll, so the answer
      is a proposal the page shows and the author can overrule.

  Black and white strips scanned in grey carry no colour to read, which is
  why the scan looked at here is always in colour.

  The same look says **where each strip is**: every run of film at least
  15 mm across is a strip (`:strips`, left to right, in mm), so a 35mm holder
  with both slots filled gives two strips from one pass.

  ## Reversal film

  A slide is black where nothing was exposed, and black is what the holder
  is. A roll of night pictures on slide film showed almost no "film" at all
  (roll 037: 85% of each slot as dark as the holder) and the look answered
  that the glass was empty. But a strip is shorter than its slot, so the slot
  shows **bare glass past the film's ends**, which the holder's plastic never
  does: a column that is part glass and otherwise dark is a slot with dark
  film in it. Film found that way, or mostly that dark, is taken for reversal
  film and so for colour (`:slide`), since its colour cannot be read off
  black.
  """

  alias Web.Negatives

  # Of 255. Darker is the holder, brighter is bare glass.
  @holder 15
  @glass 235

  @format_line_mm 40.0
  @least_film_mm 15.0

  @cast_line 1.5
  @spread_line 0.12

  # A slot with dark film in it: some of each column is bare glass (past the
  # film's ends), not most of it (an empty slot), and much of the rest is dark.
  @glass_some 0.05
  @glass_most 0.6
  @dark_much 0.3
  # Film this dark overall is reversal film.
  @slide_dark 0.5

  # Enough pixels to judge by, few enough to walk in the BEAM. Only the
  # columns have to be fine (a strip's edges are cut from them), so the
  # height is squashed.
  @sample_width 536
  @sample_height 240

  @doc """
  What is on the glass in the scan at `path`, made at `dpi`:
  `{:ok, %{format: "35mm" | "120", color: "color" | "bw", width_mm:, cast:,
  spread:, strips: [%{left_mm:, width_mm:}]}}`, or `:none` when no film is
  found or the scan cannot be read.
  """
  def read(path, dpi) do
    args = [
      path <> "[0]",
      "-alpha",
      "off",
      "-resize",
      "#{@sample_width}x#{@sample_height}!",
      "-depth",
      "8",
      "ppm:-"
    ]

    with {ppm, 0} <- System.cmd(Negatives.magick_bin(), args, stderr_to_stdout: false),
         {:ok, width, _height, pixels} <- parse_ppm(ppm),
         {full_width, _} <- full_width(path) do
      classify(pixels, width, 25.4 * full_width / (dpi * width))
    else
      _ -> :none
    end
  rescue
    _ -> :none
  end

  defp full_width(path) do
    case System.cmd(Negatives.magick_bin(), ["identify", "-format", "%w", path <> "[0]"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> Integer.parse(String.trim(output))
      _ -> :error
    end
  end

  @doc "The width, height and pixel bytes of a binary PPM (`P6`, 8 bits)."
  def parse_ppm(<<"P6", rest::binary>>) do
    with [width, height, "255", pixels] <- header(rest, 3, []),
         {width, ""} <- Integer.parse(width),
         {height, ""} <- Integer.parse(height),
         true <- byte_size(pixels) >= width * height * 3 do
      {:ok, width, height, binary_part(pixels, 0, width * height * 3)}
    else
      _ -> :error
    end
  end

  def parse_ppm(_other), do: :error

  # The header's fields are split by any whitespace; one byte of it ends the last.
  defp header(rest, 0, fields), do: Enum.reverse([rest | fields])

  defp header(rest, left, fields) do
    case Regex.run(~r/\A\s*(\d+)\s/, rest, return: :index) do
      [{0, taken}, {start, length}] ->
        field = binary_part(rest, start, length)
        header(binary_part(rest, taken, byte_size(rest) - taken), left - 1, [field | fields])

      _ ->
        []
    end
  end

  @doc """
  The same answer from pixels already in hand: `pixels` is rows of RGB bytes
  `width` across, and each pixel is `mm_per_pixel` wide.
  """
  def classify(pixels, width, mm_per_pixel) when width > 0 do
    rows = for <<row::binary-size(width * 3) <- pixels>>, do: row

    runs =
      rows
      |> film_runs(width)
      |> Enum.filter(fn {first, last} -> (last - first + 1) * mm_per_pixel >= @least_film_mm end)

    case Enum.max_by(runs, fn {first, last} -> last - first end, fn -> nil end) do
      nil ->
        :none

      {first, last} ->
        width_mm = (last - first + 1) * mm_per_pixel
        {cast, spread} = colour(rows, first, last)
        slide? = dark_share(rows, first, last) >= @slide_dark

        {:ok,
         %{
           format: if(width_mm < @format_line_mm, do: "35mm", else: "120"),
           color:
             if(slide? or cast >= @cast_line or spread >= @spread_line, do: "color", else: "bw"),
           slide: slide?,
           width_mm: Float.round(width_mm, 1),
           cast: Float.round(cast, 2),
           spread: Float.round(spread, 3),
           strips:
             for {first, last} <- runs do
               %{
                 left_mm: Float.round(first * mm_per_pixel, 2),
                 width_mm: Float.round((last - first + 1) * mm_per_pixel, 2)
               }
             end
         }}
    end
  end

  def classify(_pixels, _width, _mm_per_pixel), do: :none

  defp light(r, g, b), do: div(r * 299 + g * 587 + b * 114, 1000)

  defp film?(r, g, b) do
    light = light(r, g, b)
    light > @holder and light < @glass
  end

  # Every run of columns that are mostly film, left to right: one per strip.
  # A 35mm holder with both slots filled is two runs, not one wide one.
  defp film_runs([], _width), do: []

  defp film_runs(rows, width) do
    none = :erlang.make_tuple(width, 0)

    {film, dark, glass} =
      Enum.reduce(rows, {none, none, none}, fn row, counts ->
        row
        |> columns()
        |> Enum.reduce(counts, fn {index, r, g, b}, {film, dark, glass} ->
          light = light(r, g, b)

          cond do
            light <= @holder -> {film, bump(dark, index), glass}
            light >= @glass -> {film, dark, bump(glass, index)}
            true -> {bump(film, index), dark, glass}
          end
        end)
      end)

    count = length(rows)

    film? = fn x ->
      elem(film, x) > count * 0.3 or
        (elem(glass, x) >= count * @glass_some and elem(glass, x) <= count * @glass_most and
           elem(dark, x) >= count * @dark_much)
    end

    0..(width - 1)
    |> Enum.chunk_by(film?)
    |> Enum.filter(fn [first | _] -> film?.(first) end)
    |> Enum.map(&{List.first(&1), List.last(&1)})
  end

  defp bump(counts, index), do: put_elem(counts, index, elem(counts, index) + 1)

  # How much of a strip, glass apart, is as dark as the holder.
  defp dark_share(rows, first, last) do
    {dark, all} =
      Enum.reduce(rows, {0, 0}, fn row, acc ->
        row
        |> columns()
        |> Enum.reduce(acc, fn {index, r, g, b}, {dark, all} ->
          light = light(r, g, b)

          cond do
            index < first or index > last or light >= @glass -> {dark, all}
            light <= @holder -> {dark + 1, all + 1}
            true -> {dark, all + 1}
          end
        end)
      end)

    if all == 0, do: 0.0, else: dark / all
  end

  defp columns(row) do
    for {<<r, g, b>>, index} <- Enum.with_index(for(<<pixel::binary-size(3) <- row>>, do: pixel)) do
      {index, r, g, b}
    end
  end

  # Red over blue across the strip's film, and how far red-less-blue wanders.
  defp colour(rows, first, last) do
    values =
      for row <- rows,
          {index, r, g, b} <- columns(row),
          index >= first and index <= last,
          film?(r, g, b) do
        {r, b, (r - b) / (r + g + b)}
      end

    case values do
      [] ->
        {1.0, 0.0}

      values ->
        count = length(values)
        red = values |> Enum.map(&elem(&1, 0)) |> Enum.sum()
        blue = values |> Enum.map(&elem(&1, 1)) |> Enum.sum()
        mean = (values |> Enum.map(&elem(&1, 2)) |> Enum.sum()) / count

        variance =
          (values |> Enum.map(&((elem(&1, 2) - mean) ** 2)) |> Enum.sum()) / count

        {red / max(blue, 1), :math.sqrt(variance)}
    end
  end
end
