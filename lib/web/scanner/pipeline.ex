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

  @doc """
  The roll being worked on: the most recently touched roll folder that
  `catalog.csv` does not list yet, as `{number, date, format, color}`, or nil
  when every roll on disk is published (`:except` leaves one roll number out,
  for a roll that is being published at this moment). A reload of the studio, or a deploy
  under it, used to open the next free number, and the next scan then started
  a second roll of the same film.
  """
  def roll_in_progress(opts \\ []) do
    case unlisted(opts) |> Enum.max_by(&elem(&1, 0), fn -> nil end) do
      {_mtime, roll} -> roll
      nil -> nil
    end
  end

  @doc """
  Every roll on disk that `catalog.csv` does not list, oldest number first,
  as `{number, date, format, color}`; `:except` leaves one out (the roll on
  the bench). These are the rolls that wait for Publish.
  """
  def unpublished_rolls(opts \\ []) do
    unlisted(opts) |> Enum.map(&elem(&1, 1)) |> Enum.sort()
  end

  @doc "A roll analysed again by its folder alone (its name says the film)."
  def generate_frames_analysis_for(roll_dir) do
    case Regex.run(~r/_([a-z0-9]+)_(bw|color)\z/, Path.basename(roll_dir)) do
      [_, format, color] -> generate_frames_analysis(roll_dir, format, color)
      _ -> {:error, "not a roll folder"}
    end
  end

  defp unlisted(opts) do
    except = opts[:except] && String.to_integer(to_string(opts[:except]))

    listed =
      case File.read(Negatives.catalog_path()) do
        {:ok, content} ->
          content
          |> String.split("\n", trim: true)
          |> Enum.drop(1)
          |> Enum.flat_map(fn line ->
            case Integer.parse(line |> String.split(",") |> hd() |> String.trim()) do
              {number, _} -> [number]
              :error -> []
            end
          end)
          |> MapSet.new()

        _ ->
          MapSet.new()
      end

    Path.join(Negatives.base_path(), "* Film/roll*")
    |> Path.wildcard()
    |> Enum.flat_map(fn dir ->
      with true <- File.dir?(dir),
           [_, number, date, format, color] <-
             Regex.run(
               ~r/\Aroll(\d+)_(\d{4}-\d{2}-\d{2})_([a-z0-9]+)_(bw|color)\z/,
               Path.basename(dir)
             ),
           false <- MapSet.member?(listed, String.to_integer(number)),
           false <- String.to_integer(number) == except,
           {:ok, stat} <- File.stat(dir, time: :posix) do
        [{stat.mtime, {number, date, format, color}}]
      else
        _ -> []
      end
    end)
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

  @doc """
  Takes the strips out of one pass over the holder: `scan` is the whole
  transparency area at `dpi`, and `strips` where `Web.Scanner.Detect` found
  film on it (`%{left_mm, width_mm}`, left to right). Each becomes the roll's
  next strip, at the archive's 300 dpi, in grey for black and white film.
  `rows` is the holder's `{top_mm, height_mm}`, or nil for the whole height
  of the scan.

  Where each strip lies on the glass is written to the roll's `holder.json`,
  replacing what was there: it is true until the film is moved, and is what
  lets a chosen frame be scanned again without anyone placing it.

  `{:ok, [strip file names]}`, or `{:error, text}` with nothing left behind
  from the strip that failed.
  """
  def add_pass(roll_dir, scan, dpi, strips, color, rows \\ nil) do
    px = fn mm -> round(mm / 25.4 * dpi) end

    {top, tall} =
      case rows do
        {top, tall} ->
          {top, tall}

        _ ->
          case read_image_dimensions(scan) do
            {:ok, {_w, h}} -> {0.0, h / dpi * 25.4}
            _ -> {0.0, 0.0}
          end
      end

    grey = if color == "color", do: [], else: ["-colorspace", "Gray"]
    percent = :erlang.float_to_binary(300 / dpi * 100, decimals: 4) <> "%"

    result =
      strips
      |> Enum.sort_by(& &1.left_mm)
      |> Enum.reduce_while({:ok, []}, fn strip, {:ok, done} ->
        name = next_strip_name(roll_dir)
        target = Path.join(roll_dir, name)
        crop = "#{px.(strip.width_mm)}x#{px.(tall)}+#{px.(strip.left_mm)}+#{px.(top)}"

        args =
          [scan <> "[0]", "-alpha", "off", "-crop", crop, "+repage"] ++
            grey ++
            [
              "-resize",
              percent,
              "-units",
              "PixelsPerInch",
              "-density",
              "300",
              "tiff:" <> target <> ".partial"
            ]

        with {_, 0} <- System.cmd(Negatives.magick_bin(), args, stderr_to_stdout: true),
             :ok <- File.rename(target <> ".partial", target) do
          {:cont, {:ok, done ++ [{name, [strip.left_mm, top, strip.width_mm, tall]}]}}
        else
          failure ->
            File.rm(target <> ".partial")
            {:halt, {:error, "couldn't cut #{name} out of the scan: #{said(failure)}"}}
        end
      end)

    with {:ok, placed} <- result do
      File.write!(
        Path.join(roll_dir, "holder.json"),
        Jason.encode_to_iodata!(
          %{"pending" => true, "look" => look(scan), "strips" => Map.new(placed)},
          pretty: true
        )
      )

      # There is one sheet of glass: this look is now the only one that
      # describes it, whichever roll an earlier one belonged to.
      File.write!(glass_path(), look(scan))

      {:ok, Enum.map(placed, &elem(&1, 0))}
    end
  end

  defp said({output, _status}) when is_binary(output), do: last_lines(output)
  defp said(other), do: inspect(other)

  defp forget_holder(roll_dir), do: File.rm(Path.join(roll_dir, "holder.json"))

  @doc """
  Where the strips of the last pass lie on the glass, as
  `%{strip file => {left, top, width, height}}` in mm. Empty once a strip has
  been moved, turned or deleted, since the files no longer say where the film is.
  """
  def holder(roll_dir) do
    case holder_doc(roll_dir) do
      %{"strips" => strips} = doc when is_map(strips) ->
        if on_glass?(doc),
          do: for({file, [l, t, w, h]} <- strips, into: %{}, do: {file, {l, t, w, h}}),
          else: %{}

      _ ->
        %{}
    end
  end

  # Each look over the holder has a name (its scan's), kept with the strips it
  # found and, alone, in a file at the archive's root. A roll's record of the
  # glass holds only while it is that look's: the next look, into this roll or
  # any other, means the film has been changed. Roll 032 went on saying its
  # last strips were on the glass through the whole of roll 033.
  defp glass_path, do: Path.join(Negatives.base_path(), ".on-glass")

  defp look(scan), do: Path.basename(scan)

  defp on_glass?(doc) do
    case File.read(glass_path()) do
      {:ok, current} -> doc["look"] == String.trim(current)
      # No look has been recorded at all (an archive from before this): believe the roll.
      _ -> true
    end
  end

  defp holder_doc(roll_dir) do
    with {:ok, body} <- File.read(Path.join(roll_dir, "holder.json")),
         {:ok, %{} = doc} <- Jason.decode(body) do
      doc
    else
      _ -> nil
    end
  end

  @doc """
  The strips of a load that has been looked at and not yet settled, in order,
  or `[]`. A load is pending from the look that added its strips until its
  singles are scanned (or it is said to have none): until then another look
  at the holder is a second attempt at the same film, not more film.
  """
  def pending_load(roll_dir) do
    case holder_doc(roll_dir) do
      %{"pending" => true, "strips" => strips} when is_map(strips) ->
        strips |> Map.keys() |> Enum.sort()

      _ ->
        []
    end
  end

  @doc "Settles the pending load: its strips are the roll's. The glass is still as it was."
  def confirm_load(roll_dir) do
    case holder_doc(roll_dir) do
      %{"pending" => true} = doc ->
        File.write!(
          Path.join(roll_dir, "holder.json"),
          Jason.encode_to_iodata!(Map.put(doc, "pending", false), pretty: true)
        )

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Takes a pending load back out of the roll, for the look that replaces it:
  its strips, the record of where they lay, and the analysis that counted
  them. Only when they are the roll's last strips, which a pending load is
  unless something else has been at the folder; then nothing is touched and
  the load is settled instead, so no other strip is ever renumbered by this.
  """
  def discard_load(roll_dir) do
    pending = pending_load(roll_dir)
    files = Enum.map(list_strips(roll_dir), & &1.file)

    cond do
      pending == [] ->
        :ok

      Enum.take(files, -length(pending)) == pending ->
        Enum.each(pending, &File.rm(Path.join(roll_dir, &1)))
        forget_holder(roll_dir)
        File.rm(Path.join(roll_dir, "frames.json"))
        :ok

      true ->
        confirm_load(roll_dir)
    end
  end

  @doc """
  The rectangle a frame occupies on the glass, `{left, top, width, height}`
  in mm with `margin` around it, or nil when its strip is not known to be in
  the holder. The frame's rectangle in `frames.json` is in its 300 dpi
  strip's pixels.
  """
  def glass_rect(roll_dir, frame, margin) do
    with {:ok, strips} <- Sheet.read_analysis(roll_dir),
         %{file: file} = strip <-
           Enum.find(strips, fn strip -> Enum.any?(strip.frames, &(&1.frame == frame)) end),
         %{region: region} <- Enum.find(strip.frames, &(&1.frame == frame)),
         {_l, _t, _w, _h} = place <- Map.get(holder(roll_dir), file) do
      # A strip found again lying the other way up has its frames at the
      # other end of it.
      region =
        if flipped?(roll_dir, file) do
          {x, y, w, h} = region
          {strip.width - (x + w), strip.height - (y + h), w, h}
        else
          region
        end

      Web.Scanner.Driver.frame_area(place, region, margin)
    else
      _ -> nil
    end
  end

  defp flipped?(roll_dir, file) do
    case holder_doc(roll_dir) do
      %{"flipped" => files} when is_list(files) -> file in files
      _ -> false
    end
  end

  # How alike two signatures have to be, at their best offset, to be the same
  # film. Measured on the scanner on 2026-10-08, two strips against the twelve
  # of two rolls: the same film scored 1.00 and no other strip above 0.37.
  @same_film 0.6
  @signature_mm 0.5
  @signature_columns 8
  @reach_mm 45.0

  @doc """
  Finds this roll's strips on the glass again. `scan` is a look over the
  holder at `dpi` and `found` where `Web.Scanner.Detect` saw film on it; each
  piece of film is compared with every strip the roll already has, and one
  that is the same film is given its place on the glass back, in
  `holder.json`. Nothing is added to the roll.

  A strip laid back in the holder is never where it first was: a few
  millimetres along, in the other slot, or the other way up. So the
  comparison is of how dense the film is along its length (a strip's
  signature, whatever the slot), tried at every offset within reach and
  both ways up, and the offset that fits best is how far the strip has
  moved. That offset goes into the strip's place, and "the other way up"
  is kept beside it, so its frames are found where they now lie.

  `{:ok, [strip files found]}`, possibly empty, or `{:error, text}`.
  """
  def relocate(roll_dir, scan, dpi, found, rows \\ nil) do
    matches = scan |> seen_on_glass(dpi, found, rows) |> match_strips(roll_dir)
    settle_on_glass(roll_dir, scan, matches)
    {:ok, Enum.map(matches, &elem(&1, 0))}
  end

  @doc """
  Whose film is on the glass. The same comparison as `relocate/5`, made
  against every roll in `rolls` (maps with a `:dir`, as many more keys as the
  caller likes): the roll whose strips fit what was seen best is the answer,
  and its `holder.json` is written as `relocate/5` writes it.

  `rows` is `{top, tall}` in mm, or a function of a roll that gives it, since
  the holder's window differs by format.

  `{:ok, {roll, [strip files found]}}`, or `:none` when no roll has this film.
  """
  def identify(rolls, scan, dpi, found, rows \\ nil) do
    seen_for = fn roll ->
      seen_on_glass(scan, dpi, found, if(is_function(rows), do: rows.(roll), else: rows))
    end

    rolls
    |> Task.async_stream(
      fn roll ->
        matches = match_strips(seen_for.(roll), roll.dir)
        {roll, matches, matches |> Enum.map(&elem(&1, 3)) |> Enum.sum()}
      end,
      max_concurrency: System.schedulers_online(),
      timeout: 120_000
    )
    |> Enum.map(fn {:ok, result} -> result end)
    |> Enum.reject(fn {_roll, matches, _score} -> matches == [] end)
    |> Enum.max_by(&elem(&1, 2), fn -> nil end)
    |> case do
      nil ->
        :none

      {roll, matches, _score} ->
        settle_on_glass(roll.dir, scan, matches)
        {:ok, {roll, Enum.map(matches, &elem(&1, 0))}}
    end
  end

  # Each piece of film the look found, with its place on the glass and its
  # signature: `{piece, top, tall, signature}`.
  defp seen_on_glass(scan, dpi, found, rows) do
    px = fn mm -> round(mm / 25.4 * dpi) end

    {top, tall} =
      case rows do
        {top, tall} ->
          {top, tall}

        _ ->
          case read_image_dimensions(scan) do
            {:ok, {_w, h}} -> {0.0, h / dpi * 25.4}
            _ -> {0.0, 0.0}
          end
      end

    for piece <- Enum.sort_by(found, & &1.left_mm),
        crop = "#{px.(piece.width_mm)}x#{px.(tall)}+#{px.(piece.left_mm)}+#{px.(top)}",
        sig = signature(scan, crop, dpi),
        do: {piece, top, tall, sig}
  end

  # The roll's strips among what was seen: `{file, place, flipped?, score}`.
  defp match_strips(seen, roll_dir) do
    known =
      for strip <- list_strips(roll_dir),
          sig = signature(strip.path, nil, 300),
          do: {strip.file, sig}

    for {piece, top, tall, sig} <- seen,
        {file, flipped?, offset, score} <- [best_match(sig, known)],
        score >= @same_film do
      # The signature has a sample every @signature_mm of the strip.
      {file, [piece.left_mm, Float.round(top + offset * @signature_mm, 2), piece.width_mm, tall],
       flipped?, score}
    end
    |> Enum.uniq_by(&elem(&1, 0))
  end

  defp settle_on_glass(_roll_dir, _scan, []), do: :ok

  defp settle_on_glass(roll_dir, scan, matches) do
    File.write!(
      Path.join(roll_dir, "holder.json"),
      Jason.encode_to_iodata!(
        %{
          "pending" => false,
          "look" => look(scan),
          "strips" => Map.new(matches, fn {file, place, _, _} -> {file, place} end),
          "flipped" => for({file, _place, true, _} <- matches, do: file)
        },
        pretty: true
      )
    )

    File.write!(glass_path(), look(scan))
  end

  # A strip's signature: a small picture of it, eight values across and one
  # row every half millimetre along, each row with its own mean taken off.
  #
  # Taking the mean off is the point. How bright a strip is along its length
  # is mostly the gaps between frames and where the film ends, which every
  # strip of five frames shares: on that alone, strips of different rolls
  # scored 0.87 against each other. What is left after it is how the picture
  # varies across the film, which belongs to that picture only.
  #
  # `crop` cuts the strip out of a wider scan made at `dpi`; the archive's own
  # strips are whole files at 300. The film's edges are shaved off first.
  defp signature(path, crop, dpi) do
    with {:ok, {_w, h}} <- read_image_dimensions(path) do
      {h, cut} =
        case crop && Regex.run(~r/\A\d+x(\d+)\+/, crop) do
          [_, ch] -> {String.to_integer(ch), ["-crop", crop, "+repage"]}
          _ -> {h, []}
        end

      rows = max(round(h / dpi * 25.4 / @signature_mm), 8)

      case System.cmd(
             Negatives.magick_bin(),
             [path <> "[0]", "-alpha", "off"] ++
               cut ++
               [
                 "-colorspace",
                 "Gray",
                 "-shave",
                 "6%x0",
                 "-scale",
                 "#{@signature_columns}x#{rows}!",
                 "-depth",
                 "8",
                 "gray:-"
               ],
             stderr_to_stdout: false
           ) do
        {bytes, 0} when byte_size(bytes) >= @signature_columns * 8 ->
          for <<row::binary-size(@signature_columns) <- bytes>> do
            values = :binary.bin_to_list(row)
            mean = Enum.sum(values) / @signature_columns
            Enum.map(values, &(&1 - mean))
          end

        _ ->
          nil
      end
    else
      _ -> nil
    end
  end

  # The roll's strip most like what was seen: `{file, flipped?, offset in
  # rows, score}`. The offset is how far along the glass the strip's own
  # start now is from where the look's crop starts. A strip the other way up
  # is the same picture turned half round: rows in reverse, and each row too.
  defp best_match(_seen, []), do: nil

  defp best_match(seen, known) do
    reach = round(@reach_mm / @signature_mm)

    for {file, sig} <- known,
        {flipped?, sig} <- [
          {false, sig},
          {true, sig |> Enum.reverse() |> Enum.map(&Enum.reverse/1)}
        ],
        offset <- -reach..reach do
      {file, flipped?, offset, likeness(seen, sig, offset)}
    end
    |> Enum.max_by(&elem(&1, 3), fn -> nil end)
  end

  # Correlation of the two where they overlap, with `known` slid `offset`
  # rows along `seen`. Too little overlap is no evidence.
  defp likeness(seen, known, offset) do
    a = if offset > 0, do: Enum.drop(seen, offset), else: seen
    b = if offset < 0, do: Enum.drop(known, -offset), else: known

    {ab, aa, bb, rows} = correlate(a, b, 0.0, 0.0, 0.0, 0)

    if rows < 120 or aa <= 0 or bb <= 0, do: -1.0, else: ab / :math.sqrt(aa * bb)
  end

  defp correlate([row_a | rest_a], [row_b | rest_b], ab, aa, bb, rows) do
    {ab, aa, bb} = correlate_row(row_a, row_b, ab, aa, bb)
    correlate(rest_a, rest_b, ab, aa, bb, rows + 1)
  end

  defp correlate(_a, _b, ab, aa, bb, rows), do: {ab, aa, bb, rows}

  defp correlate_row([x | xs], [y | ys], ab, aa, bb),
    do: correlate_row(xs, ys, ab + x * y, aa + x * x, bb + y * y)

  defp correlate_row(_xs, _ys, ab, aa, bb), do: {ab, aa, bb}

  @doc """
  Cuts a frame out of a band scanned across the glass: `band` is the file,
  `band_rect` the rectangle it covers and `frame_rect` the frame's, both in
  mm on the glass, at `dpi`. The cut goes to `raw-frames/frame-NN.tiff`,
  where `develop_keeper/2` expects a frame's scan.
  """
  def cut_from_band(roll_dir, frame, band, {band_l, band_t, _, _}, {l, t, w, h}, dpi) do
    px = fn mm -> round(mm / 25.4 * dpi) end
    crop = "#{px.(w)}x#{px.(h)}+#{px.(l - band_l)}+#{px.(t - band_t)}"
    target = keeper_raw_path(roll_dir, frame)
    File.mkdir_p!(Path.dirname(target))

    # A strip lying the other way up than when it was first scanned gives its
    # frames upside down; they are turned back, so the print is as it would
    # have been.
    strip = with {file, _, _} <- frame_places(roll_dir)[frame], do: file
    turn = if is_binary(strip) and flipped?(roll_dir, strip), do: ["-rotate", "180"], else: []

    case System.cmd(
           Negatives.magick_bin(),
           [band <> "[0]", "-crop", crop, "+repage"] ++ turn ++ ["tiff:" <> target],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {output, _} -> {:error, "couldn't cut frame #{frame}: #{last_lines(output)}"}
    end
  end

  @doc """
  Turns a strip scan over (180° by default). The analysis measured it the
  other way up, so it is removed; the strip's place on the glass is forgotten
  (its frames no longer lie where the files say); and **its singles are
  carried with their frames**: the first frame of the strip is now its last,
  and each print is turned to match.
  """
  def rotate_strip(strip_path, degrees \\ 180) do
    roll_dir = Path.dirname(strip_path)
    file = Path.basename(strip_path)
    before = frame_places(roll_dir)
    args = [strip_path, "-rotate", to_string(degrees), strip_path]

    case System.cmd(Negatives.magick_bin(), args, stderr_to_stdout: true) do
      {_, 0} ->
        File.rm(Path.join(roll_dir, "frames.json"))
        forget_strip(roll_dir, file)

        carry_singles(roll_dir, before, fn
          {^file, index, count} -> {file, count - 1 - index, degrees}
          {strip, index, _count} -> {strip, index, 0}
        end)

        :ok

      {err, _} ->
        {:error, err}
    end
  end

  @doc """
  Renumbers a roll's strips into the order given, each keeping its own
  extension; a strip left out of the list is gone from the roll. The order of
  the files is the order of the sheet, so the analysis already written
  describes the wrong strips and is removed.

  **Singles are carried with their frames.** They are filed by frame number,
  and moving or removing a strip renumbers every frame after it, so each
  print, its raw scan and its entry in `selects.json` is moved to its frame's
  new number, and those of a removed strip are removed with it. That takes
  knowing the new numbers, so a roll that has singles is analysed again here;
  one that has none is left for its next analysis, as before. Where the
  strips lie on the glass is kept under their new names.
  """
  def reorder_strips(roll_dir, ordered_filenames) do
    before = frame_places(roll_dir)

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
          [{staged, String.pad_leading(to_string(index), 3, "0") <> ext, name}]
        else
          []
        end
      end)

    Enum.each(staged, fn {staged, name, _was} ->
      File.rename!(staged, Path.join(roll_dir, name))
    end)

    renamed = Map.new(staged, fn {_staged, name, was} -> {was, name} end)
    rename_holder(roll_dir, renamed)
    File.rm(Path.join(roll_dir, "frames.json"))

    carry_singles(roll_dir, before, fn {strip, index, _count} ->
      case renamed[strip] do
        nil -> nil
        name -> {name, index, 0}
      end
    end)

    :ok
  end

  @doc """
  Deletes a strip from a roll and renumbers the rest. Its singles go with it;
  the other strips' singles follow their frames to their new numbers.
  """
  def delete_strip(roll_dir, filename) do
    file = Path.basename(filename)
    File.rm(Path.join(roll_dir, file))
    reorder_strips(roll_dir, Enum.map(list_strips(roll_dir), & &1.file))
  end

  @doc """
  Begins a new roll at a strip: `from_file` and every strip after it leave
  this roll and become the first strips of the next free roll number, with
  the same date and film. For the holder that had the end of one roll and
  the start of the next on it, and only the author can say which strip that
  was.

  Everything of a moved strip goes with it: its singles, their raw scans and
  their entries in `selects.json`, under their frames' numbers in the new
  roll, and where the strip lies on the glass, still pending if its load
  was. The strips that stay keep their numbers, since only the tail moves.
  Both rolls are analysed again. `{:ok, {number, date, format, color}}` for
  the new roll, or `{:error, text}` with nothing moved.
  """
  def split_roll(roll_dir, from_file) do
    files = Enum.map(list_strips(roll_dir), & &1.file)
    at = Enum.find_index(files, &(&1 == from_file))

    with true <-
           (is_integer(at) and at > 0) or {:error, "a roll cannot begin at another's first strip"},
         [_, date, format, color] <-
           Regex.run(
             ~r/\Aroll\d+_(\d{4}-\d{2}-\d{2})_([a-z0-9]+)_(bw|color)\z/,
             Path.basename(roll_dir)
           ) ||
             {:error, "#{Path.basename(roll_dir)} does not say what film it is"} do
      before = frame_places(roll_dir)
      moving = Enum.drop(files, at)
      number = next_roll_number()
      {:ok, new_dir} = prepare_roll(number, date, format, color)

      renamed =
        moving
        |> Enum.with_index(1)
        |> Map.new(fn {file, index} ->
          name = String.pad_leading("#{index}", 3, "0") <> String.downcase(Path.extname(file))
          File.rename!(Path.join(roll_dir, file), Path.join(new_dir, name))
          {file, name}
        end)

      # The glass: each strip's place follows it.
      case holder_doc(roll_dir) do
        %{"strips" => strips} = doc when is_map(strips) ->
          {gone, kept} = Map.split(strips, moving)
          write_holder(roll_dir, doc, kept)

          write_holder(
            new_dir,
            doc,
            Map.new(gone, fn {file, place} -> {renamed[file], place} end)
          )

        _ ->
          :ok
      end

      File.rm(Path.join(roll_dir, "frames.json"))
      analyse_again(roll_dir)
      analyse_again(new_dir)

      new_numbers =
        Map.new(frame_places(new_dir), fn {frame, {strip, index, _}} ->
          {{strip, index}, frame}
        end)

      selects = read_selects(roll_dir)

      moved =
        for {frame, {strip, index, _count}} <- before,
            name = renamed[strip],
            new = new_numbers[{name, index}] do
          for {{dir, file}, {_, new_file}} <- Enum.zip(single_files(frame), single_files(new)),
              File.regular?(Path.join([roll_dir, dir, file])) do
            File.mkdir_p!(Path.join(new_dir, dir))
            File.rename!(Path.join([roll_dir, dir, file]), Path.join([new_dir, dir, new_file]))
          end

          clear_previews(roll_dir, frame)
          {frame, new, name}
        end

      carried =
        for {frame, new, name} <- moved, entry = selects[to_string(frame)], into: %{} do
          {to_string(new), Map.put(entry, "strip", name)}
        end

      # Frames of the moved strips that had no single still leave the old roll's record.
      gone = for {frame, {strip, _, _}} <- before, renamed[strip], do: to_string(frame)
      write_selects(Path.join(roll_dir, "selects.json"), Map.drop(selects, gone))
      if carried != %{}, do: write_selects(Path.join(new_dir, "selects.json"), carried)

      {:ok, {number, date, format, color}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Where each frame sits, by number: `%{frame => {strip file, place on the
  # strip from 0, frames on the strip}}`. Empty with no analysis.
  defp frame_places(roll_dir) do
    case frames_doc(roll_dir) do
      %{"strips" => strips} ->
        for %{"file" => file, "frames" => frames} <- strips,
            is_list(frames),
            {%{"frame" => number}, index} <- Enum.with_index(frames),
            into: %{} do
          {number, {file, index, length(frames)}}
        end

      _ ->
        %{}
    end
  end

  # Moves every single to its frame's new number. `to` says where a frame's
  # old place `{strip, index, count}` now is, as `{strip, index, quarter-turn
  # degrees for its print}`, or nil when the frame has left the roll.
  defp carry_singles(roll_dir, before, to) do
    selects = read_selects(roll_dir)

    kept =
      (printed_frames(roll_dir) ++ Enum.map(Map.keys(selects), &String.to_integer/1))
      |> Enum.uniq()
      |> Enum.filter(&Map.has_key?(before, &1))

    with [_ | _] <- kept,
         {:ok, _path} <- analyse_again(roll_dir) do
      after_places =
        Map.new(frame_places(roll_dir), fn {number, {strip, index, _}} ->
          {{strip, index}, number}
        end)

      tag = ".carry_#{System.unique_integer([:positive])}_"

      moves =
        for number <- kept do
          target =
            case to.(before[number]) do
              {strip, index, turn} -> {after_places[{strip, index}], strip, turn}
              nil -> {nil, nil, 0}
            end

          {number, target}
        end

      # Every file aside first, then each to its new name, so two frames
      # swapping numbers do not land on one another.
      for {number, _target} <- moves, {dir, name} <- single_files(number) do
        path = Path.join([roll_dir, dir, name])
        if File.regular?(path), do: File.rename!(path, Path.join([roll_dir, dir, tag <> name]))
      end

      for {number, _} <- moves, do: clear_previews(roll_dir, number)

      for {number, {new, _strip, turn}} <- moves,
          {{dir, name}, {_, new_name}} <- Enum.zip(single_files(number), single_files(new || 0)) do
        aside = Path.join([roll_dir, dir, tag <> name])

        cond do
          not File.regular?(aside) ->
            :ok

          new == nil ->
            File.rm(aside)

          true ->
            target = Path.join([roll_dir, dir, new_name])
            File.rename!(aside, target)
            if dir == "frames", do: turn_file(target, turn)
        end
      end

      carried =
        for {number, {new, strip, _turn}} <- moves,
            new != nil,
            entry = selects[to_string(number)],
            into: %{} do
          {to_string(new), Map.put(entry, "strip", strip)}
        end

      untouched = Map.drop(selects, Enum.map(kept, &to_string/1))
      write_selects(Path.join(roll_dir, "selects.json"), Map.merge(untouched, carried))
      :ok
    else
      [] -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp single_files(number) do
    name = pad2(number)
    [{"frames", "#{name}.png"}, {"raw-frames", "frame-#{name}.tiff"}]
  end

  defp clear_previews(roll_dir, number) do
    [roll_dir, "frames", "previews", "#{pad2(number)}*.webp"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.each(&File.rm/1)
  end

  # A roll's format and film are in its folder's name.
  defp analyse_again(roll_dir) do
    case Regex.run(~r/_([a-z0-9]+)_(bw|color)\z/, Path.basename(roll_dir)) do
      [_, format, color] -> generate_frames_analysis(roll_dir, format, color)
      _ -> {:error, "#{Path.basename(roll_dir)} does not say what film it is"}
    end
  end

  # The strips on the glass, under the names a reorder gave them. One that
  # left the roll is dropped.
  defp rename_holder(roll_dir, renamed) do
    case holder_doc(roll_dir) do
      %{"strips" => strips} = doc when is_map(strips) ->
        kept = for {file, place} <- strips, name = renamed[file], into: %{}, do: {name, place}
        write_holder(roll_dir, doc, kept)

      _ ->
        :ok
    end
  end

  # One strip is no longer where the files say; the others are.
  defp forget_strip(roll_dir, file) do
    case holder_doc(roll_dir) do
      %{"strips" => strips} = doc when is_map(strips) ->
        write_holder(roll_dir, doc, Map.delete(strips, file))

      _ ->
        :ok
    end
  end

  defp write_holder(roll_dir, _doc, strips) when map_size(strips) == 0,
    do: forget_holder(roll_dir)

  defp write_holder(roll_dir, doc, strips) do
    File.write!(
      Path.join(roll_dir, "holder.json"),
      Jason.encode_to_iodata!(Map.put(doc, "strips", strips), pretty: true)
    )
  end

  @doc """
  Whether the roll's analysis found reversal film (`film-develop` decides
  that by looking; the page only knows colour from black and white). A roll
  not yet analysed is not one.
  """
  def slide?(roll_dir) do
    with {:ok, body} <- File.read(Path.join(roll_dir, "frames.json")),
         {:ok, %{"mode" => "slide"}} <- Jason.decode(body) do
      true
    else
      _ -> false
    end
  end

  @doc """
  Runs `film-develop analyze` over a roll, which finds the frames on each
  strip and writes `frames.json`. `{:ok, path}` or `{:error, what it said}`.

  35mm is cut on the film's own 38 mm grid, however many frames a strip
  holds, so there is nothing to tell the tool about it. 120 and 620 spacing
  belongs to the camera: there the tool cuts every strip of a roll into the
  same number of frames and exits 1 when that count runs a cut through the
  middle of a picture. It names the count that fits, and while the roll has
  no prints that count is taken and the analysis run again. Once a frame has
  been printed the count stays: changing it renumbers every frame after the
  first strip, and the prints are filed by number. A strip still split wrong
  after that is not an error here (the tool wrote `frames.json`, and says so
  in it); `frames/1` marks its frames.

  Options: `:export`, a folder for a small developed crop of each frame
  (`frame-NN.png`), which is how the studio shows what it found.
  """
  def generate_frames_analysis(roll_dir, _format, color, opts \\ []) do
    path = Path.join(roll_dir, "frames.json")
    mode = if color == "color", do: "color", else: "bw"

    export =
      case opts[:export] do
        dir when is_binary(dir) -> ["--export", dir]
        _ -> []
      end

    args = fn count -> ["analyze", "--mode", mode] ++ count ++ export ++ [roll_dir] end

    result =
      case tool(:film_develop_bin, "film-develop", args.([])) do
        {:ok, output, 1} ->
          case {mis_split(roll_dir), fitting_count(output), printed_frames(roll_dir)} do
            {[_ | _], count, []} when is_integer(count) ->
              tool(:film_develop_bin, "film-develop", args.(["--frames-per-strip", "#{count}"]))

            _ ->
              {:ok, output, 1}
          end

        other ->
          other
      end

    case result do
      {:error, reason} ->
        {:error, reason}

      {:ok, output, status} ->
        cond do
          status == 0 and File.regular?(path) -> {:ok, path}
          status == 0 -> {:error, "film-develop finished without writing frames.json"}
          status == 1 and mis_split(roll_dir) != [] -> {:ok, path}
          true -> {:error, "film-develop exited #{status}: #{last_lines(output)}"}
        end
    end
  end

  defp fitting_count(output) do
    case Regex.run(~r/Try --frames-per-strip (\d+)/, output) do
      [_, count] -> String.to_integer(count)
      _ -> nil
    end
  end

  defp frames_doc(roll_dir) do
    with {:ok, body} <- File.read(Path.join(roll_dir, "frames.json")),
         {:ok, %{"strips" => strips} = doc} when is_list(strips) <- Jason.decode(body) do
      doc
    else
      _ -> nil
    end
  end

  # The strips the analysis itself says it could not cut into frames.
  defp mis_split(roll_dir) do
    case frames_doc(roll_dir) do
      %{"mis_split" => files} when is_list(files) -> files
      _ -> []
    end
  end

  @doc "The frames a roll has prints of (`frames/NN.png`), by number."
  def printed_frames(roll_dir) do
    case File.ls(Path.join(roll_dir, "frames")) do
      {:ok, files} ->
        files
        |> Enum.flat_map(fn file ->
          case Regex.run(~r/\A(\d+)\.png\z/, file) do
            [_, digits] -> [String.to_integer(digits)]
            _ -> []
          end
        end)
        |> Enum.sort()

      _ ->
        []
    end
  end

  @doc """
  Every frame the roll's analysis found, in order, as the studio needs them:
  `%{frame, strip, quality, well_exposed?, mis_split?, printed?}`. `quality`
  is the tool's 0..1 reading of how much tone the negative carries, or nil.
  Empty when the roll has not been analysed.
  """
  def frames(roll_dir) do
    case frames_doc(roll_dir) do
      nil ->
        []

      %{"strips" => strips} = doc ->
        wrong = List.wrap(doc["mis_split"])
        printed = MapSet.new(printed_frames(roll_dir))

        for %{"file" => file, "frames" => frames} <- strips,
            is_list(frames),
            %{"frame" => number} = frame <- frames,
            is_integer(number) do
          %{
            frame: number,
            strip: file,
            quality: if(is_number(frame["quality"]), do: frame["quality"]),
            well_exposed?: frame["well_exposed"] == true,
            mis_split?: file in wrong,
            printed?: MapSet.member?(printed, number)
          }
        end
        |> Enum.sort_by(& &1.frame)
    end
  end

  @doc """
  Whether the studio proposes a frame for an enhanced scan: the analysis calls
  it well exposed, it has no print yet, and its strip was cut into frames
  correctly. This judges the negative, not the picture.
  """
  def suggested?(%{well_exposed?: well, mis_split?: wrong, printed?: printed}) do
    well and not wrong and not printed
  end

  @doc """
  Writes down which of the `offered` frames were proposed and which were
  `chosen` (a list or set of frame numbers), in the roll's `selects.json`.
  The difference between the two is the only record of what the author
  actually wants printed, which is what a better proposal would be learned
  from. Earlier entries for other frames are kept.
  """
  def record_selects(roll_dir, offered, chosen) do
    path = Path.join(roll_dir, "selects.json")
    chosen = MapSet.new(chosen)
    at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    entries =
      Map.new(offered, fn frame ->
        {to_string(frame.frame),
         %{
           "strip" => frame.strip,
           "quality" => frame.quality,
           "suggested" => frame.well_exposed? and not frame.mis_split?,
           # A frame that has its print stays chosen when its strip is put
           # up again and other frames are picked from it.
           "chosen" => MapSet.member?(chosen, frame.frame) or Map.get(frame, :printed?, false),
           "at" => at
         }}
      end)

    # Entry by entry, so a frame's turn (`set_rotation/3`) outlives a new choice.
    frames =
      Map.merge(read_selects(roll_dir), entries, fn _frame, was, now -> Map.merge(was, now) end)

    write_selects(path, frames)
  end

  defp write_selects(path, frames) do
    partial = path <> ".partial"
    File.write!(partial, Jason.encode_to_iodata!(%{"frames" => frames}, pretty: true))
    File.rename!(partial, path)
    :ok
  end

  @doc """
  How far a frame is turned from the way it lies on its strip, in degrees
  clockwise (0, 90, 180 or 270): what the author set, else **landscape**. A
  strip laid along the holder puts a 35mm picture on its side, so a frame
  taller than it is wide is turned a quarter anticlockwise by default; which
  way is up cannot be read off the film, and one more press of the page's
  turn button is the answer when it is the other.
  """
  def rotation(roll_dir, frame) do
    case read_selects(roll_dir)[to_string(frame)] do
      %{"rotate" => degrees} when degrees in [0, 90, 180, 270] ->
        degrees

      _ ->
        case frame_region(roll_dir, frame) do
          {_x, _y, w, h} when h > w -> 270
          _ -> 0
        end
    end
  end

  @doc """
  Turns a frame a quarter clockwise from where it is and remembers it in
  `selects.json`. A print the frame already has is turned with it, which
  dates the previews made from it, so they are made again on the next request.
  Returns the new angle.
  """
  def turn_frame(roll_dir, frame) do
    degrees = rem(rotation(roll_dir, frame) + 90, 360)
    frames = read_selects(roll_dir)
    entry = Map.put(frames[to_string(frame)] || %{}, "rotate", degrees)
    write_selects(Path.join(roll_dir, "selects.json"), Map.put(frames, to_string(frame), entry))

    print = Path.join([roll_dir, "frames", "#{pad2(frame)}.png"])
    if File.regular?(print), do: turn_file(print, 90)

    degrees
  end

  @doc """
  Takes a single back out of the collection: its print, the previews made
  from it and its raw scan. The frame stays on its strip and on the sheet,
  and `selects.json` records that it was not kept after all.
  """
  def remove_print(roll_dir, frame) do
    name = pad2(frame)
    File.rm(Path.join([roll_dir, "frames", "#{name}.png"]))
    File.rm(keeper_raw_path(roll_dir, frame))

    clear_previews(roll_dir, frame)

    frames = read_selects(roll_dir)

    case frames[to_string(frame)] do
      %{} = entry ->
        entry = Map.merge(entry, %{"chosen" => false, "removed" => true})

        write_selects(
          Path.join(roll_dir, "selects.json"),
          Map.put(frames, to_string(frame), entry)
        )

      _ ->
        :ok
    end
  end

  defp turn_file(_path, 0), do: :ok

  defp turn_file(path, degrees) do
    case System.cmd(Negatives.magick_bin(), [path, "-rotate", "#{degrees}", path],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {output, _} -> {:error, "couldn't turn #{Path.basename(path)}: #{last_lines(output)}"}
    end
  end

  @doc """
  Singles that were chosen and never made: frames `selects.json` records as
  chosen that have no print. The choosing is written down before the scanner
  starts, so a run cut short (the page closed, the service restarted) leaves
  exactly this behind. Each as `%{frame, strip, on_glass?}`; `on_glass?` says
  whether its strip is still where the last look left it, which is whether
  the scan can simply be run again.
  """
  def owed_singles(roll_dir) do
    printed = MapSet.new(printed_frames(roll_dir))
    places = frame_places(roll_dir)
    glass = holder(roll_dir)

    for {key, %{"chosen" => true}} <- read_selects(roll_dir),
        {frame, ""} <- [Integer.parse(key)],
        not MapSet.member?(printed, frame),
        {strip, _index, _count} <- [places[frame]] do
      %{frame: frame, strip: strip, on_glass?: Map.has_key?(glass, strip)}
    end
    |> Enum.sort_by(& &1.frame)
  end

  @doc "The roll's recorded selections, by frame number as a string."
  def read_selects(roll_dir) do
    with {:ok, body} <- File.read(Path.join(roll_dir, "selects.json")),
         {:ok, %{"frames" => frames}} when is_map(frames) <- Jason.decode(body) do
      frames
    else
      _ -> %{}
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

    with :ok <- run(:film_develop_bin, "film-develop", args),
         true <-
           File.regular?(print) or
             {:error, "film-develop finished without writing #{Path.basename(print)}"},
         :ok <- turn_file(print, rotation(roll_dir, frame)) do
      warm_previews(roll_dir)
      {:ok, print}
    end
  end

  # The copies the site serves are made now, off to the side, and not when
  # someone first opens the roll. Nothing to do for a roll not yet listed.
  defp warm_previews(roll_dir) do
    Task.start(fn -> Negatives.warm_frame_previews(Path.basename(roll_dir)) end)
    :ok
  end

  defp pad2(number), do: String.pad_leading(to_string(number), 2, "0")

  # One of the pipeline's own tools. Configurable so the suite can stand a
  # stub in for it; by default the bare name, found on PATH.
  defp run(key, default, args) do
    case tool(key, default, args) do
      {:ok, _output, 0} -> :ok
      {:ok, output, status} -> {:error, "#{default} exited #{status}: #{last_lines(output)}"}
      {:error, reason} -> {:error, reason}
    end
  end

  # The same, for a caller that has to read what the tool said.
  defp tool(key, default, args) do
    bin = Application.get_env(:web, key, default)

    case System.find_executable(bin) do
      nil ->
        {:error, "#{default} is not installed, or not on the server's PATH"}

      executable ->
        {output, status} = System.cmd(executable, args, stderr_to_stdout: true)
        {:ok, output, status}
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
  Everything between the last strip and the roll being on `/negatives`, in
  one go: the analysis if the roll has none, the contact sheet, both gates,
  the catalog row. `{:ok, roll number}`, or `{:error, step, text}` naming the
  step that stopped it (`:analysis`, `:sheet` or `:gates`), with nothing
  published. A load still pending is settled first: its strips are the roll's.
  """
  def finish_roll(roll_num, date, format, color) do
    dir = roll_dir(roll_num, date, format, color)
    slug = roll_folder_name(roll_num, date, format, color)
    sheet_path = Path.join(Negatives.contact_sheets_path(), "#{slug}.png")
    confirm_load(dir)

    with {:strips, [_ | _]} <- {:strips, list_strips(dir)},
         {:analysis, {:ok, _}} <- {:analysis, analysed(dir, format, color)},
         {:sheet, {:ok, _}} <-
           {:sheet, assemble_contact_sheet(dir, roll_num, date, format, color)},
         {:gates, %{conforming?: true}} <- {:gates, verify_conformance(dir, sheet_path)},
         {:ok, published} <- publish_roll(roll_num, date, format, color) do
      warm_previews(roll_dir(roll_num, date, format, color))
      {:ok, published}
    else
      {:strips, []} ->
        {:error, :strips, "the roll has no strips yet"}

      {step, {:error, reason}} ->
        {:error, step, reason}

      {:gates, checks} ->
        {:error, :gates, gates_line(checks)}

      {:error, :not_conforming} ->
        {:error, :gates, "the roll did not pass both checks"}
    end
  end

  defp analysed(dir, format, color) do
    path = Path.join(dir, "frames.json")

    if File.regular?(path),
      do: {:ok, path},
      else: generate_frames_analysis(dir, format, color)
  end

  defp gates_line(%{gate_1: gate_1, gate_2: gate_2}) do
    [
      match?({:ok, _}, gate_1) || "the strip files are not the ones the analysis describes",
      match?({:ok, _}, gate_2) || "the sheet is not the size those strips compose to"
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.join("; ")
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
