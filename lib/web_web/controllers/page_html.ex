defmodule WebWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use WebWeb, :html

  embed_templates "page_html/*"

  @doc """
  The site's beta number, shown beside the homepage's wordmark. 1.0 was the
  deploy of 2026-10-11, the first with the whole revamp live; the second
  number goes up with each deploy that changes what a visitor sees.
  """
  def beta, do: "1.1"

  # The splash is set in the block game's own lettering, which is a bitmap:
  # each letter a few pixels on a grid seven high. They are drawn here as
  # squares, so no font is loaded for eight characters. Rows read top to
  # bottom; a letter is as wide as its rows.
  @glyphs %{
    "B" => ~w(1111. 1...1 1111. 1...1 1...1 1...1 1111.),
    "e" => ~w(..... ..... .111. 1...1 11111 1.... .1111),
    "t" => ~w(.1. .1. 111 .1. .1. .1. ..1),
    "a" => ~w(..... ..... .111. ....1 .1111 1...1 .1111),
    " " => ~w(... ... ... ... ... ... ...),
    "i" => ~w(1 . 1 1 1 1 1),
    "I" => ~w(111 .1. .1. .1. .1. .1. 111),
    "'" => ~w(1 1 . . . . .),
    "m" => ~w(..... ..... 11.1. 1.1.1 1.1.1 1...1 1...1),
    "n" => ~w(..... ..... 1111. 1...1 1...1 1...1 1...1),
    "b" => ~w(1.... 1.... 1.11. 11..1 1...1 1...1 1111.),
    "!" => ~w(1 1 1 1 1 . 1),
    "." => ~w(. . . . . . 1),
    "0" => ~w(.111. 1...1 1..11 1.1.1 11..1 1...1 .111.),
    "1" => ~w(..1.. .11.. ..1.. ..1.. ..1.. ..1.. 11111),
    "2" => ~w(.111. 1...1 ....1 ..11. .1... 1...1 11111),
    "3" => ~w(.111. 1...1 ....1 ..11. ....1 1...1 .111.),
    "4" => ~w(...11 ..1.1 .1..1 1...1 11111 ....1 ....1),
    "5" => ~w(11111 1.... 1111. ....1 ....1 1...1 .111.),
    "6" => ~w(..11. .1... 1.... 1111. 1...1 1...1 .111.),
    "7" => ~w(11111 1...1 ....1 ...1. ..1.. ..1.. ..1..),
    "8" => ~w(.111. 1...1 1...1 .111. 1...1 1...1 .111.),
    "9" => ~w(.111. 1...1 1...1 .1111 ....1 ...1. .11..)
  }

  @doc """
  The beta splash: `text` in pixels, with the dark copy one pixel down and to
  the right that the game drew under all its lettering. Characters it has no
  letter for are left out.
  """
  attr :text, :string, required: true
  attr :title, :string, default: nil

  def beta_splash(assigns) do
    {pixels, width} =
      assigns.text
      |> String.graphemes()
      |> Enum.reduce({[], 0}, fn char, {pixels, x} ->
        case @glyphs[char] do
          nil ->
            {pixels, x}

          rows ->
            lit =
              for {row, y} <- Enum.with_index(rows),
                  {"1", dx} <- Enum.with_index(String.graphemes(row)),
                  do: {x + dx, y}

            {pixels ++ lit, x + String.length(hd(rows)) + 1}
        end
      end)

    assigns = assign(assigns, pixels: pixels, width: width, path: path(pixels))

    ~H"""
    <svg
      class="site-beta"
      viewBox={"0 0 #{@width} 8"}
      role="img"
      aria-label={@text}
    >
      <title :if={@title}>{@title}</title>
      <path class="site-beta-shadow" transform="translate(1 1)" d={@path} />
      <path class="site-beta-face" d={@path} />
    </svg>
    """
  end

  # One rectangle for each unbroken run of pixels along a row. Drawn a square
  # at a time, turned and scaled, the squares showed hairline gaps between
  # them and the lettering looked torn; a run has no joins to show, and the
  # stroke in the stylesheet closes the joins between rows.
  defp path(pixels) do
    pixels
    |> Enum.group_by(fn {_x, y} -> y end, fn {x, _y} -> x end)
    |> Enum.flat_map(fn {y, xs} ->
      xs
      |> Enum.sort()
      |> Enum.chunk_while(
        nil,
        fn
          x, nil -> {:cont, {x, x}}
          x, {from, to} when x == to + 1 -> {:cont, {from, x}}
          x, run -> {:cont, run, {x, x}}
        end,
        fn
          nil -> {:cont, nil}
          run -> {:cont, run, nil}
        end
      )
      |> Enum.map(fn {from, to} -> "M#{from} #{y}h#{to - from + 1}v1h-#{to - from + 1}z" end)
    end)
    |> Enum.join(" ")
  end
end
