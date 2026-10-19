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

  **Stable Diffusion fills large damage, and only ever as a candidate**
  (`diffuse/2`, `developed/NN.candidate.png`): it paints what could have been
  there, not what was (over a shelf of cameras it put a canister that never
  stood there), so the author looks at it and keeps it (`keep/2`, which
  makes it the repair) or discards it. SD 1.5 inpainting (CreativeML
  OpenRAIL-M) in a Python of its own (`:sd_python`, PyTorch on the CPU), its
  parts loaded one after another. **It runs under a memory cap**
  (`:sd_memory_max`, systemd's `MemoryMax`, 3G, no swap, at the lowest
  priority): loaded whole it needed 5 GB, and the first try on this machine
  ran it out of memory and was killed by the kernel. It peaks at 2.1 GB, about
  two minutes a window, and one runs at a time on the machine.
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

  def sd_python,
    do:
      Application.get_env(
        :web,
        :sd_python,
        Path.expand("~/.local/share/film-repair/sd-venv/bin/python")
      )

  def sd_model,
    do:
      Application.get_env(
        :web,
        :sd_model,
        Path.expand("~/.local/share/film-repair/sd15-inpaint")
      )

  # The most memory Stable Diffusion may take, or nil to run it with no cap
  # (the suite, whose stand-in takes none).
  defp sd_memory, do: Application.get_env(:web, :sd_memory_max, "3G")

  defp script, do: Application.app_dir(:web, "priv/repair/film_repair.py")

  def mask?(roll_dir, frame), do: File.regular?(Darkroom.mask_path(roll_dir, frame))
  def repaired?(roll_dir, frame), do: File.regular?(Darkroom.repaired_path(roll_dir, frame))
  def candidate?(roll_dir, frame), do: File.regular?(Darkroom.candidate_path(roll_dir, frame))

  @doc """
  Finds the scanner's lines in the picture as developed and adds them to the
  mask. `{:ok, lines found}`.
  """
  def find_lines(roll_dir, frame) do
    source = developed(roll_dir, frame)
    found = Darkroom.mask_path(roll_dir, frame) <> ".found.png"
    File.mkdir_p!(Path.dirname(found))

    try do
      with {:ok, said} <- tool(python(), ["detect", source, found, "--lines"]),
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

      python()
      |> tool([
        "lama",
        Darkroom.base_path(roll_dir, frame),
        Darkroom.mask_path(roll_dir, frame),
        partial,
        "--model",
        lama_model()
      ])
      |> finish(partial, out)
    end
  end

  @doc """
  Fills what the mask covers with Stable Diffusion, lines corrected first as
  `lama/2` does, into the candidate. One at a time on the machine.
  `{:ok, %{lines: corrected, places: windows filled}}`.
  """
  def diffuse(roll_dir, frame) do
    with true <- mask?(roll_dir, frame) || {:error, "nothing is marked to repair"},
         :ok <- Darkroom.set_aside(roll_dir, frame) do
      out = Darkroom.candidate_path(roll_dir, frame)
      partial = out <> ".partial.png"

      fill = fn ->
        File.rm(partial)

        sd_python()
        |> tool(
          [
            "diffuse",
            Darkroom.base_path(roll_dir, frame),
            Darkroom.mask_path(roll_dir, frame),
            partial,
            "--model",
            sd_model()
          ],
          sd_memory()
        )
        |> finish(partial, out)
      end

      case :global.trans({__MODULE__.Diffusion, self()}, fill, [node()], 0) do
        :aborted -> {:error, "Stable Diffusion is already filling another print"}
        result -> result
      end
    end
  end

  @doc "Makes Stable Diffusion's candidate the repair."
  def keep(roll_dir, frame) do
    case File.rename(
           Darkroom.candidate_path(roll_dir, frame),
           Darkroom.repaired_path(roll_dir, frame)
         ) do
      :ok -> :ok
      {:error, _} -> {:error, "there is no fill to keep"}
    end
  end

  @doc "Throws Stable Diffusion's candidate away."
  def discard(roll_dir, frame) do
    File.rm(Darkroom.candidate_path(roll_dir, frame))
    :ok
  end

  defp finish({:ok, said}, partial, out) do
    File.rename!(partial, out)
    {:ok, %{lines: said["lines"] || 0, places: said["windows"] || 0}}
  end

  defp finish(error, partial, _out) do
    File.rm(partial)
    error
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

  # Runs the script under `python`; given a memory cap, inside a systemd
  # scope the kernel stops alone when it reaches the cap, at the lowest
  # priority. The script prints one JSON line when it is done; PyTorch and
  # its libraries print their own lines around it.
  defp tool(python, args, memory \\ nil) do
    with exe when is_binary(exe) <-
           System.find_executable(python) ||
             {:error, "the repair tools are not installed (#{python})"},
         {:ok, cmd, argv} <- command(exe, ["-I", script() | args], memory) do
      case System.cmd(cmd, argv, stderr_to_stdout: true, env: [{"HF_HUB_OFFLINE", "1"}]) do
        {output, 0} ->
          {:ok,
           output
           |> String.split("\n", trim: true)
           |> Enum.reverse()
           |> Enum.find_value(%{}, &said/1)}

        {_output, status} when memory != nil and status in [137, 143] ->
          {:error,
           "Stable Diffusion reached its #{memory} of memory and was stopped. Mark a smaller area."}

        {output, status} ->
          {:error,
           "film_repair exited #{status}: #{output |> String.split("\n", trim: true) |> Enum.take(-2) |> Enum.join(" ")}"}
      end
    end
  end

  defp said("{" <> _ = line) do
    case Jason.decode(line) do
      {:ok, %{} = said} -> said
      _ -> nil
    end
  end

  defp said(_line), do: nil

  defp command(exe, argv, nil), do: {:ok, exe, argv}

  defp command(exe, argv, memory) do
    case System.find_executable("systemd-run") do
      nil ->
        {:error, "Stable Diffusion runs only under a memory cap, and systemd-run is not here"}

      systemd_run ->
        {:ok, systemd_run,
         ["--user", "--scope", "--quiet", "-p", "MemoryMax=#{memory}", "-p", "MemorySwapMax=0"] ++
           ["nice", "-n", "19", exe | argv]}
    end
  end

  defp magick(args) do
    case System.cmd(Web.Negatives.magick_bin(), args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, _} -> {:error, "magick: #{String.slice(out, 0, 200)}"}
    end
  end
end
