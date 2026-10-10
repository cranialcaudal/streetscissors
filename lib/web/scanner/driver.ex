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
    * **Unconverted.** `--film-type "Positive Film"`, for a negative. The
      backend's "Negative Film" does not invert: it rebalances the channels
      against the orange mask, and `film-develop` measures and removes that
      mask itself, so a strip scanned that way is corrected twice. "Positive
      Film" hands over what the sensor saw, which is what every strip in the
      archive is.
    * **An area.** One strip sits in the holder at a time, and the scan is
      cut to the rectangle that holder slot occupies on the glass
      (`-l -t -x -y`, millimetres). Without it every strip is the whole bed.

  The rectangles are per format and configured (`:web, :scanner_areas`) —
  they describe one physical holder on one scanner and are measured off a
  preview, not guessed.
  """

  @default_scanimage_bin "scanimage"

  # The V550 scans film at 400, 800, 1600 and 3200 dpi and nothing between
  # (`scanimage --help` with the transparency unit selected). Asked for
  # anything else, scanimage rounds to the nearest of those, says so on one
  # line and exits 0: a "300 dpi" strip came back at 400. So every figure
  # asked of the scanner is one it has, and a strip, which the archive and
  # the sheet's arithmetic hold to 300, is brought down to that afterwards.
  @preview_dpi 400
  # A pass is the whole holder at once, every strip on it: a look to choose
  # frames by, and the strips themselves, which the sheet needs at only 300.
  # So it is the quickest the scanner has (28 s; 43 s at 800, 135 s at 1600).
  @pass_dpi 400
  @strip_scan_dpi 400
  @strip_dpi 300
  # A chosen frame, the author's figure. The scanner's time goes with the
  # length of glass it crosses, so frames are scanned in bands (`bands/2`),
  # not one by one and not the whole holder.
  @keeper_dpi 1600

  # Around a keeper frame, so a strip put back a little off still has its
  # frame inside the scan. A strip that has not left the holder since its
  # look is where the analysis found it and needs none: a frame's rectangle
  # in `frames.json` is the picture itself (since October 2026 the analysis
  # leaves the rebate out), and any margin would print that rebate back in.
  @keeper_margin_mm 3.0
  @keeper_in_place_margin_mm 0.0

  def scanimage_bin, do: Application.get_env(:web, :scanimage_bin, @default_scanimage_bin)

  def preview_dpi, do: @preview_dpi
  def pass_dpi, do: @pass_dpi
  def strip_dpi, do: @strip_dpi
  def keeper_dpi, do: @keeper_dpi

  @doc "The margin around a frame, in mm: `:put_back` or `:in_place` (see above)."
  def keeper_margin(:in_place), do: @keeper_in_place_margin_mm
  def keeper_margin(_put_back), do: @keeper_margin_mm

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

  @doc """
  The whole transparency area in colour at `pass_dpi/0`: every strip in the
  holder in one scan. Colour whatever the film, since whether it is colour is
  read off this scan.
  """
  def pass_args(device_id, output) do
    film_args(device_id) ++
      ["--mode", "Color", "--resolution", "#{@pass_dpi}", "--format=tiff"] ++ out(output)
  end

  @doc """
  One strip, cut to its format's holder rectangle. It is scanned at the
  nearest resolution the scanner has; `strip_resample/0` is what then makes it
  the contact sheet's.
  """
  def strip_args(device_id, format, color, output) do
    film_args(device_id) ++
      mode_args(color) ++
      ["--resolution", "#{@strip_scan_dpi}", "--format=tiff"] ++
      area_args(area(format)) ++ out(output)
  end

  @doc "What a strip is scanned at and what it is kept at, as `{from, to}` dpi."
  def strip_resample, do: {@strip_scan_dpi, @strip_dpi}

  @doc """
  ImageMagick arguments that bring the TIFF at `path` from one resolution to
  another, in place, and record the new one in the file.
  """
  def resample_args(path, {from, to}) do
    percent = :erlang.float_to_binary(to / from * 100, decimals: 4)

    [
      "tiff:" <> path,
      "-resize",
      percent <> "%",
      "-units",
      "PixelsPerInch",
      "-density",
      "#{to}",
      "tiff:" <> path
    ]
  end

  @doc """
  One frame at print resolution. `region` is the frame's rectangle within its
  strip scan, in that scan's pixels (as `frames.json` records it); the scan
  is cut to it plus a margin. With no region or no holder rectangle the whole
  strip slot is scanned.
  """
  def keeper_args(
        device_id,
        format,
        color,
        region,
        output,
        margin \\ @keeper_margin_mm,
        opts \\ []
      ) do
    film_args(device_id) ++
      mode_args(color) ++
      depth_args(opts) ++
      ["--resolution", "#{@keeper_dpi}", "--format=tiff"] ++
      area_args(frame_area(area(format), region, margin)) ++ out(output)
  end

  @doc """
  A band across the glass at print resolution: `rect` is `{left, top, width,
  height}` in mm.
  """
  def band_args(device_id, color, rect, output, opts \\ []) do
    film_args(device_id) ++
      mode_args(color) ++
      depth_args(opts) ++
      ["--resolution", "#{@keeper_dpi}", "--format=tiff"] ++ area_args(rect) ++ out(output)
  end

  @doc """
  Gathers frames into as few bands as cover them: `frames` is `[{frame,
  {left, top, width, height}}]` in mm on the glass. Frames that overlap down
  the glass, or lie within `gap` mm of each other, share a band (two frames
  side by side in the two slots cost one crossing, and so do neighbours on a
  strip); each band is as wide as its frames need. Returned top to bottom as
  `%{rect: {l, t, w, h}, frames: [{frame, rect}]}`.
  """
  def bands(frames, gap \\ 5.0) do
    frames
    |> Enum.sort_by(fn {_frame, {_l, t, _w, _h}} -> t end)
    |> Enum.reduce([], fn {_frame, {_l, t, _w, h}} = item, groups ->
      case groups do
        [{bottom, items} | rest] when t <= bottom + gap ->
          [{max(bottom, t + h), [item | items]} | rest]

        _ ->
          [{t + h, [item]} | groups]
      end
    end)
    |> Enum.reverse()
    |> Enum.map(fn {bottom, items} ->
      items = Enum.reverse(items)
      left = items |> Enum.map(fn {_, {l, _, _, _}} -> l end) |> Enum.min()
      right = items |> Enum.map(fn {_, {l, _, w, _}} -> l + w end) |> Enum.max()
      top = items |> Enum.map(fn {_, {_, t, _, _}} -> t end) |> Enum.min()
      %{rect: {left, top, right - left, bottom - top}, frames: items}
    end)
  end

  @doc false
  def frame_area(area, region, margin \\ @keeper_margin_mm)
  def frame_area(nil, _region, _margin), do: nil
  def frame_area(area, nil, _margin), do: area

  def frame_area({left, top, width, height}, {x, y, w, h}, margin) do
    mm = fn pixels -> pixels / @strip_dpi * 25.4 end

    l = max(left, left + mm.(x) - margin)
    t = max(top, top + mm.(y) - margin)
    right = min(left + width, left + mm.(x + w) + margin)
    bottom = min(top + height, top + mm.(y + h) + margin)

    {l, t, right - l, bottom - t}
  end

  defp film_args(device_id) do
    [
      "-d",
      device_id,
      "--source",
      "Transparency Unit",
      "--film-type",
      "Positive Film",
      "--progress"
    ]
  end

  # `deep: true` is sixteen bits a channel, for a slide's singles. A dense
  # slide keeps its whole picture in the bottom twenty of 256 levels, and
  # lifted from eight bits it prints in steps. Negatives sit in the middle of
  # the scale and are left at eight, at a third of the file.
  defp depth_args(opts), do: if(opts[:deep], do: ["--depth", "16"], else: [])

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
