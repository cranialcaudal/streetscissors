defmodule Web.NegativesFixtures do
  @moduledoc """
  A throwaway negatives archive on disk, for tests that read one.

  Several test files used to hand-roll the same tmp-directory-and-`put_env`
  dance; this is that, in one place. Everything here is invented — made-up roll
  numbers, made-up dates, strips of nothing — because the real archive is
  private and lives only on the author's machine. Checks against it belong in
  the gitignored `test/private/`.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @doc """
  A PNG of exactly `width` x `height`, as far as anything here can tell.

  Signature, a well-formed IHDR and an IEND — enough for
  `Web.Negatives.Sheet.dimensions/1`, which reads the header and nothing else,
  and enough to be recognisably a PNG rather than a text file pretending. It
  carries no image data, because nothing in the suite decodes one: the
  ImageMagick stub copies its input rather than reading it.
  """
  def png_bytes(width, height) do
    ihdr = <<width::32, height::32, 8, 0, 0, 0, 0>>

    <<137, "PNG", 13, 10, 26, 10>> <>
      chunk("IHDR", ihdr) <>
      chunk("IEND", "")
  end

  defp chunk(type, data) do
    <<byte_size(data)::32>> <> type <> data <> <<:erlang.crc32(type <> data)::32>>
  end

  @doc """
  Creates an empty archive in a tmp directory, points the app at it, and puts
  it back the way it was when the test ends. Returns the archive root.
  """
  def archive!(rows \\ []) do
    root =
      Path.join(
        System.tmp_dir!(),
        "negatives_fixture_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "Contact Sheets"))
    write_catalog!(root, rows)

    previous = Application.get_env(:web, :negatives_path)
    Application.put_env(:web, :negatives_path, root)

    on_exit(fn ->
      if previous do
        Application.put_env(:web, :negatives_path, previous)
      else
        Application.delete_env(:web, :negatives_path)
      end

      File.rm_rf(root)
    end)

    root
  end

  @doc """
  Adds a roll to `catalog.csv` and creates its folder. Returns the folder path.

  `opts` takes `:roll`, `:date`, `:format`, `:color` and `:frames`; the folder
  name follows the archive's own convention, which is what the layout rules are
  inferred from — a roll filed under "35mm Film" is laid out differently from
  one under "120 Film".
  """
  def put_roll!(root, opts \\ []) do
    roll = Keyword.get(opts, :roll, "001")
    date = Keyword.get(opts, :date, "2026-01-01")
    format = Keyword.get(opts, :format, "120")
    color = Keyword.get(opts, :color, "bw")
    frames = Keyword.get(opts, :frames, "4")

    slug = "roll#{roll}_#{date}_#{format}_#{color}"
    folder = "#{format} Film/#{slug}"
    File.mkdir_p!(Path.join(root, folder))

    append_catalog!(root, [roll, date, format, color, frames, folder])

    Path.join(root, folder)
  end

  @doc "Writes the assembled contact sheet for a roll slug, at a given size."
  def put_sheet!(root, slug, width, height) do
    path = Path.join([root, "Contact Sheets", "#{slug}.png"])
    File.write!(path, png_bytes(width, height))
    path
  end

  @doc """
  Writes a roll's strip scans and the `frames.json` that describes them.

  `strips` is a list of `{width, height, frames}`, where each frame is
  `{number, {x, y, w, h}}` in that strip's own pixels — the shape
  `negatives --analyze` produces. Files are named `001.tiff`, `002.tiff`, … in
  the order given, which is the order the assembler places them in.
  """
  def put_strips!(folder, strips) do
    described =
      strips
      |> Enum.with_index(1)
      |> Enum.map(fn {{width, height, frames}, index} ->
        file = String.pad_leading("#{index}", 3, "0") <> ".tiff"
        File.write!(Path.join(folder, file), "strip scan")

        %{
          "file" => file,
          "index" => index - 1,
          "width" => width,
          "height" => height,
          "axis" => "y",
          "frames" =>
            Enum.map(frames, fn {number, {x, y, w, h}} ->
              %{"frame" => number, "region" => [x, y, w, h], "well_exposed" => true}
            end)
        }
      end)

    write_analysis!(folder, described)
  end

  @doc "Writes a `frames.json` directly, for tests that need a malformed one."
  def write_analysis!(folder, strips) when is_list(strips) do
    body = Jason.encode!(%{"roll" => "001", "frames_per_strip" => 3, "strips" => strips})
    File.write!(Path.join(folder, "frames.json"), body)
  end

  def write_analysis!(folder, body) when is_binary(body) do
    File.write!(Path.join(folder, "frames.json"), body)
  end

  @doc """
  Puts a finished print in a roll's `frames/` directory.

  This is the thing that makes a frame viewable, and therefore the thing that
  gets it circled on the sheet — `film-develop develop` writes `NN.png` here.
  """
  def put_print!(folder, number, opts \\ []) do
    dir = Path.join(folder, "frames")
    File.mkdir_p!(dir)

    name =
      Keyword.get(opts, :name, String.pad_leading("#{number}", 2, "0") <> ".png")

    path = Path.join(dir, name)
    File.write!(path, png_bytes(1200, 1200))
    path
  end

  @doc """
  The golden roll: two 656x2152 strips of 120, side by side on 8x10 paper.

  Worked by hand from the assembler's rules — content is 1336 x 2152, both
  orientations fit without shrinking, and the tie sends the sheet portrait at
  2400 x 3000. The run centres at x=532 and each strip at y=424, so frame 1's
  region `{0, 0, 656, 700}` lands at `{532, 424, 656, 700}`. Returns the roll
  folder and its slug.
  """
  def golden_roll!(root) do
    folder = put_roll!(root, roll: "013", format: "120", frames: "2")

    put_strips!(folder, [
      {656, 2152, [{1, {0, 0, 656, 700}}, {2, {0, 726, 656, 700}}]},
      {656, 2152, [{3, {0, 0, 656, 700}}, {4, {0, 726, 656, 700}}]}
    ])

    slug = "roll013_2026-01-01_120_bw"
    put_sheet!(root, slug, 2400, 3000)

    {folder, slug}
  end

  defp write_catalog!(root, rows) do
    body =
      ["roll,scan_date,film_type,color,frames,folder" | Enum.map(rows, &Enum.join(&1, ","))]
      |> Enum.join("\n")

    File.write!(Path.join(root, "catalog.csv"), body <> "\n")
  end

  defp append_catalog!(root, row) do
    path = Path.join(root, "catalog.csv")
    File.write!(path, Enum.join(row, ",") <> "\n", [:append])
  end
end
