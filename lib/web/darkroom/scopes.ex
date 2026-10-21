defmodule Web.Darkroom.Scopes do
  @moduledoc """
  A histogram and an RGB parade of the print editor's preview, drawn beside
  the sliders so a clipped highlight or a colour cast is seen, not guessed.

  Read from the preview JPEG LightCraft just drew, shrunk by ImageMagick to
  #{256}x#{96} `rgb:` bytes (the same way `Web.Darkroom.Stats` reads a
  print), then binned here: a few milliseconds a preview. These are
  **display-encoded** values, what the screen shows, not scene light; the
  LightCraft fork's `scopes.compute` (docs/colour/contracts.md, W4) is meant
  to replace them.

  `read/1` gives `%{histogram: %{r, g, b, l}, parade: %{r, g, b}}`:

  * **histogram**: 64 bins per channel, each as a share of the tallest bin,
    so 1.0 is the peak (`l` is luma, Rec. 709 weights);
  * **parade**: for each of 64 columns across the picture, per channel,
    `{low, mid, high}` (the 5th, 50th and 95th percentile, 0 to 1).
  """

  alias Web.Negatives

  @width 256
  @height 96
  @bins 64
  @columns 64

  def read(path) do
    case System.cmd(
           Negatives.magick_bin(),
           [
             path <> "[0]",
             "-resize",
             "#{@width}x#{@height}!",
             "-colorspace",
             "sRGB",
             "-depth",
             "8",
             "rgb:-"
           ],
           stderr_to_stdout: false
         ) do
      {bytes, 0} when byte_size(bytes) == @width * @height * 3 -> {:ok, from_bytes(bytes)}
      _ -> :error
    end
  catch
    :exit, _ -> :error
  end

  @doc false
  def from_bytes(bytes) do
    pixels =
      for <<r, g, b <- bytes>>, do: {r, g, b, round(0.2126 * r + 0.7152 * g + 0.0722 * b)}

    %{histogram: histogram(pixels), parade: parade(pixels)}
  end

  defp histogram(pixels) do
    counts =
      Enum.reduce(pixels, %{r: zeros(), g: zeros(), b: zeros(), l: zeros()}, fn {r, g, b, l},
                                                                                acc ->
        %{
          r: bump(acc.r, bin(r)),
          g: bump(acc.g, bin(g)),
          b: bump(acc.b, bin(b)),
          l: bump(acc.l, bin(l))
        }
      end)

    peak = counts |> Map.values() |> Enum.flat_map(&Tuple.to_list/1) |> Enum.max() |> max(1)

    Map.new(counts, fn {channel, row} -> {channel, Enum.map(Tuple.to_list(row), &(&1 / peak))} end)
  end

  defp parade(pixels) do
    width = div(length(pixels), @height)
    per_column = div(width, @columns)

    columns =
      pixels
      |> Enum.with_index()
      |> Enum.group_by(
        fn {_pixel, i} -> min(div(rem(i, width), per_column), @columns - 1) end,
        &elem(&1, 0)
      )
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    Map.new([r: 0, g: 1, b: 2], fn {channel, index} ->
      {channel,
       Enum.map(columns, fn column ->
         values = column |> Enum.map(&elem(&1, index)) |> Enum.sort()
         {pct(values, 0.05), pct(values, 0.5), pct(values, 0.95)}
       end)}
    end)
  end

  defp zeros, do: Tuple.duplicate(0, @bins)
  defp bin(value), do: min(div(value * @bins, 256), @bins - 1)
  defp bump(row, i), do: put_elem(row, i, elem(row, i) + 1)

  defp pct(sorted, q) do
    sorted |> Enum.at(min(round(q * (length(sorted) - 1)), length(sorted) - 1)) |> Kernel./(255)
  end
end
