defmodule Web.Darkroom do
  @moduledoc """
  A single print, edited after it is developed: the Lightroom half of the
  admin's darkroom (`/admin/darkroom`, `WebWeb.AdminLive.DarkroomEditor`).

  **The engine is LightCraft** (`lightcraft-cli`, MIT or Apache-2.0, built from
  github.com/storytold/lightcraft and installed beside `film-develop`). Every
  picture the editor shows and every print it writes is LightCraft's, so what is
  seen while a slider moves is what gets printed: `Web.Darkroom.Session` keeps
  one `lightcraft-cli mcp` open per editor for the previews, `save/3` runs
  `lightcraft-cli run` once for the print, and both are given the commands
  `commands/1` builds from the recipe. There is no second implementation of the
  adjustments to keep in step.

  **An edit is a recipe, never a change to the picture.** A frame's edits are
  `edits/NN.json` in its roll's folder: the sliders that are off their default,
  by LightCraft's control id, and the crop. The picture they apply to is the
  print as `film-develop` made it, set aside as `developed/NN.png` the first
  time the frame is edited; `frames/NN.png`, the print the site serves, is that
  picture with the recipe applied. So:

    * `revert/2` puts `developed/NN.png` back and deletes the recipe.
    * Developing the frame again (`Pipeline.develop_keeper/2`) makes a new
      `developed/NN.png` and applies the recipe to it (`reapply/2`).
    * Turning a frame turns `developed/NN.png` with the print and the crop with
      them (`turn/3`); renumbering a strip's singles carries both files.

  `developed/` and `edits/` sit beside `frames/`, not in it, so neither is
  served. `film-develop redevelop` run by hand writes `frames/` directly and
  knows nothing of recipes: go through `develop_keeper/2` for an edited roll.

  **The crop is LightCraft's**: `rect` is `[x0, y0, x1, y1]` in fractions of
  the picture, `angle` the straightening in degrees clockwise. A rect that no
  longer fits once straightened is shrunk by LightCraft to the largest of its
  shape that does.
  """

  require Logger

  alias Web.Negatives

  @preview_edge 1200

  # What the editor offers, in order: {section, title, colour only?}. The
  # engine's other sections are left out on purpose: lens optics and camera
  # calibration describe a digital camera, `profile` a raw file's, and the
  # `sdr*` sliders an HDR edit's.
  @sections [
    {"light", "Light", false},
    {"color", "Colour", true},
    {"curve", "Tone curve", false},
    {"mixer", "Colour mixer", true},
    {"bwMix", "Black and white mix", true},
    {"grading", "Colour grading", true},
    {"effects", "Effects", false},
    {"detail", "Detail", false},
    {"vignette", "Vignette", false}
  ]

  # Within the sections shown: the HDR sliders (an HDR edit's, shown in Light)
  # and the AI denoiser (a model that is not installed).
  @hidden_prefixes ["hdr.", "enhance."]

  @doc "The editor's engine, configurable so the suite can stand a stub in."
  def bin, do: Application.get_env(:web, :lightcraft_bin, "lightcraft-cli")

  @doc "The edge, in pixels, of the pictures the editor shows while working."
  def preview_edge, do: @preview_edge

  # ── Where things are ──────────────────────────────────────────────────

  def print_path(roll_dir, frame), do: Path.join([roll_dir, "frames", "#{pad2(frame)}.png"])
  def base_path(roll_dir, frame), do: Path.join([roll_dir, "developed", "#{pad2(frame)}.png"])
  def edits_path(roll_dir, frame), do: Path.join([roll_dir, "edits", "#{pad2(frame)}.json"])

  @doc "A frame's repair mask (`Web.Darkroom.Repair`): white where a mark is."
  def mask_path(roll_dir, frame), do: Path.join([roll_dir, "edits", "#{pad2(frame)}.mask.png"])

  @doc "The print as developed, with the marks the mask covers repaired."
  def repaired_path(roll_dir, frame),
    do: Path.join([roll_dir, "developed", "#{pad2(frame)}.repaired.png"])

  @doc "A repair offered for looking at before it is kept (Stable Diffusion's)."
  def candidate_path(roll_dir, frame),
    do: Path.join([roll_dir, "developed", "#{pad2(frame)}.candidate.png"])

  @doc "Whether a frame's print has a recipe applied to it."
  def edited?(roll_dir, frame), do: File.regular?(edits_path(roll_dir, frame))

  @doc """
  The picture a frame's edits apply to: its repaired picture when it has one,
  else the print as it was developed when the frame has been edited, else the
  print itself, which is that picture.
  """
  def source_path(roll_dir, frame) do
    repaired = repaired_path(roll_dir, frame)
    base = base_path(roll_dir, frame)

    cond do
      File.regular?(repaired) -> repaired
      File.regular?(base) -> base
      true -> print_path(roll_dir, frame)
    end
  end

  # ── The recipe ────────────────────────────────────────────────────────

  @doc """
  A frame's recipe: `%{controls: %{id => number}, crop: nil | %{rect, angle},
  spots: [%{x, y, size}]}`. Spots are dust healed by LightCraft, in
  fractions of the whole picture (not of the crop), `size` a fraction of its
  long edge.
  """
  def recipe(roll_dir, frame) do
    with {:ok, body} <- File.read(edits_path(roll_dir, frame)),
         {:ok, %{} = doc} <- Jason.decode(body) do
      from_json(doc)
    else
      _ -> empty()
    end
  end

  def empty, do: %{controls: %{}, crop: nil, spots: []}

  @doc "Whether a recipe changes nothing."
  def empty?(recipe), do: recipe.controls == %{} and recipe.crop == nil and spots(recipe) == []

  defp spots(recipe), do: Map.get(recipe, :spots, [])

  defp from_json(doc) do
    controls =
      for {id, value} <- doc["controls"] || %{}, is_binary(id), is_number(value), into: %{} do
        {id, value}
      end

    %{controls: controls, crop: crop_from_json(doc["crop"]), spots: clean_spots(doc["spots"])}
  end

  defp crop_from_json(%{"rect" => [x0, y0, x1, y1] = rect} = crop)
       when x0 < x1 and y0 < y1 do
    if Enum.all?(rect, &is_number/1), do: %{rect: rect, angle: crop["angle"] || 0}
  end

  defp crop_from_json(_), do: nil

  defp to_json(%{controls: controls, crop: crop} = recipe) do
    %{
      "controls" => controls,
      "crop" => crop && %{"rect" => crop.rect, "angle" => crop.angle},
      "spots" => Enum.map(spots(recipe), &%{"x" => &1.x, "y" => &1.y, "size" => &1.size}),
      "saved_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  @doc """
  The commands that apply a recipe, after a `develop.reset`. The same list goes
  to the open session for a preview and into the script for the print.

  `size` is the picture's `{width, height}`. **A crop's edges are put on whole
  pixels**: LightCraft resamples a crop whose edge falls between two (0.3 of
  2229 pixels is 668.7), and the print came out with two fifths of its fine
  detail gone; on whole pixels it is the picture's own pixels, untouched.
  """
  def commands(%{controls: controls, crop: crop} = recipe, size \\ nil) do
    set = if controls == %{}, do: [], else: [{"develop.set", %{"values" => controls}}]

    cut =
      if crop,
        do: [{"crop.set", %{"rect" => snap(crop.rect, size), "angle" => crop.angle}}],
        else: []

    heal =
      for spot <- spots(recipe) do
        {"spot.add", %{"mode" => "heal", "points" => [[spot.x, spot.y]], "size" => spot.size}}
      end

    [{"develop.reset", %{}} | set ++ cut ++ heal]
  end

  @doc false
  def snap(rect, nil), do: rect

  def snap([x0, y0, x1, y1], {w, h}) do
    [round(x0 * w) / w, round(y0 * h) / h, round(x1 * w) / w, round(y1 * h) / h]
  end

  @doc """
  Dust spots the browser or LightCraft gave, held to the picture and to a
  sensible size, at most three hundred.
  """
  def clean_spots(list) when is_list(list) do
    list
    |> Enum.flat_map(fn spot ->
      with %{} <- spot,
           x when is_float(x) <- number(spot["x"] || spot[:x]),
           y when is_float(y) <- number(spot["y"] || spot[:y]),
           true <- x >= 0 and x <= 1 and y >= 0 and y <= 1 do
        size = (number(spot["size"] || spot[:size]) || 0.004) |> max(0.001) |> min(0.05)
        [%{x: x, y: y, size: size}]
      else
        _ -> []
      end
    end)
    |> Enum.take(300)
  end

  def clean_spots(_), do: []

  @doc "The export a preview is: JPEG, `preview_edge/0` on the long side."
  def preview_export(path) do
    {"app.export",
     %{
       "path" => path,
       "longEdge" => @preview_edge,
       "quality" => 85,
       "metadata" => "none",
       "conflict" => "overwrite"
     }}
  end

  defp print_export(path) do
    {"app.export",
     %{"path" => path, "longEdge" => 0, "metadata" => "none", "conflict" => "overwrite"}}
  end

  # ── The sliders ───────────────────────────────────────────────────────

  @doc """
  The engine's slider schema (`develop.controls`) cut down to what a print
  from film is edited with, grouped by section. A grey print loses every
  section that only means something in colour: on a black and white print
  white balance and vibrance only tint it.
  """
  def sections(schema, grey?) do
    by_section = Enum.group_by(schema, & &1["section"])

    Enum.flat_map(@sections, fn {key, title, colour?} ->
      controls = Enum.reject(by_section[key] || [], &hidden?/1)

      if controls == [] or (grey? and colour?),
        do: [],
        else: [%{key: key, title: title, controls: controls}]
    end)
  end

  defp hidden?(%{"id" => id}), do: String.starts_with?(id, @hidden_prefixes)

  @doc """
  Keeps only real sliders off their default, each held to its range. What the
  browser sends is never passed on unchecked: an unknown id would fail the
  whole `develop.set`.
  """
  def clean_controls(values, schema) do
    known = Map.new(schema, &{&1["id"], &1})

    values
    |> Enum.flat_map(fn {id, raw} ->
      with %{"min" => lo, "max" => hi, "default" => default} <- known[id],
           value when is_float(value) <- number(raw),
           value = value |> max(lo) |> min(hi),
           true <- abs(value - default) > 1.0e-9 do
        [{id, value}]
      else
        _ -> []
      end
    end)
    |> Map.new()
  end

  @doc """
  The ids among `values` that `clean_controls/2` would drop for not being a
  slider the engine offers (an unknown id, or a control with no range, such
  as a curve), as opposed to one only sitting at its default. Said aloud
  rather than lost quietly: a LightCraft upgrade that renames a slider would
  otherwise strip it from every saved edit on the next save.
  """
  def unknown_controls(values, schema) do
    sliders =
      for %{"id" => id, "min" => _, "max" => _, "default" => _} <- schema, into: MapSet.new(), do: id

    values |> Map.keys() |> Enum.reject(&MapSet.member?(sliders, &1)) |> Enum.sort()
  end

  @doc "A crop the browser sent, or nil when it is the whole picture and level."
  def clean_crop(%{"rect" => rect} = crop) when is_list(rect) and length(rect) == 4 do
    angle = (number(crop["angle"]) || 0.0) |> max(-45.0) |> min(45.0)

    case Enum.map(rect, &number/1) do
      [x0, y0, x1, y1] when is_number(x0) and is_number(y0) and is_number(x1) and is_number(y1) ->
        [x0, y0, x1, y1] = Enum.map([x0, y0, x1, y1], &(&1 |> max(0.0) |> min(1.0)))

        cond do
          x1 - x0 < 0.02 or y1 - y0 < 0.02 -> nil
          [x0, y0, x1, y1] == [0.0, 0.0, 1.0, 1.0] and angle == 0.0 -> nil
          true -> %{rect: [x0, y0, x1, y1], angle: angle}
        end

      _ ->
        nil
    end
  end

  def clean_crop(_), do: nil

  defp number(value) when is_number(value), do: value * 1.0

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> float
      _ -> nil
    end
  end

  defp number(_), do: nil

  # ── Printing ──────────────────────────────────────────────────────────

  @doc """
  Prints a frame with `recipe` and keeps the recipe. The first edit sets the
  print as it was developed aside, which is what every later edit starts from.
  An empty recipe is a revert.
  """
  def save(roll_dir, frame, recipe) do
    if empty?(recipe) and not File.regular?(repaired_path(roll_dir, frame)) do
      revert(roll_dir, frame)
    else
      base = base_path(roll_dir, frame)
      print = print_path(roll_dir, frame)

      with :ok <- copy_aside(print, base),
           :ok <- render(source_path(roll_dir, frame), recipe, print),
           :ok <- write_recipe(roll_dir, frame, recipe) do
        clear_previews(roll_dir, frame)
        :ok
      end
    end
  end

  # ── One edit for many prints ──────────────────────────────────────────

  defp clipboard_path, do: Path.join([Web.Negatives.base_path(), ".darkroom", "clipboard.json"])

  @doc """
  Keeps a print's sliders to paste onto another (`copied_controls/0`). Only
  the sliders: a crop, the dust and a repair belong to one frame. Kept in a
  file beside the archive's other darkroom state, so it outlasts moving from
  one print's page to the next.
  """
  def copy_controls(controls) when is_map(controls) do
    path = clipboard_path()

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      Web.SourceFile.write_atomic(path, Jason.encode!(%{"controls" => controls}))
    end
  end

  @doc "The sliders last copied, or nil."
  def copied_controls do
    with {:ok, body} <- File.read(clipboard_path()),
         {:ok, %{"controls" => %{} = controls}} <- Jason.decode(body) do
      controls
    else
      _ -> nil
    end
  end

  @doc """
  Prints each of `frames` with `controls` as its sliders, each keeping its
  own crop, dust and repair. `progress` is told `{done, total}` after each.
  Returns the frames that could not be printed, with why.
  """
  def apply_controls(roll_dir, frames, controls, progress \\ fn _ -> :ok end) do
    total = length(frames)

    frames
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {frame, done} ->
      result = save(roll_dir, frame, %{recipe(roll_dir, frame) | controls: controls})
      progress.({done, total})

      case result do
        :ok -> []
        {:error, reason} -> [{frame, reason}]
        other -> [{frame, inspect(other)}]
      end
    end)
  end

  @doc "Puts the print back as it was developed and forgets the recipe."
  def revert(roll_dir, frame) do
    base = base_path(roll_dir, frame)

    if File.regular?(base), do: File.rename!(base, print_path(roll_dir, frame))
    File.rm(edits_path(roll_dir, frame))

    for path <- [
          mask_path(roll_dir, frame),
          repaired_path(roll_dir, frame),
          candidate_path(roll_dir, frame)
        ],
        do: File.rm(path)

    clear_previews(roll_dir, frame)
    :ok
  end

  @doc """
  After a frame is developed again: the new print is the new picture its
  recipe applies to. Nothing to do for a frame with no recipe.
  """
  def reapply(roll_dir, frame) do
    if edited?(roll_dir, frame) do
      base = base_path(roll_dir, frame)
      print = print_path(roll_dir, frame)
      File.mkdir_p!(Path.dirname(base))
      File.rename!(print, base)

      # The repair was made from the old development: made again from the new.
      File.rm(repaired_path(roll_dir, frame))
      File.rm(candidate_path(roll_dir, frame))
      if File.regular?(mask_path(roll_dir, frame)), do: Web.Darkroom.Repair.lama(roll_dir, frame)

      with {:error, reason} <-
             render(source_path(roll_dir, frame), recipe(roll_dir, frame), print) do
        # The new development is still worth showing; the recipe is kept.
        File.cp!(base, print)
        {:error, reason}
      end
    else
      :ok
    end
  end

  @doc """
  A frame was turned `degrees` clockwise (the print already has been): turns
  the developed picture with it and the crop's rectangle with the picture.
  """
  def turn(roll_dir, frame, degrees) do
    if edited?(roll_dir, frame) and rem(degrees, 360) != 0 do
      for path <- [
            base_path(roll_dir, frame),
            mask_path(roll_dir, frame),
            repaired_path(roll_dir, frame)
          ],
          File.regular?(path),
          do: magick([path, "-rotate", "#{degrees}", path])

      File.rm(candidate_path(roll_dir, frame))

      recipe = recipe(roll_dir, frame)

      write_recipe(roll_dir, frame, %{
        recipe
        | crop: turn_crop(recipe.crop, degrees),
          spots: Enum.map(recipe.spots, &turn_spot(&1, degrees))
      })
    else
      :ok
    end
  end

  @doc """
  A crop turned with its picture, a quarter at a time: a point `(x, y)` of the
  picture is at `(1 - y, x)` once the picture is turned a quarter clockwise.
  """
  def turn_crop(nil, _degrees), do: nil

  def turn_crop(crop, degrees) do
    turns = div(rem(rem(degrees, 360) + 360, 360), 90)

    rect =
      Enum.reduce(List.duplicate(:quarter, turns), crop.rect, fn :quarter, [x0, y0, x1, y1] ->
        [1 - y1, x0, 1 - y0, x1]
      end)

    %{crop | rect: rect}
  end

  @doc "A dust spot turned with its picture, a quarter at a time, as `turn_crop/2` turns a crop."
  def turn_spot(spot, degrees) do
    turns = div(rem(rem(degrees, 360) + 360, 360), 90)

    Enum.reduce(List.duplicate(:quarter, turns), spot, fn :quarter, %{x: x, y: y} = s ->
      %{s | x: 1 - y, y: x}
    end)
  end

  @doc "Sets the print as developed aside, the first time a frame is changed."
  def set_aside(roll_dir, frame),
    do: copy_aside(print_path(roll_dir, frame), base_path(roll_dir, frame))

  defp copy_aside(print, base) do
    cond do
      File.regular?(base) ->
        :ok

      File.regular?(print) ->
        File.mkdir_p!(Path.dirname(base))
        File.cp!(print, base)
        :ok

      true ->
        {:error, "there is no print of this frame"}
    end
  end

  defp write_recipe(roll_dir, frame, recipe) do
    path = edits_path(roll_dir, frame)
    File.mkdir_p!(Path.dirname(path))
    partial = path <> ".partial"
    File.write!(partial, Jason.encode_to_iodata!(to_json(recipe), pretty: true))
    File.rename!(partial, path)
    :ok
  end

  @doc """
  Applies `recipe` to the picture at `input` and writes the whole print to
  `output`. The print is made beside the developed picture, outside `frames/`,
  and moved into place only when it is finished, so the site never serves half
  a file. A grey picture is printed grey: LightCraft writes colour.
  """
  def render(input, recipe, output) do
    scratch = Path.join(Path.dirname(input), ".print-#{System.unique_integer([:positive])}")
    File.mkdir_p!(scratch)
    made = Path.join(scratch, "print.png")
    script = Path.join(scratch, "commands.jsonl")

    lines =
      for {command, params} <- commands(recipe, dimensions(input)) ++ [print_export(made)] do
        Jason.encode!(%{"command" => command, "params" => params})
      end

    File.write!(script, Enum.join(lines, "\n") <> "\n")

    try do
      with {:ok, output_text} <- run(["run", "--import", input, "--script", script]),
           :ok <- all_ok(output_text),
           true <- File.regular?(made) or {:error, "lightcraft-cli finished without a print"},
           :ok <- if(grey?(input), do: magick([made, "-colorspace", "Gray", made]), else: :ok) do
        File.rename!(made, output)
        :ok
      end
    after
      File.rm_rf(scratch)
    end
  end

  defp all_ok(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.find_value(:ok, fn line ->
      case Jason.decode(line) do
        {:ok, %{"ok" => false} = reply} -> {:error, "#{reply["command"]}: #{reply["error"]}"}
        _ -> nil
      end
    end)
  end

  defp run(args) do
    case System.find_executable(bin()) do
      nil ->
        {:error, "lightcraft-cli is not installed, or not on the server's PATH"}

      exe ->
        case System.cmd(exe, args, stderr_to_stdout: true) do
          {output, 0} -> {:ok, output}
          {output, status} -> {:error, "lightcraft-cli exited #{status}: #{last_line(output)}"}
        end
    end
  end

  @doc "A picture's `{width, height}` in pixels, or nil when it cannot be read."
  def dimensions(path) do
    case System.cmd(Negatives.magick_bin(), ["identify", "-format", "%w %h", path],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case output |> String.split() |> Enum.map(&Integer.parse/1) do
          [{w, ""}, {h, ""} | _] -> {w, h}
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc "Whether a picture is grey (a black and white print), by ImageMagick."
  def grey?(path) do
    case System.cmd(Negatives.magick_bin(), ["identify", "-format", "%[colorspace]", path],
           stderr_to_stdout: true
         ) do
      {"Gray" <> _, 0} -> true
      _ -> false
    end
  end

  defp magick(args) do
    case System.cmd(Negatives.magick_bin(), args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> {:error, "magick: #{last_line(output)}"}
    end
  end

  # The copies of a print the pages are served from are made again from the
  # new print. They are dated by the second, so a print saved in the same
  # second as its preview was made would otherwise keep the old preview.
  defp clear_previews(roll_dir, frame) do
    [roll_dir, "frames", "previews", "#{pad2(frame)}*.webp"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.each(&File.rm/1)

    Task.Supervisor.start_child(Web.TaskSupervisor, fn ->
      Negatives.warm_frame_previews(Path.basename(roll_dir))
    end)
  end

  defp last_line(output) do
    output |> String.split("\n", trim: true) |> List.last() |> to_string() |> String.slice(0, 300)
  end

  defp pad2(number), do: String.pad_leading(to_string(number), 2, "0")
end
