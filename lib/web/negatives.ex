defmodule Web.Negatives do
  @moduledoc """
  Context for discovering and metadata-tagging analog film contact sheets.
  """

  require Logger

  @default_base_path "negatives"

  @doc """
  Root directory on disk where negative archives and contact sheets live.
  Configurable via `config :web, :negatives_path` (`NEGATIVES_PATH` at
  runtime); defaults to a `negatives` directory beside the checkout.
  """
  def base_path, do: Application.get_env(:web, :negatives_path) || Path.expand(@default_base_path)

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
  The ImageMagick binary, resolved through config the way `Web.Media.FFmpeg`
  resolves ffmpeg — so the suite can run against a stub instead of requiring
  ImageMagick on every machine that runs the tests.
  """
  def magick_bin, do: Application.get_env(:web, :magick_bin, "magick")

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

  # Narrower copies of a preview, by width in pixels, for the places a page
  # shows a photograph small: a strip of thumbnails 92 pixels tall was loading
  # a 2000-pixel image for each one. A width outside this list is not served —
  # the list is what stops `?w=` being a way to fill the disk one size at a time.
  @widths [480, 960]

  @doc "The widths a preview is also kept at, narrowest first."
  def widths, do: @widths

  @doc """
  A preview's address at one of `widths/0`: the same URL with `w=` added,
  whether or not it already carries a `?v=` of its own.
  """
  def sized_url(url, width) when width in @widths do
    url <> if(String.contains?(url, "?"), do: "&", else: "?") <> "w=#{width}"
  end

  @doc """
  An `srcset` offering a preview at every width it is kept at, so the browser
  takes the smallest that fills the space it has. The full preview is listed
  at its nominal #{@preview_max_dim} pixels.
  """
  def srcset(url) do
    @widths
    |> Enum.map(&"#{sized_url(url, &1)} #{&1}w")
    |> Kernel.++(["#{url} #{@preview_max_dim}w"])
    |> Enum.join(", ")
  end

  @doc """
  Resolves a downscaled WebP preview for a contact sheet, generating it on
  first request (or when the original has changed since). Falls back to the
  original image if generation fails, so previews degrade rather than 404.

  `width`, when it is one of `widths/0`, asks for the narrower copy instead;
  anything else is the full preview.
  """
  def preview_path(filename, width \\ nil) do
    with {:ok, original} <- image_path(filename) do
      preview = Path.join(previews_path(), Path.rootname(Path.basename(filename)) <> ".webp")

      cond do
        preview_fresh?(preview, original) -> {:ok, sized(preview, width)}
        generate_preview(original, preview) -> {:ok, sized(preview, width)}
        true -> {:ok, original}
      end
    end
  end

  # The narrower copy of a preview, made from the preview itself — a small
  # WebP, so this is quick — and kept beside it as `<name>-<width>.webp`.
  # Anything that goes wrong answers with the preview it was asked to shrink:
  # a picture that is larger than it needed to be is still the picture.
  defp sized(preview, width) when width in @widths do
    copy = Path.rootname(preview) <> "-#{width}.webp"

    cond do
      preview_fresh?(copy, preview) -> copy
      generate_preview(preview, copy, "#{width}x>") -> copy
      true -> preview
    end
  end

  defp sized(preview, _width), do: preview

  defp preview_fresh?(preview, original) do
    File.regular?(preview) and File.stat!(preview).mtime >= File.stat!(original).mtime
  end

  # `geometry` is ImageMagick's: the default fits the longest side, and a
  # sized copy passes `<width>x>` to fit the width alone. Both only shrink.
  defp generate_preview(
         original,
         preview,
         geometry \\ "#{@preview_max_dim}x#{@preview_max_dim}>"
       ) do
    File.mkdir_p!(Path.dirname(preview))
    # Temp file + rename so a concurrent request never reads a half-written preview
    tmp = "#{preview}.tmp-#{System.unique_integer([:positive])}.webp"

    args = [
      original,
      "-resize",
      geometry,
      "-quality",
      "#{@preview_quality}",
      tmp
    ]

    # System.cmd raises when the binary is missing, which would 500 a page that
    # promises to degrade to the original instead.
    try do
      case System.cmd(magick_bin(), args, stderr_to_stdout: true) do
        {_, 0} ->
          File.rename!(tmp, preview)
          true

        {output, _} ->
          File.rm(tmp)
          Logger.warning("contact sheet preview generation failed for #{original}: #{output}")
          false
      end
    rescue
      error ->
        File.rm(tmp)

        Logger.warning(
          "contact sheet preview generation failed for #{original}: #{Exception.message(error)}"
        )

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
  A roll's folder on disk, from a roll token ("roll012", "12", or a slug).

  The folder is looked up from catalog.csv only — never from user input — with
  `Path.safe_relative` as defence in depth. Public because
  `Web.Negatives.Sheet` needs the same guarded resolution.
  """
  def roll_dir(roll) do
    with {:ok, roll_num} <- parse_roll(roll) do
      roll_folder(roll_num)
    end
  end

  @doc """
  Where a roll's finished prints live.

  The scanning pipeline's own output directory: `negatives --scan-frames`
  rescans a stickered frame at high resolution and `film-develop develop`
  writes the developed result here as `NN.png`. The strip scans in the folder
  above are the raw material the contact sheet was assembled from, and are not
  published one by one — the sheet already shows every one of them.
  """
  def prints_dir(folder), do: Path.join(folder, "frames")

  @doc """
  Resolves an individual finished frame inside a roll's `frames/` directory.

  Roll and frame are digit tokens. Handles both naming conventions the
  pipeline produces (`NN.png` from `film-develop develop`, `frame-NN.png` from
  its `--export`).
  """
  def frame_path(roll, frame) do
    with {:ok, roll_num} <- parse_roll(roll),
         {:ok, frame_num} <- parse_frame(frame),
         {:ok, folder} <- roll_folder(roll_num) do
      find_frame_file(prints_dir(folder), frame_num)
    else
      _ -> :error
    end
  end

  @doc """
  Downscaled WebP preview of a finished print, generated on first request — a
  1200dpi scan is tens of megabytes and often a TIFF, so it is not what a page
  should load. Cached in a `previews/` subdir beside the prints; falls back to
  the original if generation fails. `width` asks for a narrower copy, as in
  `preview_path/2`.
  """
  def frame_preview_path(roll, frame, width \\ nil) do
    with {:ok, original} <- frame_path(roll, frame) do
      preview =
        original
        |> Path.dirname()
        |> Path.join("previews")
        |> Path.join(Path.rootname(Path.basename(original)) <> ".webp")

      cond do
        preview_fresh?(preview, original) -> {:ok, sized(preview, width)}
        generate_preview(original, preview) -> {:ok, sized(preview, width)}
        true -> {:ok, original}
      end
    end
  end

  @doc """
  Makes every copy of a roll's photographs the pages ask for (the preview and
  each narrower width), so the first visitor to a roll is not the one who
  waits for them. Quietly does nothing for a roll that is not listed yet.
  """
  def warm_frame_previews(roll) do
    for frame <- list_frames(roll), width <- [nil | @widths] do
      frame_preview_path(roll, frame.frame, width)
    end

    :ok
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
    if File.dir?(dir), do: scan_frame_files(dir, frame_num), else: :error
  end

  defp scan_frame_files(dir, frame_num) do
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
  The finished prints a roll has, as
  `[%{frame: 3, url: ..., original_url: ...}, ...]` ordered by frame number.

  This is the set of photographs from a roll that can actually be looked at,
  and therefore the set of frames that get circled on its contact sheet. Empty
  until a frame has been rescanned and developed — a roll folder full of strip
  scans does not imply any of them has been printed.

  Frame numbers are the roll's own, running 1..N across every exposure, as
  `frames.json` numbers them. They used to be the strip scans' file numbers,
  which meant "frame 3" of a 120 roll was its third *strip* of three exposures.
  """
  def list_frames(roll) do
    with {:ok, roll_num} <- parse_roll(roll),
         {:ok, folder} <- roll_folder(roll_num),
         dir <- prints_dir(folder),
         true <- File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.flat_map(fn file ->
        case Regex.run(@frame_exts, file) do
          [_, digits, _ext] ->
            frame = String.to_integer(digits)

            [
              %{
                frame: frame,
                url: "/negatives/frame/#{roll_num}/#{frame}",
                original_url: "/negatives/frame/#{roll_num}/#{frame}/original"
              }
            ]

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
      meta: Web.Negatives.RollMeta.read(Path.join(base_path(), folder)),
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
