defmodule Web.Negatives.SheetLayout do
  @moduledoc """
  Where each exposure sits on an assembled contact sheet.

  A contact sheet is one flat PNG, so nothing in the image itself says which
  pixels are frame 7. The archive's scanning pipeline knows, though, because it
  assembled the sheet: `negatives --analyze` writes every frame's rectangle
  within its *strip* to `frames.json`, and the GIMP script that composites the
  strips onto paper does so by fixed rules. Replaying those rules turns a
  strip-local rectangle into a sheet-local one.

  This module is that replay, and nothing else — no filesystem, no config, so
  the arithmetic can be tested against known numbers. `Web.Negatives.Sheet`
  reads the files and decides whether the answer is trustworthy.

  ## The rules being replayed

  Transcribed from `film-contact-sheet.scm` (`File > Create > Film Contact
  Sheet`, installed at `~/.config/GIMP/3.2/scripts/`), which the CLI
  `digital-contact-sheet-maker` drives. Its identifiers are kept in the names
  below so the two can be read side by side:

    * `contact-sheet--margin` 75px and `contact-sheet--gap` 24px, at
      `contact-sheet--dpi` 300 — a quarter-inch border, 2mm between strips
    * `contact-sheet--orient` rotates each scan *before* it is measured: a
      `rows` sheet turns portrait strips 270°, a `columns` sheet turns
      landscape strips 90°. `frames.json` regions are unrotated, so they turn
      with their strip — see `orient/2`
    * strips run along one axis in filename order, centred on the other
    * the canvas is always exactly the paper, in whichever orientation needs
      less shrinking (`s-port` vs `s-land`, ties going portrait)
    * strips are placed at native size unless the stack cannot fit, in which
      case every strip shrinks by the same factor

  ## Keeping this honest

  The script lives outside the repository and cannot be vendored into it, so
  this transcription can drift from it. Drift must never place a mark on the
  wrong photograph, so `Web.Negatives.Sheet` gates every answer against the
  archive twice and shows nothing at all when either gate fails. A change to
  the margin, the gap or the paper list therefore makes marks *disappear*,
  which `test/private/negatives_layout_test.exs` reports against the real
  archive.
  """

  @margin 75
  @gap 24

  # Portrait, at 300dpi: 8x10 inch, A4, US Letter — `contact-sheet--paper`.
  # Landscape is not a separate entry; compose/3 tries a paper both ways.
  @papers [{2400, 3000}, {2480, 3508}, {2550, 3300}]

  # What `contact-sheet--scan-files` globs for. Used by the caller to decide
  # which files on disk are supposed to be strips.
  @strip_exts ~w(.jpg .jpeg .png .tif .tiff .bmp .webp)

  @type dims :: {pos_integer(), pos_integer()}
  @type region :: {number(), number(), number(), number()}
  @type layout :: :rows | :columns | :auto
  @type strip :: %{width: pos_integer(), height: pos_integer(), frames: [frame()]}
  @type frame :: %{frame: pos_integer(), region: region()}
  @type placed :: %{frame: pos_integer(), rect: region()}
  @type plan :: %{sheet: dims(), scale: float(), rects: [placed()]}

  @doc "Paper sizes the assembler can produce, portrait."
  @spec papers() :: [dims()]
  def papers, do: @papers

  @doc "File extensions the assembler treats as strip scans."
  @spec strip_exts() :: [String.t()]
  def strip_exts, do: @strip_exts

  @doc """
  Which way the strips run, inferred from the roll folder's path.

  `digital-contact-sheet-maker` does this from the folder name, in this order,
  and so does this: 35mm strips of six stack top to bottom, 120 and 620 stand
  side by side, and anything else is left to the shape of the scans.

  The order matters and the match is a substring, exactly as the shell case
  statement is — which means an archive whose *root* path contained "35mm"
  would call every roll `:rows`. Nothing guards that but this sentence and the
  gates in `Web.Negatives.Sheet`.
  """
  @spec layout_for_path(String.t()) :: layout()
  def layout_for_path(path) do
    path = String.downcase(path)

    cond do
      String.contains?(path, "35mm") -> :rows
      String.contains?(path, "620") or String.contains?(path, "120") -> :columns
      true -> :auto
    end
  end

  @doc """
  Places every frame of every strip onto the sheet.

  Takes the strips in filename order — the order the assembler placed them —
  with their scan dimensions and their frames' strip-local regions, and returns
  the sheet's dimensions, the shrink factor applied, and each frame's rectangle
  in sheet pixels.

  The paper is given portrait; which orientation the sheet ends up in is part
  of the answer, because it is part of what the assembler decides.
  """
  @spec compose([strip()], layout(), dims()) :: {:ok, plan()} | :error
  def compose([], _layout, _paper), do: :error

  def compose(strips, layout, {pw, ph}) do
    oriented = Enum.map(strips, &orient(&1, layout))
    dims = Enum.map(oriented, fn s -> {s.width, s.height} end)
    n = length(dims)

    columns? = columns?(layout, dims, n)

    content_w = run_or_max(dims, n, columns?, :width)
    content_h = run_or_max(dims, n, columns?, :height)

    s_port = fit(pw, ph, content_w, content_h)
    s_land = fit(ph, pw, content_w, content_h)

    # Ties go portrait, because the script's test is a strict `>`.
    {sheet_w, sheet_h} = if s_land > s_port, do: {ph, pw}, else: {pw, ph}
    scale = max(s_port, s_land)

    total_run =
      Enum.reduce(dims, @gap * (n - 1), fn {w, h}, acc ->
        acc + sc(if(columns?, do: w, else: h), scale)
      end)

    start = (if(columns?, do: sheet_w, else: sheet_h) - total_run) / 2

    {rects, _pos} =
      Enum.flat_map_reduce(oriented, start, fn strip, pos ->
        sw = sc(strip.width, scale)
        sh = sc(strip.height, scale)

        {off_x, off_y} =
          if columns?, do: {pos, (sheet_h - sh) / 2}, else: {(sheet_w - sw) / 2, pos}

        placed =
          Enum.map(strip.frames, fn %{frame: number, region: {x, y, w, h}} ->
            %{
              frame: number,
              rect: {off_x + x * scale, off_y + y * scale, w * scale, h * scale}
            }
          end)

        {placed, pos + if(columns?, do: sw, else: sh) + @gap}
      end)

    {:ok,
     %{
       sheet: {sheet_w, sheet_h},
       scale: scale,
       rects: Enum.sort_by(rects, & &1.frame)
     }}
  end

  # `contact-sheet--orient`. A strip turned onto the sheet takes its frames
  # with it, so the regions rotate by the same quarter turn — otherwise every
  # 35mm roll in the archive, which is every roll whose strips stand up on a
  # sheet built in rows, would mark the wrong pixels.
  defp orient(%{width: w, height: h} = strip, :rows) when h > w do
    %{strip | width: h, height: w, frames: turn(strip.frames, 270, w, h)}
  end

  defp orient(%{width: w, height: h} = strip, :columns) when w > h do
    %{strip | width: h, height: w, frames: turn(strip.frames, 90, w, h)}
  end

  defp orient(strip, _layout), do: strip

  # Clockwise, about the image's own box: 90° sends (x,y) to (H-y, x) and 270°
  # sends it to (y, W-x). Width and height swap either way.
  defp turn(frames, degrees, w, h) do
    Enum.map(frames, fn %{region: {x, y, rw, rh}} = frame ->
      region =
        case degrees do
          90 -> {h - (y + rh), x, rh, rw}
          270 -> {y, w - (x + rw), rh, rw}
        end

      %{frame | region: region}
    end)
  end

  # Strips scanned standing up are placed side by side; strips scanned lying
  # down are stacked. A forced layout says so outright; `:auto` goes with the
  # majority of the scans.
  defp columns?(:columns, _dims, _n), do: true
  defp columns?(:rows, _dims, _n), do: false

  defp columns?(:auto, dims, n) do
    2 * Enum.count(dims, fn {w, h} -> h > w end) > n
  end

  # Along the run the strips add up with a gap between them; across it, the
  # widest (or tallest) one sets the content box.
  defp run_or_max(dims, n, columns?, axis) do
    values = Enum.map(dims, fn {w, h} -> if axis == :width, do: w, else: h end)
    along? = if axis == :width, do: columns?, else: not columns?

    if along?, do: Enum.sum(values) + @gap * (n - 1), else: Enum.max(values)
  end

  defp fit(w, h, content_w, content_h) do
    Enum.min([1.0, (w - 2 * @margin) / content_w, (h - 2 * @margin) / content_h])
  end

  # A strip is never scaled away to nothing, and never scaled up: at scale 1
  # this is the identity, which is the case every roll in the archive is in.
  defp sc(value, scale), do: max(1, round(value * scale))
end
