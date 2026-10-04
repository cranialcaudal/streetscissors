defmodule Web.Scanner.Simulation do
  @moduledoc """
  A pretend scanner, for working on the studio without one attached.

  Only reachable when `:web, :scanner_simulation` is set, which `config/dev.exs`
  and `config/test.exs` do and production never does: on the live site a
  simulated "scan" would write invented strips into the real archive, and
  those could then be published. With the flag off and no scanner connected
  the studio says so and scans nothing.

  The pictures are drawn with ImageMagick: a strip of film base with frames
  on it, at the size a 300 dpi scan of that format would be.
  """

  alias Web.Negatives

  def enabled?, do: Application.get_env(:web, :scanner_simulation, false) == true

  @doc "A stand-in for the bed preview: the glass, with strips laid on it."
  def preview(target, format, color) do
    base = if color == "color", do: "#8a4524", else: "#25211e"

    strips =
      if format == "35mm" do
        for row <- 0..5, do: "rectangle 30,#{40 + row * 110} 570,#{130 + row * 110}"
      else
        for col <- 0..3, do: "rectangle #{40 + col * 135},30 #{155 + col * 135},720"
      end

    magick(
      ["-size", "600x750", "xc:#0d0b09", "-fill", base, "-draw", Enum.join(strips, " ")],
      target
    )
  end

  @doc "A stand-in strip scan: `index` is the strip's place on the roll, from 1."
  def strip(target, index, format, color) do
    base = if color == "color", do: "#9c4927", else: "#1e1b18"
    frame = if color == "color", do: "#4d3423", else: "#423d38"

    {size, frames} =
      if format == "35mm" do
        {"2400x400", for(f <- 0..5, do: "rectangle #{60 + f * 380},50 #{400 + f * 380},350")}
      else
        {"600x2400", for(f <- 0..2, do: "rectangle 40,#{60 + f * 780} 560,#{780 + f * 780}")}
      end

    magick(
      [
        "-size",
        size,
        "-density",
        "300",
        "xc:#{base}",
        "-fill",
        frame,
        "-draw",
        Enum.join(frames, " "),
        "-fill",
        "#d6cebe",
        "-pointsize",
        "36",
        "-annotate",
        "+12+40",
        "strip #{index}"
      ],
      target
    )
  end

  @doc "A stand-in high-resolution frame scan."
  def keeper(target, frame, color) do
    base = if color == "color", do: "#3d2c20", else: "#292522"

    magick(
      [
        "-size",
        "1800x1800",
        "xc:#{base}",
        "-fill",
        "#d9d2c5",
        "-pointsize",
        "48",
        "-gravity",
        "Center",
        "-annotate",
        "+0+0",
        "frame #{frame}"
      ],
      target
    )
  end

  defp magick(args, target) do
    File.mkdir_p!(Path.dirname(target))

    case System.cmd(Negatives.magick_bin(), args ++ [target], stderr_to_stdout: true) do
      {_, 0} -> {:ok, target}
      {output, _} -> {:error, String.trim(output)}
    end
  end
end
