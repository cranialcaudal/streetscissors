defmodule Web.Negatives do
  @moduledoc """
  Context for discovering and metadata-tagging analog film contact sheets.
  """

  require Logger

  @default_base_path "/home/cesar/Pictures/Negatives"

  @doc """
  Root directory on disk where negative archives and contact sheets live.
  Configurable via `config :web, :negatives_path`.
  """
  def base_path, do: Application.get_env(:web, :negatives_path, @default_base_path)

  def contact_sheets_path do
    Path.join(base_path(), "Contact Sheets")
  end

  def previews_path do
    Path.join(contact_sheets_path(), "previews")
  end

  def catalog_path do
    Path.join(base_path(), "catalog.csv")
  end

  @doc """
  Resolves a contact sheet image path safely guarding against directory traversal.
  """
  def image_path(filename) do
    with ext <- Path.extname(filename) |> String.downcase(),
         true <- ext in [".png", ".jpg", ".jpeg", ".webp", ".tif", ".tiff"],
         {:ok, rel} <- Path.safe_relative(filename) do
      path = Path.join(contact_sheets_path(), rel)
      if File.regular?(path), do: {:ok, path}, else: :error
    else
      _ -> :error
    end
  end

  @preview_max_dim 2000
  @preview_quality 82

  @doc """
  Resolves a downscaled WebP preview for a contact sheet, generating it on
  first request (or when the original has changed since). Falls back to the
  original image if generation fails, so previews degrade rather than 404.
  """
  def preview_path(filename) do
    with {:ok, original} <- image_path(filename) do
      preview = Path.join(previews_path(), Path.rootname(Path.basename(filename)) <> ".webp")

      cond do
        preview_fresh?(preview, original) -> {:ok, preview}
        generate_preview(original, preview) -> {:ok, preview}
        true -> {:ok, original}
      end
    end
  end

  defp preview_fresh?(preview, original) do
    File.regular?(preview) and File.stat!(preview).mtime >= File.stat!(original).mtime
  end

  defp generate_preview(original, preview) do
    File.mkdir_p!(Path.dirname(preview))
    # Temp file + rename so a concurrent request never reads a half-written preview
    tmp = "#{preview}.tmp-#{System.unique_integer([:positive])}.webp"

    args = [
      original,
      "-resize",
      "#{@preview_max_dim}x#{@preview_max_dim}>",
      "-quality",
      "#{@preview_quality}",
      tmp
    ]

    case System.cmd("magick", args, stderr_to_stdout: true) do
      {_, 0} ->
        File.rename!(tmp, preview)
        true

      {output, _} ->
        File.rm(tmp)
        Logger.warning("contact sheet preview generation failed for #{original}: #{output}")
        false
    end
  end

  @frame_exts ~r/(\d+)\.(tiff?|png|jpe?g|webp)\z/i

  @doc """
  Finds the contact sheet filename for a roll token ("roll012", "12", or a
  full sheet slug). Returns `{:ok, filename} | :error`.
  """
  def sheet_for_roll(roll) do
    with {:ok, num} <- parse_roll(roll),
         true <- File.exists?(contact_sheets_path()) do
      contact_sheets_path()
      |> File.ls!()
      |> Enum.filter(fn file ->
        Path.extname(file) |> String.downcase() |> Kernel.in([".png", ".jpg", ".jpeg", ".webp"])
      end)
      |> Enum.find(&Regex.match?(~r/\Aroll0*#{num}_/, &1))
      |> case do
        nil -> :error
        filename -> {:ok, filename}
      end
    else
      _ -> :error
    end
  end

  @doc """
  Resolves an individual frame scan inside a roll folder. Roll and frame
  are digit tokens; the folder is looked up from catalog.csv only (never
  user input), with `Path.safe_relative` as defense-in-depth. Handles both
  frame naming conventions on disk (`<roll-slug>_NN.tiff` and `NNN.tiff`).
  """
  def frame_path(roll, frame) do
    with {:ok, roll_num} <- parse_roll(roll),
         {:ok, frame_num} <- parse_frame(frame),
         {:ok, folder} <- roll_folder(roll_num) do
      find_frame_file(folder, frame_num)
    else
      _ -> :error
    end
  end

  @doc """
  Downscaled WebP preview for an individual frame, generated on first
  request (the TIFF originals are not browser-renderable). Cached in a
  `previews/` subdir of the roll folder; falls back to the original if
  generation fails.
  """
  def frame_preview_path(roll, frame) do
    with {:ok, original} <- frame_path(roll, frame) do
      preview =
        original
        |> Path.dirname()
        |> Path.join("previews")
        |> Path.join(Path.rootname(Path.basename(original)) <> ".webp")

      cond do
        preview_fresh?(preview, original) -> {:ok, preview}
        generate_preview(original, preview) -> {:ok, preview}
        true -> {:ok, original}
      end
    end
  end

  defp parse_roll(token) do
    case Regex.run(~r/\A(?:roll)?0*(\d{1,4})(?:_[\w-]*)?\z/i, to_string(token)) do
      [_, num] -> {:ok, num}
      _ -> :error
    end
  end

  defp parse_frame(token) do
    case Regex.run(~r/\A0*(\d{1,4})\z/, to_string(token)) do
      [_, num] -> {:ok, String.to_integer(num)}
      _ -> :error
    end
  end

  defp roll_folder(num) do
    case Map.get(load_catalog(), num) do
      %{folder: folder} when is_binary(folder) and folder != "" ->
        case Path.safe_relative(folder) do
          {:ok, rel} ->
            path = Path.join(base_path(), rel)
            if File.dir?(path), do: {:ok, path}, else: :error

          :error ->
            :error
        end

      _ ->
        :error
    end
  end

  defp find_frame_file(dir, frame_num) do
    dir
    |> File.ls!()
    |> Enum.sort()
    |> Enum.find_value(:error, fn file ->
      case Regex.run(@frame_exts, file) do
        [_, digits, _ext] ->
          if String.to_integer(digits) == frame_num, do: {:ok, Path.join(dir, file)}

        _ ->
          nil
      end
    end)
  end

  @doc """
  Individual frame scans published inside a roll's folder, as
  `[%{frame: 3, url: "/negatives/frame/12/3"}, ...]` ordered by frame number.

  A roll folder holds the frames the contact sheet was made from, so this is
  what lets a single photograph point back at the sheet it came from: the
  frames are listed under their own sheet. Empty until frames are uploaded —
  the roll folder existing does not imply individual scans exist yet.
  """
  def list_frames(roll) do
    with {:ok, roll_num} <- parse_roll(roll),
         {:ok, folder} <- roll_folder(roll_num) do
      folder
      |> File.ls!()
      |> Enum.flat_map(fn file ->
        case Regex.run(@frame_exts, file) do
          [_, digits, _ext] ->
            frame = String.to_integer(digits)
            [%{frame: frame, url: "/negatives/frame/#{roll_num}/#{frame}"}]

          _ ->
            []
        end
      end)
      |> Enum.uniq_by(& &1.frame)
      |> Enum.sort_by(& &1.frame)
    else
      _ -> []
    end
  end

  @doc """
  Lists all contact sheets with catalog metadata.
  Can be filtered by format ("all", "120", "35mm", etc.) or color ("all", "bw", "color").
  """
  def list_contact_sheets(filter_format \\ "all", filter_color \\ "all") do
    catalog = load_catalog()
    path = contact_sheets_path()

    if File.exists?(path) do
      path
      |> File.ls!()
      |> Enum.filter(fn file ->
        ext = Path.extname(file) |> String.downcase()
        ext in [".png", ".jpg", ".jpeg", ".webp"] and not File.dir?(Path.join(path, file))
      end)
      |> Enum.map(&parse_sheet_file(&1, path, catalog))
      |> Enum.filter(fn sheet ->
        format_match? =
          filter_format == "all" or
            String.downcase(sheet.format) == String.downcase(filter_format)

        color_match? =
          filter_color == "all" or
            String.downcase(sheet.color) == String.downcase(filter_color)

        format_match? and color_match?
      end)
      |> Enum.sort_by(& &1.roll_num, :desc)
    else
      []
    end
  end

  @doc """
  Gets summary statistics of the film archive.
  """
  def get_stats do
    sheets = list_contact_sheets()
    total_rolls = length(sheets)

    total_frames =
      Enum.reduce(sheets, 0, fn sheet, acc ->
        case Integer.parse(to_string(sheet.frames)) do
          {n, _} -> acc + n
          :error -> acc
        end
      end)

    latest_date =
      case sheets do
        [first | _] -> first.date
        [] -> nil
      end

    %{
      total_rolls: total_rolls,
      total_frames: total_frames,
      latest_date: latest_date
    }
  end

  defp parse_sheet_file(filename, dir, catalog) do
    slug = Path.rootname(filename)
    full_path = Path.join(dir, filename)
    stat = File.stat!(full_path)
    mtime = NaiveDateTime.from_erl!(stat.mtime)

    parts = String.split(slug, "_")

    roll_str =
      case parts do
        [roll_part | _] ->
          case Regex.run(~r/roll0*(\d+)/i, roll_part) do
            [_, num] -> num
            _ -> roll_part
          end

        _ ->
          "0"
      end

    roll_padded =
      case parts do
        [roll_part | _] ->
          case Regex.run(~r/roll(\d+)/i, roll_part) do
            [_, padded] -> padded
            _ -> roll_str
          end

        _ ->
          roll_str
      end

    roll_num =
      case Integer.parse(roll_str) do
        {n, _} -> n
        :error -> 0
      end

    cat_entry = Map.get(catalog, roll_padded) || Map.get(catalog, roll_str) || %{}

    date = cat_entry[:scan_date] || Enum.at(parts, 1, Calendar.strftime(mtime, "%Y-%m-%d"))
    format = cat_entry[:film_type] || Enum.at(parts, 2, "120")
    color = cat_entry[:color] || Enum.at(parts, 3, "bw")
    frames = cat_entry[:frames] || "?"
    folder = cat_entry[:folder] || "#{format} Film/#{slug}"

    %{
      id: "sheet-#{slug}",
      slug: slug,
      filename: filename,
      roll: roll_padded,
      roll_num: roll_num,
      date: date,
      format: format,
      color: color,
      frames: frames,
      folder: folder,
      image_url:
        "/negatives/image/#{filename}?v=#{NaiveDateTime.diff(mtime, ~N[1970-01-01 00:00:00])}",
      preview_url:
        "/negatives/preview/#{filename}?v=#{NaiveDateTime.diff(mtime, ~N[1970-01-01 00:00:00])}",
      mtime: mtime
    }
  end

  defp load_catalog do
    path = catalog_path()

    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.drop(1)
      |> Enum.reduce(%{}, fn line, acc ->
        case String.split(line, ",") do
          [roll, scan_date, film_type, color, frames, folder | _] ->
            roll_clean = String.trim(roll)

            entry = %{
              roll: roll_clean,
              scan_date: String.trim(scan_date),
              film_type: String.trim(film_type),
              color: String.trim(color),
              frames: String.trim(frames),
              folder: String.trim(folder)
            }

            acc
            |> Map.put(roll_clean, entry)
            |> Map.put(String.trim_leading(roll_clean, "0"), entry)

          _ ->
            acc
        end
      end)
    else
      %{}
    end
  end
end
