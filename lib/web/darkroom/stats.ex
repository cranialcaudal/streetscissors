defmodule Web.Darkroom.Stats do
  @moduledoc """
  What a print looks like, in a few numbers: the colour cast of its near
  neutral parts, how much of it is near neutral (which says how far that cast
  can be trusted), and its tone and colour in Oklab (Ottosson's perceptual
  space: lightness and two colour axes) for the taste model's features
  (`Web.Darkroom.Taste`).

  Read from a 64x64 copy ImageMagick makes (`rgb:` bytes), so a print of any
  size costs a few milliseconds, and everything after is arithmetic here.

  **The cast** is the mean of `log10(R/G)` and `log10(B/G)` (linear light)
  over pixels that are neither near black nor near white and whose channels
  lie within a quarter of one another: the grey-world estimate, taken over
  what could be grey. A print with few such pixels (a red wall, a sunset)
  says little about its cast, and `neutral` is small.
  """

  alias Web.Negatives

  @side 64

  def read(path) do
    case System.cmd(
           Negatives.magick_bin(),
           [
             path <> "[0]",
             "-resize",
             "#{@side}x#{@side}!",
             "-colorspace",
             "sRGB",
             "-depth",
             "8",
             "rgb:-"
           ],
           stderr_to_stdout: false
         ) do
      {bytes, 0} when byte_size(bytes) == @side * @side * 3 -> {:ok, from_bytes(bytes)}
      _ -> :error
    end
  end

  @doc false
  def from_bytes(bytes) do
    pixels = for <<r, g, b <- bytes>>, do: {lin(r), lin(g), lin(b)}
    n = length(pixels)

    neutral =
      for {r, g, b} = p <- pixels,
          y = 0.2126 * r + 0.7152 * g + 0.0722 * b,
          y > 0.02 and y < 0.85,
          lo = Enum.min([r, g, b]),
          lo > 0,
          Enum.max([r, g, b]) / lo < 1.25,
          do: p

    {rg, bg} =
      case neutral do
        [] ->
          {0.0, 0.0}

        some ->
          {mean(some, &:math.log10(elem(&1, 0) / elem(&1, 1))),
           mean(some, &:math.log10(elem(&1, 2) / elem(&1, 1)))}
      end

    labs = Enum.map(pixels, &oklab/1)
    ls = labs |> Enum.map(&elem(&1, 0)) |> Enum.sort()

    %{
      cast: {rg, bg},
      neutral: length(neutral) / n,
      l: mean(labs, &elem(&1, 0)),
      a: mean(labs, &elem(&1, 1)),
      b: mean(labs, &elem(&1, 2)),
      chroma: mean(labs, fn {_, a, b} -> :math.sqrt(a * a + b * b) end),
      l05: pct(ls, 0.05),
      l50: pct(ls, 0.5),
      l95: pct(ls, 0.95)
    }
  end

  @doc "The numbers the taste model reads, in a fixed order."
  def features(s) do
    {rg, bg} = s.cast
    [s.l, s.a, s.b, s.chroma, s.l05, s.l50, s.l95, rg, bg, s.neutral]
  end

  def feature_names, do: ~w(lightness a b chroma shadows midtones highlights rg bg neutral)

  defp mean(list, f), do: Enum.sum(Enum.map(list, f)) / max(length(list), 1)

  defp pct(sorted, q),
    do: Enum.at(sorted, min(round(q * (length(sorted) - 1)), length(sorted) - 1))

  defp lin(c) do
    c = c / 255
    if c <= 0.04045, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
  end

  # Oklab from linear sRGB, as Ottosson publishes it.
  defp oklab({r, g, b}) do
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    {l, m, s} = {cbrt(l), cbrt(m), cbrt(s)}

    {0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s}
  end

  defp cbrt(x) when x <= 0, do: 0.0
  defp cbrt(x), do: :math.pow(x, 1 / 3)
end
