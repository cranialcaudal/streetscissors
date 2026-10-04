defmodule Web.Scanner.Pipeline do
  @moduledoc """
  From strip scans in a roll folder to a roll on `/negatives`: the folder
  itself, the analysis, the contact sheet, the two gates, and the catalog row.

  The analysis and the sheet are made by the same tools the `negatives`
  command uses — `film-develop` and `digital-contact-sheet-maker` — so a roll
  made here is the roll the command line would have made. **Nothing here
  stands in for them.** When one is missing or fails, that is what the caller
  is told: an invented `frames.json` would put the grease-pencil rings on
  `/negatives` in the wrong place, and a sheet composed some other way would
  not be the sheet the layout rules describe.

  A roll is published only once both gates pass, which is the same proof the
  public page asks for before it draws a ring.
  """

  alias Web.Negatives
  alias Web.Negatives.Sheet
  alias Web.Negatives.SheetLayout

  require Logger

  @doc """
  The next free roll number as a zero-padded 3-digit string (e.g. "031"): the
  lowest one claimed by neither `catalog.csv` nor a roll folder on disk.
  """
  def next_roll_number do
    catalog_rolls =
      case File.read(Negatives.catalog_path()) do
        {:ok, content} ->
          content
          |> String.split("\n", trim: true)
          |> Enum.drop(1)
          |> Enum.flat_map(fn line ->
            case String.split(line, ",") do
              [roll | _] ->
                case Integer.parse(String.trim(roll)) do
                  {n, _} -> [n]
                  _ -> []
                end

              _ ->
                []
            end
          end)

        _ ->
          []
      end

    disk_rolls =
      case File.ls(Negatives.base_path()) do
        {:ok, entries} ->
          entries
          |> Enum.filter(&File.dir?(Path.join(Negatives.base_path(), &1)))
          |> Enum.flat_map(fn sub ->
            sub_path = Path.join(Negatives.base_path(), sub)

            case File.ls(sub_path) do
              {:ok, folders} ->
                folders
                |> Enum.flat_map(fn folder ->
                  case Regex.run(~r/\Aroll0*(\d+)/i, folder) do
                    [_, num] -> [String.to_integer(num)]
                    _ -> []
                  end
                end)

              _ ->
                []
            end
          end)

        _ ->
          []
      end

    # The lowest number nothing claims, as `negatives` picks it — not one past
    # the highest, which a single high-numbered roll would send into four digits.
    used = MapSet.new(catalog_rolls ++ disk_rolls)
    next_num = Enum.find(Stream.iterate(1, &(&1 + 1)), &(not MapSet.member?(used, &1)))

    String.pad_leading(to_string(next_num), 3, "0")
  end

  @doc "Maps film format to directory name under negatives root."
  def format_dir_name("120"), do: "120 Film"
  def format_dir_name("35mm"), do: "35mm Film"
  def format_dir_name("620"), do: "620 Film"
  def format_dir_name("110"), do: "110 Film"
  def format_dir_name(other), do: "#{other} Film"

  @doc "Standard roll folder slug (e.g. roll031_2026-10-02_120_bw)."
  def roll_folder_name(roll_num, date, format, color) do
    padded = String.pad_leading(to_string(roll_num), 3, "0")
    "roll#{padded}_#{date}_#{format}_#{color}"
  end

  @doc "Full directory path on disk for a roll."
  def roll_dir(roll_num, date, format, color) do
    Path.join([
      Negatives.base_path(),
      format_dir_name(format),
      roll_folder_name(roll_num, date, format, color)
    ])
  end

  @doc "Prepares roll directories on disk, including frames/ subfolder."
  def prepare_roll(roll_num, date, format, color) do
    dir = roll_dir(roll_num, date, format, color)
    File.mkdir_p!(dir)
    File.mkdir_p!(Path.join(dir, "frames"))
    {:ok, dir}
  end

  @doc "Lists strip scan files currently inside a roll directory in sorted order."
  def list_strips(roll_dir) do
    if File.dir?(roll_dir) do
      case File.ls(roll_dir) do
        {:ok, files} ->
          files
          |> Enum.filter(fn file ->
            ext = Path.extname(file) |> String.downcase()
            ext in SheetLayout.strip_exts() and File.regular?(Path.join(roll_dir, file))
          end)
          |> Enum.sort()
          |> Enum.with_index(1)
          |> Enum.map(fn {file, idx} ->
            full_path = Path.join(roll_dir, file)
            stat = File.stat!(full_path)

            dims =
              case read_image_dimensions(full_path) do
                {:ok, {w, h}} -> "#{w} × #{h} px"
                _ -> "—"
              end

            %{
              index: idx,
              file: file,
              path: full_path,
              size: stat.size,
              dimensions: dims,
              mtime: NaiveDateTime.from_erl!(stat.mtime)
            }
          end)

        _ ->
          []
      end
    else
      []
    end
  end

  @doc """
  The name the next strip in a roll folder gets: `003.tiff` after two strips.
  `ext` is the scan's own extension, kept as it is.
  """
  def next_strip_name(roll_dir, ext \\ ".tiff") do
    index = length(list_strips(roll_dir)) + 1
    String.pad_leading(to_string(index), 3, "0") <> String.downcase(ext)
  end

  @doc """
  Adds an uploaded scan to a roll as its next strip, under its own extension —
  the file is copied, never converted, so what is archived is what the
  scanner wrote.
  """
  def add_strip(roll_dir, source_path, client_name) do
    ext = client_name |> Path.extname() |> String.downcase()

    if ext in SheetLayout.strip_exts() do
      File.mkdir_p!(roll_dir)
      name = next_strip_name(roll_dir, ext)
      File.cp!(source_path, Path.join(roll_dir, name))
      {:ok, name}
    else
      {:error, "#{client_name} is not a scan the assembler reads"}
    end
  end

  @doc "Rotates a strip scan by degrees (default 180), which makes any analysis of the roll stale."
  def rotate_strip(strip_path, degrees \\ 180) do
    args = [strip_path, "-rotate", to_string(degrees), strip_path]

    case System.cmd(Negatives.magick_bin(), args, stderr_to_stdout: true) do
      {_, 0} ->
        # The analysis measured the strip the other way up.
        File.rm(Path.join(Path.dirname(strip_path), "frames.json"))
        :ok

      {err, _} ->
        {:error, err}
    end
  end

  @doc """
  Renumbers a roll's strips into the order given, each keeping its own
  extension. The order of the files is the order of the sheet, so this also
  makes any analysis already written describe the wrong strips — it is
  removed, and Gate 1 fails until the roll is analysed again.
  """
  def reorder_strips(roll_dir, ordered_filenames) do
    # Through temporary names first, so no rename lands on a file still to move.
    prefix = ".reorder_#{System.unique_integer([:positive])}_"

    staged =
      ordered_filenames
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {name, index} ->
        from = Path.join(roll_dir, name)
        ext = name |> Path.extname() |> String.downcase()
        staged = Path.join(roll_dir, "#{prefix}#{index}#{ext}")

        if File.exists?(from) do
          File.rename!(from, staged)
          [{staged, String.pad_leading(to_string(index), 3, "0") <> ext}]
        else
          []
        end
      end)

    Enum.each(staged, fn {staged, name} -> File.rename!(staged, Path.join(roll_dir, name)) end)
    File.rm(Path.join(roll_dir, "frames.json"))

    :ok
  end

  @doc "Deletes a strip scan file from a roll directory and re-indexes remaining strips."
  def delete_strip(roll_dir, filename) do
    File.rm(Path.join(roll_dir, Path.basename(filename)))
    reorder_strips(roll_dir, Enum.map(list_strips(roll_dir), & &1.file))
  end

  @doc """
  Runs `film-develop analyze` over a roll, which finds the frames on each
  strip and writes `frames.json`. `{:ok, path}` or `{:error, what it said}`.
  """
  def generate_frames_analysis(roll_dir, _format, color) do
    path = Path.join(roll_dir, "frames.json")
    mode = if color == "color", do: "color", else: "bw"

    with :ok <- run(:film_develop_bin, "film-develop", ["analyze", "--mode", mode, roll_dir]) do
      if File.regular?(path),
        do: {:ok, path},
        else: {:error, "film-develop finished without writing frames.json"}
    end
  end

  @doc """
  Has `digital-contact-sheet-maker` assemble the roll's contact sheet into
  `Contact Sheets/<slug>.png`. `{:ok, path}` or `{:error, what it said}`.
  """
  def assemble_contact_sheet(roll_dir, roll_num, date, format, color) do
    sheet_dir = Negatives.contact_sheets_path()
    File.mkdir_p!(sheet_dir)

    slug = roll_folder_name(roll_num, date, format, color)
    sheet_path = Path.join(sheet_dir, "#{slug}.png")

    layout =
      case format do
        "35mm" -> "rows"
        format when format in ["120", "620"] -> "columns"
        _ -> "auto"
      end

    color_flag = if color == "color", do: "--color", else: "--bw"
    args = [roll_dir, "-o", sheet_path, "-p", "8x10", "-l", layout, color_flag]

    with :ok <- run(:contact_sheet_bin, "digital-contact-sheet-maker", args) do
      case Sheet.dimensions(sheet_path) do
        {:ok, _dims} -> {:ok, sheet_path}
        _ -> {:error, "the contact sheet maker finished without writing a readable sheet"}
      end
    end
  end

  @doc """
  The rectangle of a frame within its strip scan, in that scan's pixels, from
  `frames.json` — or nil when the roll has no analysis or no such frame.
  """
  def frame_region(roll_dir, frame) do
    with {:ok, strips} <- Sheet.read_analysis(roll_dir),
         %{region: region} <-
           strips |> Enum.flat_map(& &1.frames) |> Enum.find(&(&1.frame == frame)) do
      region
    else
      _ -> nil
    end
  end

  @doc "Where the raw high-resolution scan of a frame is kept: `raw-frames/frame-NN.tiff`."
  def keeper_raw_path(roll_dir, frame) do
    Path.join([roll_dir, "raw-frames", "frame-#{pad2(frame)}.tiff"])
  end

  @doc """
  Develops a raw frame scan into the print `/negatives` shows —
  `frames/NN.png` — with `film-develop develop`, led by the settings the
  roll's analysis found for its strip. The raw scan stays in `raw-frames/`,
  outside the folder the site serves, so a negative is never published as a
  photograph.
  """
  def develop_keeper(roll_dir, frame) do
    raw = keeper_raw_path(roll_dir, frame)
    print = Path.join([roll_dir, "frames", "#{pad2(frame)}.png"])
    args = ["develop", raw, "--roll", roll_dir, "--frame", to_string(frame)]

    with :ok <- run(:film_develop_bin, "film-develop", args) do
      if File.regular?(print),
        do: {:ok, print},
        else: {:error, "film-develop finished without writing #{Path.basename(print)}"}
    end
  end

  defp pad2(number), do: String.pad_leading(to_string(number), 2, "0")

  # One of the pipeline's own tools. Configurable so the suite can stand a
  # stub in for it; by default the bare name, found on PATH.
  defp run(key, default, args) do
    bin = Application.get_env(:web, key, default)

    case System.find_executable(bin) do
      nil ->
        {:error, "#{default} is not installed, or not on the server's PATH"}

      executable ->
        case System.cmd(executable, args, stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, status} -> {:error, "#{default} exited #{status}: #{last_lines(output)}"}
        end
    end
  end

  defp last_lines(output) do
    output |> String.split("\n", trim: true) |> Enum.take(-4) |> Enum.join(" — ")
  end

  @doc "Verifies Gate 1 and Gate 2 conformance for a roll."
  def verify_conformance(roll_dir, sheet_path) do
    gate_1_res = Sheet.verify_gate_1(roll_dir)
    gate_2_res = Sheet.verify_gate_2(roll_dir, sheet_path)

    frame_count =
      case gate_1_res do
        {:ok, strips} ->
          Enum.reduce(strips, 0, fn strip, acc -> acc + length(strip.frames) end)

        _ ->
          0
      end

    %{
      gate_1: gate_1_res,
      gate_2: gate_2_res,
      frames_count: frame_count,
      conforming?: match?({:ok, _}, gate_1_res) and match?({:ok, _}, gate_2_res)
    }
  end

  @doc """
  Publishes a roll: adds its row to `catalog.csv` and builds the sheet's
  preview. Refused with `{:error, :not_conforming}` unless both gates pass —
  the roll's own files are checked here, not taken on the caller's word.

  The catalog's `frames` column is the number of **strips**, as the
  `negatives` command writes it; exposures are counted from `frames.json`
  when the page needs them. A roll number already in the catalog is left as
  it is.
  """
  def publish_roll(roll_num, date, format, color) do
    slug = roll_folder_name(roll_num, date, format, color)
    dir = roll_dir(roll_num, date, format, color)
    sheet_path = Path.join(Negatives.contact_sheets_path(), "#{slug}.png")

    if verify_conformance(dir, sheet_path).conforming? do
      catalog_path = Negatives.catalog_path()
      File.mkdir_p!(Path.dirname(catalog_path))

      existing =
        case File.read(catalog_path) do
          {:ok, content} -> content
          _ -> "roll,scan_date,film_type,color,frames,folder\n"
        end

      padded = String.pad_leading(to_string(roll_num), 3, "0")
      strips = length(list_strips(dir))
      row = "#{padded},#{date},#{format},#{color},#{strips},#{format_dir_name(format)}/#{slug}\n"

      listed? =
        existing
        |> String.split("\n", trim: true)
        |> Enum.any?(&(&1 |> String.split(",") |> hd() |> String.trim() == padded))

      unless listed? do
        File.write!(catalog_path, String.trim_trailing(existing, "\n") <> "\n" <> row)
      end

      _ = Negatives.preview_path("#{slug}.png")

      {:ok, padded}
    else
      {:error, :not_conforming}
    end
  end

  # --- Internal Compositing & Geometry Helpers ------------------------------

  defp read_image_dimensions(path) do
    case System.cmd(Negatives.magick_bin(), ["identify", "-format", "%w %h", path],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case String.split(String.trim(output)) do
          [w, h] -> {:ok, {String.to_integer(w), String.to_integer(h)}}
          _ -> :error
        end

      _ ->
        :error
    end
  end
end
