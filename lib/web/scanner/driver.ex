defmodule Web.Scanner.Driver do
  @moduledoc """
  What to say to `scanimage`, and how to read what it says back. Pure: every
  function here builds an argument list or parses output, and `Web.Scanner.Bed`
  is the only thing that runs one — the split `Web.Media.FFmpeg` and the
  transcoder have.

  A film scan differs from a document scan in three ways, and leaving any of
  them out produces a file that looks like a scan and isn't one:

    * **Transmitted light.** `--source "Transparency Unit"` lights the film
      from the lid; the default lights it from below and photographs glare.
    * **Negative film.** `--film-type "Negative Film"` sets the backend's
      exposure for a negative's density range.
    * **An area.** One strip sits in the holder at a time, and the scan is
      cut to the rectangle that holder slot occupies on the glass
      (`-l -t -x -y`, millimetres). Without it every strip is the whole bed.

  The rectangles are per format and configured (`:web, :scanner_areas`) —
  they describe one physical holder on one scanner and are measured off a
  preview, not guessed.
  """

  @default_scanimage_bin "scanimage"

  @preview_dpi 75
  @strip_dpi 300
  @keeper_dpi 2400

  # Around a keeper frame, so a strip put back a little off still has its
  # frame inside the scan.
  @keeper_margin_mm 3.0

  def scanimage_bin, do: Application.get_env(:web, :scanimage_bin, @default_scanimage_bin)

  def strip_dpi, do: @strip_dpi
  def keeper_dpi, do: @keeper_dpi

  @doc "Arguments that list the SANE devices."
  def list_args, do: ["-L"]

  @doc """
  The devices in `scanimage -L` output, as `%{id, name, type}`. A webcam is a
  SANE device too (v4l) and is listed first on a laptop, so each is typed and
  only `:scanner` is ever scanned with.
  """
  def parse_devices(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case Regex.run(~r/device `([^']+)' is an? (.*)/, line) do
        [_, id, name] -> [%{id: id, name: String.trim(name), type: device_type(id, name)}]
        _ -> []
      end
    end)
  end

  defp device_type(id, name) do
    described = String.downcase(name)

    cond do
      String.starts_with?(id, "v4l:") -> :webcam
      String.contains?(described, ["webcam", "video camera", "virtual device"]) -> :webcam
      String.contains?(described, ["scanner", "flatbed", "perfection"]) -> :scanner
      true -> :other
    end
  end

  @doc """
  The scanner to use among `devices`: the first `:scanner`, or the first whose
  id starts with the pinned prefix (`:web, :scanner_device`, e.g. `epkowa`)
  when one is set. A prefix rather than a whole id, because the id carries the
  USB address and that changes every time the cable does.
  """
  def pick(devices) do
    scanners = Enum.filter(devices, &(&1.type == :scanner))

    case Application.get_env(:web, :scanner_device) do
      prefix when is_binary(prefix) and prefix != "" ->
        Enum.find(scanners, &String.starts_with?(&1.id, prefix))

      _ ->
        List.first(scanners)
    end
  end

  @doc """
  The holder rectangle for a film format as `{left, top, width, height}` in
  millimetres, or nil when none is configured for it. 620 is 120 film on a
  different spool and sits in the same slot.
  """
  def area("620"), do: area("120")

  def area(format) do
    case Map.get(Application.get_env(:web, :scanner_areas, %{}), format) do
      {l, t, x, y} = area when is_number(l) and is_number(t) and is_number(x) and is_number(y) ->
        area

      spec when is_binary(spec) ->
        parse_area(spec)

      _ ->
        nil
    end
  end

  @doc """
  Parses `"l,t,x,y"` (millimetres) into an area tuple, or nil — how the
  rectangles arrive from the environment.
  """
  def parse_area(spec) when is_binary(spec) do
    with [_, _, _, _] = parts <- spec |> String.split(",") |> Enum.map(&String.trim/1),
         [l, t, x, y] <- Enum.map(parts, &parse_mm/1),
         true <- Enum.all?([l, t, x, y], &is_float/1) and x > 0 and y > 0 do
      {l, t, x, y}
    else
      _ -> nil
    end
  end

  def parse_area(_spec), do: nil

  defp parse_mm(text) do
    case Float.parse(text) do
      {mm, ""} when mm >= 0 -> mm
      _ -> nil
    end
  end

  @doc "A low-resolution look at the whole transparency area, to place film by."
  def preview_args(device_id, output) do
    film_args(device_id) ++ ["--resolution", "#{@preview_dpi}", "--format=png"] ++ out(output)
  end

  @doc "One strip, cut to its format's holder rectangle, at contact-sheet resolution."
  def strip_args(device_id, format, color, output) do
    film_args(device_id) ++
      mode_args(color) ++
      ["--resolution", "#{@strip_dpi}", "--format=tiff"] ++
      area_args(area(format)) ++ out(output)
  end

  @doc """
  One frame at print resolution. `region` is the frame's rectangle within its
  strip scan, in that scan's pixels (as `frames.json` records it); the scan
  is cut to it plus a margin. With no region or no holder rectangle the whole
  strip slot is scanned.
  """
  def keeper_args(device_id, format, color, region, output) do
    film_args(device_id) ++
      mode_args(color) ++
      ["--resolution", "#{@keeper_dpi}", "--format=tiff"] ++
      area_args(frame_area(area(format), region)) ++ out(output)
  end

  @doc false
  def frame_area(nil, _region), do: nil
  def frame_area(area, nil), do: area

  def frame_area({left, top, width, height}, {x, y, w, h}) do
    mm = fn pixels -> pixels / @strip_dpi * 25.4 end

    l = max(left, left + mm.(x) - @keeper_margin_mm)
    t = max(top, top + mm.(y) - @keeper_margin_mm)
    right = min(left + width, left + mm.(x + w) + @keeper_margin_mm)
    bottom = min(top + height, top + mm.(y + h) + @keeper_margin_mm)

    {l, t, right - l, bottom - t}
  end

  defp film_args(device_id) do
    [
      "-d",
      device_id,
      "--source",
      "Transparency Unit",
      "--film-type",
      "Negative Film",
      "--progress"
    ]
  end

  defp mode_args("color"), do: ["--mode", "Color"]
  defp mode_args(_bw), do: ["--mode", "Gray"]

  defp area_args(nil), do: []

  defp area_args({l, t, x, y}) do
    ["-l", mm(l), "-t", mm(t), "-x", mm(x), "-y", mm(y)]
  end

  defp mm(value), do: :erlang.float_to_binary(value / 1, decimals: 1)

  defp out(path), do: ["--output-file", path]

  @doc """
  The percentage in a chunk of `scanimage --progress` output (`Progress:
  42.0%`, redrawn with carriage returns), or nil.
  """
  def progress(chunk) do
    case Regex.scan(~r/Progress:\s*([\d.]+)%/, chunk) do
      [] ->
        nil

      matches ->
        [_, value] = List.last(matches)
        {percent, _} = Float.parse(value)
        percent |> round() |> min(100)
    end
  end
end
