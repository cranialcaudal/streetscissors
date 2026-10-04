defmodule Web.Negatives.Sheet do
  @moduledoc """
  Which frames of a contact sheet have been printed, and where they sit on it.

  `Web.Negatives.SheetLayout` does the arithmetic; this decides whether the
  archive can be trusted to answer at all. A mark in the wrong place is much
  worse than no mark: it invites someone to click one photograph and shows them
  another, on a page whose whole claim is that a frame can be traced back to the
  sheet it was cut from. So every failure here returns `[]`, and the page falls
  back to the plain sheet it has always shown.

  ## The two gates

  1. **The analysis has to still describe the roll.** `frames.json` is written
     by `negatives --analyze` and goes stale the moment a strip is added or
     rescanned without re-running it. Four rolls in the archive were in exactly
     that state when this was written — one describing a single strip for a
     roll with seven on disk. So the strip scans on disk must match
     `strips[].file` exactly, in order.

  2. **The layout has to reproduce the sheet.** The assembler always fills the
     paper exactly, so trying each paper size and keeping the one whose
     composed dimensions match the real PNG proves the paper rather than
     assuming it. No match means the sheet was not built the way this code
     thinks sheets are built — a hand-assembled roll, a `--layout` override, a
     changed script — and nothing is drawn.

  Gate 1 catches what gate 2 cannot: a stale analysis still composes to a
  paper-sized sheet, because the sheet is always paper-sized whatever is on it.
  """

  alias Web.Negatives
  alias Web.Negatives.GreasePencil
  alias Web.Negatives.SheetLayout

  # How far outside the frame the pencil is allowed to wander, as a fraction of
  # the frame's short side. This is also the click target's overhang.
  @pad_ratio 0.1

  @type mark :: %{
          frame: pos_integer(),
          left: float(),
          top: float(),
          width: float(),
          height: float(),
          ring: GreasePencil.ring()
        }

  @doc """
  The sheet image's pixel dimensions, read from the PNG header.

  Twenty-four bytes off the front of the file: the signature, then the IHDR
  chunk, whose first two fields are the width and height. Cheaper than asking
  ImageMagick, and it runs on every sheet render. Anything that is not a PNG is
  refused rather than guessed at — the assembler only ever writes PNG, so a
  sheet in another format is a sheet this code did not build.
  """
  @spec dimensions(Path.t()) :: {:ok, {pos_integer(), pos_integer()}} | :error
  def dimensions(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 24)) do
      {:ok, <<137, "PNG", 13, 10, 26, 10, _len::32, "IHDR", width::32, height::32>>}
      when width > 0 and height > 0 ->
        {:ok, {width, height}}

      _ ->
        :error
    end
  end

  @doc """
  The sheet's width over its height, for a box that has to match its shape.

  `nil` when the image cannot be read, which is the caller's cue to lay the
  sheet out the way it did before any of this existed.
  """
  @spec aspect_ratio(map()) :: float() | nil
  def aspect_ratio(%{filename: filename}) do
    with {:ok, path} <- Negatives.image_path(filename),
         {:ok, {w, h}} <- dimensions(path) do
      w / h
    else
      _ -> nil
    end
  end

  def aspect_ratio(_sheet), do: nil

  @doc """
  How many exposures a roll actually holds.

  `catalog.csv`'s `frames` column counts *strip scans*, not frames — roll 13
  reads 4 when it holds twelve exposures, and every 35mm roll is out by six.
  `frames.json` has the real number, so this counts what the analysis
  described.

  Returns `nil` when the roll has no analysis or the analysis has gone stale,
  because the honest answer there is "unknown": the strip count is wrong and a
  stale analysis's frame count is wronger. The caller shows a question mark,
  which is also what a roll with no catalog entry has always shown.

  This reads a file per roll, so it belongs to the full index — which renders
  on request — and not to the rail beside the sheet, which renders on every
  visit and shows only what `list_contact_sheets/2` already knows.
  """
  @spec frame_count(map()) :: pos_integer() | nil
  def frame_count(%{roll: roll}) do
    with {:ok, dir} <- Negatives.roll_dir(roll),
         {:ok, strips} <- analysis(dir),
         :ok <- manifest_matches?(dir, strips) do
      case Enum.reduce(strips, 0, fn strip, acc -> acc + length(strip.frames) end) do
        0 -> nil
        count -> count
      end
    else
      _ -> nil
    end
  end

  def frame_count(_sheet), do: nil

  @doc """
  Marks for the frames of `sheet` that appear in `available`.

  Positions are fractions of the sheet, 0..1, so the caller can place them over
  the image at any rendered size. Each carries its own ring — see
  `Web.Negatives.GreasePencil`.

  An empty `available` returns `[]` without touching the filesystem, which is
  the common case by a wide margin: a roll with no prints is a roll with
  nothing to circle, and the archive is nearly all such rolls.
  """
  @spec marks(map(), Enumerable.t()) :: [mark()]
  def marks(sheet, available) do
    wanted = MapSet.new(available)

    if MapSet.size(wanted) == 0 do
      []
    else
      place(sheet, wanted)
    end
  end

  defp place(%{roll: roll, slug: slug, filename: filename}, wanted) do
    with {:ok, dir} <- Negatives.roll_dir(roll),
         {:ok, strips} <- analysis(dir),
         :ok <- manifest_matches?(dir, strips),
         {:ok, path} <- Negatives.image_path(filename),
         {:ok, {sheet_w, sheet_h} = dims} <- dimensions(path),
         {:ok, plan} <- compose_matching(strips, dir, dims) do
      plan.rects
      |> Enum.filter(&MapSet.member?(wanted, &1.frame))
      |> Enum.map(&mark(&1, slug, sheet_w, sheet_h))
    else
      _ -> []
    end
  end

  defp place(_sheet, _wanted), do: []

  defp mark(%{frame: number, rect: {x, y, w, h}}, slug, sheet_w, sheet_h) do
    pad = @pad_ratio * min(w, h)

    %{
      frame: number,
      left: (x - pad) / sheet_w * 100,
      top: (y - pad) / sheet_h * 100,
      width: (w + 2 * pad) / sheet_w * 100,
      height: (h + 2 * pad) / sheet_h * 100,
      ring: GreasePencil.ring({slug, number}, w, h, pad)
    }
  end

  @doc """
  Whether a sheet's marks can be drawn, and if not, which check refused.

  `marks/2` answers `[]` for every failure alike, which is right for the page
  and useless for whoever has to fix the roll. This names the reason, in the
  order the gates run:

    * `:no_folder` — the roll is not in `catalog.csv`, or its folder is gone
    * `:not_analysed` — no readable `frames.json` in the folder
    * `:stale_analysis` — `frames.json` describes other strips than are on
      disk (gate 1)
    * `:no_sheet` — the sheet's image could not be read
    * `:size_mismatch` — no paper size composes to the sheet's dimensions
      (gate 2)
  """
  @spec status(map()) ::
          :ok
          | {:withheld, :no_folder | :not_analysed | :stale_analysis | :no_sheet | :size_mismatch}
  def status(%{roll: roll, filename: filename}) do
    with {:no_folder, {:ok, dir}} <- {:no_folder, Negatives.roll_dir(roll)},
         {:not_analysed, {:ok, strips}} <- {:not_analysed, analysis(dir)},
         {:stale_analysis, :ok} <- {:stale_analysis, manifest_matches?(dir, strips)},
         {:no_sheet, {:ok, path}} <- {:no_sheet, Negatives.image_path(filename)},
         {:no_sheet, {:ok, dims}} <- {:no_sheet, dimensions(path)},
         {:size_mismatch, {:ok, _plan}} <- {:size_mismatch, compose_matching(strips, dir, dims)} do
      :ok
    else
      {reason, _} -> {:withheld, reason}
    end
  end

  @doc """
  Reads frames.json for a roll directory.
  """
  def read_analysis(dir), do: analysis(dir)

  @doc """
  Gate 1. Verifies that strip scans on disk match frames.json in exact filename order.
  """
  def verify_gate_1(dir) do
    with {:ok, strips} <- analysis(dir),
         :ok <- manifest_matches?(dir, strips) do
      {:ok, strips}
    else
      _ -> {:error, :gate_1_failed}
    end
  end

  @doc """
  Gate 2. Verifies that the contact sheet image matches paper layout rules.
  """
  def verify_gate_2(dir, sheet_path) do
    with {:ok, strips} <- analysis(dir),
         {:ok, dims} <- dimensions(sheet_path),
         {:ok, plan} <- compose_matching(strips, dir, dims) do
      {:ok, plan}
    else
      _ -> {:error, :gate_2_failed}
    end
  end

  # Gate 2. Every paper composes to a sheet exactly its own size, so at most
  # one can match the image on disk — which turns "assume 8x10" into a proof.
  defp compose_matching(strips, dir, dims) do
    layout = SheetLayout.layout_for_path(dir)

    Enum.find_value(SheetLayout.papers(), :error, fn paper ->
      case SheetLayout.compose(strips, layout, paper) do
        {:ok, %{sheet: ^dims} = plan} -> {:ok, plan}
        _ -> nil
      end
    end)
  end

  # Gate 1. The strips the assembler laid down are the image files in the roll
  # folder, in filename order; frames.json has to still be describing that set.
  defp manifest_matches?(dir, strips) do
    on_disk =
      case File.ls(dir) do
        {:ok, files} ->
          files
          |> Enum.filter(fn file ->
            Path.extname(file) |> String.downcase() |> Kernel.in(SheetLayout.strip_exts()) and
              File.regular?(Path.join(dir, file))
          end)
          |> Enum.sort()

        _ ->
          []
      end

    described = Enum.map(strips, & &1.file)

    if on_disk != [] and on_disk == described, do: :ok, else: :error
  end

  # frames.json, as written by `negatives --analyze`. Strips come back in
  # filename order because that is the order they were placed in.
  defp analysis(dir) do
    with {:ok, body} <- File.read(Path.join(dir, "frames.json")),
         {:ok, %{"strips" => strips}} when is_list(strips) and strips != [] <-
           Jason.decode(body),
         parsed when parsed != :error <- parse_strips(strips) do
      {:ok, parsed}
    else
      _ -> :error
    end
  end

  defp parse_strips(strips) do
    Enum.reduce_while(strips, [], fn strip, acc ->
      case strip do
        %{"file" => file, "width" => w, "height" => h, "frames" => frames}
        when is_binary(file) and is_integer(w) and is_integer(h) and is_list(frames) and w > 0 and
               h > 0 ->
          {:cont, [%{file: file, width: w, height: h, frames: parse_frames(frames)} | acc]}

        _ ->
          {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      parsed -> Enum.sort_by(parsed, & &1.file)
    end
  end

  defp parse_frames(frames) do
    Enum.flat_map(frames, fn
      %{"frame" => n, "region" => [x, y, w, h]}
      when is_integer(n) and is_number(x) and is_number(y) and is_number(w) and is_number(h) and
             w > 0 and h > 0 ->
        [%{frame: n, region: {x, y, w, h}}]

      _ ->
        []
    end)
  end
end
