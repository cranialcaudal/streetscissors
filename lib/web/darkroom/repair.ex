defmodule Web.Darkroom.Repair do
  @moduledoc """
  Marks on a scan repaired before the print is graded: the scanner's lines,
  scratches and hairs. His choice (2026-10-18): LaMa for these, and Stable
  Diffusion for large damage, looked at before it is kept.

  **A repair is a mask and a picture made from it, never a change to the
  print.** The mask (white where a mark is) is `edits/NN.mask.png`, painted
  by hand in the editor or found (`find_lines/3`: rows that stand out from
  both sides the whole way along; a finder for scratches was tried and found
  only real things, so scratches are painted). The repaired picture is
  `developed/NN.repaired.png`, made from the print as developed
  (`developed/NN.png`) and the mask, and it is what the sliders then work on
  (`Darkroom.source_path/2`). Revert takes all of it away.

  **A scanner line is corrected, not painted.** Rows (or columns) the mask
  covers the whole way along are taken for a line: a fault of the scanner,
  the same all along, so the picture under it is still there, a gain and an
  offset away in the channels it touched. Undoing that brings back what was
  under it as it was; on the Powell Camera print LaMa had painted out a
  reflection in a picture frame and dented a camera that the correction
  keeps. LaMa gets only what a line took past bringing back (pixels pushed to
  black or white, rows all but blanked) and everything else the mask covers:
  scratches, hairs, a scratch along the film that varies as it goes.

  The work is `priv/repair/film_repair.py` (numpy, OpenCV and onnxruntime in
  a Python of its own, `:film_repair_python`) with LaMa's ONNX port
  (`:lama_model`, Apache-2.0), in 512-pixel windows at the picture's own
  resolution, its grain measured around each place and put back. A line's
  correction takes about a second; LaMa about seven seconds a window on this
  machine, and 1.2 GB of memory at most.
  """

  alias Web.Darkroom

  def python,
    do:
      Application.get_env(
        :web,
        :film_repair_python,
        Path.expand("~/.local/share/film-repair/venv/bin/python")
      )

  def lama_model,
    do:
      Application.get_env(
        :web,
        :lama_model,
        Path.expand("~/.local/share/film-repair/lama_fp32.onnx")
      )

  defp script, do: Application.app_dir(:web, "priv/repair/film_repair.py")

  def mask?(roll_dir, frame), do: File.regular?(Darkroom.mask_path(roll_dir, frame))
  def repaired?(roll_dir, frame), do: File.regular?(Darkroom.repaired_path(roll_dir, frame))

  @doc """
  Finds the scanner's lines in the picture as developed and adds them to the
  mask. `{:ok, lines found}`.
  """
  def find_lines(roll_dir, frame) do
    source = developed(roll_dir, frame)
    found = Darkroom.mask_path(roll_dir, frame) <> ".found.png"
    File.mkdir_p!(Path.dirname(found))

    try do
      with {:ok, said} <- tool(["detect", source, found, "--lines"]),
           :ok <- merge_mask(roll_dir, frame, found) do
        {:ok, said["lines"] || 0}
      end
    after
      File.rm(found)
    end
  end

  @doc """
  Keeps a mask the browser painted: PNG bytes, the picture's own size. A mask
  with nothing on it is no mask.
  """
  def put_mask(roll_dir, frame, <<137, "PNG", _::binary>> = png)
      when byte_size(png) < 8_000_000 do
    path = Darkroom.mask_path(roll_dir, frame)
    File.mkdir_p!(Path.dirname(path))
    partial = path <> ".partial.png"
    File.write!(partial, png)

    # Grey, white where painted, and the picture's size.
    {w, h} = Darkroom.dimensions(developed(roll_dir, frame)) || {0, 0}

    result =
      magick([
        partial,
        "-alpha",
        "off",
        "-colorspace",
        "Gray",
        "-threshold",
        "50%",
        "-resize",
        "#{w}x#{h}!",
        "-depth",
        "8",
        partial
      ])

    with :ok <- result,
         {:ok, empty?} <- blank?(partial) do
      if empty?,
        do:
          (
            File.rm(partial)
            File.rm(path)
          ),
        else: File.rename!(partial, path)

      :ok
    else
      error ->
        File.rm(partial)
        error
    end
  end

  def put_mask(_roll_dir, _frame, _png), do: {:error, "that is not a picture of a mask"}

  def clear_mask(roll_dir, frame) do
    File.rm(Darkroom.mask_path(roll_dir, frame))
    :ok
  end

  @doc """
  Repairs what the mask covers, from the print as developed (set aside first
  if the frame has not been edited yet), into the repaired picture: lines
  corrected, the rest painted by LaMa. `{:ok, %{lines: corrected, places:
  windows LaMa painted}}`.
  """
  def lama(roll_dir, frame) do
    with true <- mask?(roll_dir, frame) || {:error, "nothing is marked to repair"},
         :ok <- Darkroom.set_aside(roll_dir, frame) do
      out = Darkroom.repaired_path(roll_dir, frame)
      partial = out <> ".partial.png"

      result =
        tool([
          "lama",
          Darkroom.base_path(roll_dir, frame),
          Darkroom.mask_path(roll_dir, frame),
          partial,
          "--model",
          lama_model()
        ])

      case result do
        {:ok, said} ->
          File.rename!(partial, out)
          {:ok, %{lines: said["lines"] || 0, places: said["windows"] || 0}}

        error ->
          File.rm(partial)
          error
      end
    end
  end

  @doc "Takes the repair away; the mask stays to be repaired again."
  def undo(roll_dir, frame) do
    File.rm(Darkroom.repaired_path(roll_dir, frame))
    :ok
  end

  # The picture marks are found on and repaired from: as developed.
  defp developed(roll_dir, frame) do
    base = Darkroom.base_path(roll_dir, frame)
    if File.regular?(base), do: base, else: Darkroom.print_path(roll_dir, frame)
  end

  defp merge_mask(roll_dir, frame, found) do
    path = Darkroom.mask_path(roll_dir, frame)

    with {:ok, nothing?} <- blank?(found) do
      cond do
        nothing? -> :ok
        File.regular?(path) -> magick([path, found, "-compose", "lighten", "-composite", path])
        true -> File.cp(found, path)
      end
    end
  end

  defp blank?(path) do
    case System.cmd(Web.Negatives.magick_bin(), [path, "-format", "%[fx:maxima]", "info:"],
           stderr_to_stdout: true
         ) do
      {out, 0} ->
        case Float.parse(String.trim(out)) do
          {max, _} -> {:ok, max == 0}
          :error -> {:error, "magick could not read the mask"}
        end

      {out, _} ->
        {:error, "magick: #{String.slice(out, 0, 200)}"}
    end
  end

  defp tool(args) do
    case System.find_executable(python()) do
      nil ->
        {:error, "the repair tools are not installed (#{python()})"}

      exe ->
        case System.cmd(exe, ["-I", script() | args], stderr_to_stdout: true) do
          {output, 0} ->
            line = output |> String.split("\n", trim: true) |> List.last() |> to_string()

            case Jason.decode(line) do
              {:ok, %{} = said} -> {:ok, said}
              _ -> {:ok, %{}}
            end

          {output, status} ->
            {:error,
             "film_repair exited #{status}: #{output |> String.split("\n", trim: true) |> Enum.take(-2) |> Enum.join(" ")}"}
        end
    end
  end

  defp magick(args) do
    case System.cmd(Web.Negatives.magick_bin(), args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, _} -> {:error, "magick: #{String.slice(out, 0, 200)}"}
    end
  end
end
