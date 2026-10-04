defmodule Web.ShareCard do
  @moduledoc """
  The picture a link unfurls with, when it is pasted into a message or a feed:
  one per post, frame and roll, made of the work itself.

  Every page used to share the site's logo, and the pages that did set their
  own image set a WebP — the preview the page loads — which several unfurlers
  will not show, and which a 1.91:1 crop cuts a portrait photograph in half
  through. A card is 1200x630, the shape they all crop to, so nothing is cut:

    * **A post** is its title, set in the site's own type on its own paper,
      over the wordmark and the date. An essay is known by its name.
    * **A frame** or **a roll** is the photograph or the sheet, whole, on the
      darkroom's ground with room around it.

  Captain's logs need none: their poster is already a 16:9 JPEG.

  **A page only names its card; asking for it is what draws it.** `post_url/1`,
  `frame_url/2` and `sheet_url/1` give the address for a page's `og:image`
  (`/share/…`, served by `WebWeb.ShareController`) and cost a file stat at
  most. ImageMagick runs when that address is first fetched — by an unfurler,
  which is the only thing that ever asks — so rendering a page never shells
  out, and a card nobody shares is never drawn.

  **Then it is a file.** `post/1`, `frame/2` and `sheet/1` return the card on
  disk, drawing it if it is not there. Cards are kept in `cards/` under the
  uploads root, named with a fingerprint of what they were made from — the
  title and date, or the source image's size and mtime. The address carries
  the same fingerprint as `?v=`, so a retitled post has a new address, the old
  file is swept away, and the year-long cache header on the response is
  honest.

  **Nothing depends on it.** With no ImageMagick, or a source it cannot read,
  the file functions answer `:error`, the controller answers 404, and an
  unfurler shows the link without a picture. A title reaches ImageMagick
  through a file (`caption:@path`), never as an argument, so one that starts
  with `@` or carries a `%` escape is set as text rather than interpreted.

  The two faces are vendored in `priv/fonts/` under the SIL Open Font License;
  the browser gets them from Google Fonts, but ImageMagick needs files.
  """

  require Logger

  alias Web.Keywords
  alias Web.Negatives
  alias Web.Uploads

  @subdir "cards"
  @size "1200x630"

  # The site's tokens (assets/css/app.css), as literals: ImageMagick does not
  # read CSS custom properties any more than a mail client does.
  @paper "#f3eee4"
  @ink "#17140f"
  @ink_3 "#7d7566"
  @accent "#a73b19"
  @rule "rgba(23,20,15,0.34)"
  @frame "rgba(23,20,15,0.22)"
  @darkroom "#0a0908"

  # --- Addresses, for a page's og:image ---------------------------------------

  @doc "The address of a post's card, or `nil` for a draft: nothing links to one."
  @spec post_url(map()) :: String.t() | nil
  def post_url(%{draft: true}), do: nil

  def post_url(%{slug: slug} = post) do
    "/share/post/#{URI.encode(slug, &URI.char_unreserved?/1)}.png?v=#{fingerprint(post_parts(post))}"
  end

  @doc "The address of a frame's card, or `nil` when there is no such print."
  @spec frame_url(String.t() | integer(), String.t() | integer()) :: String.t() | nil
  def frame_url(roll, frame) do
    with {:ok, print} <- Negatives.frame_path(roll, frame),
         {:ok, parts} <- file_parts(print) do
      "/share/frame/#{roll}/#{frame}.jpg?v=#{fingerprint(parts)}"
    else
      _ -> nil
    end
  end

  @doc "The address of a roll's card, or `nil` when its sheet is not on disk."
  @spec sheet_url(map()) :: String.t() | nil
  def sheet_url(%{filename: filename, roll: roll}) do
    with {:ok, sheet} <- Negatives.image_path(filename),
         {:ok, parts} <- file_parts(sheet) do
      "/share/roll/#{roll}.jpg?v=#{fingerprint(parts)}"
    else
      _ -> nil
    end
  end

  # --- Files, drawn on first asking -------------------------------------------

  @doc "A post's card on disk, drawn if need be. `:error` for a draft."
  @spec post(map()) :: {:ok, Path.t()} | :error
  def post(%{draft: true}), do: :error

  def post(%{slug: slug, title: title} = post) do
    [_title, stamp] = parts = post_parts(post)

    ensure(name("post", slug, parts, "png"), fn target ->
      with_title_file(title, fn title_file ->
        # One line per stroke of the drawing: the frame, the title, the rule,
        # then the wordmark and the date along the foot.
        [
          ~w(-size #{@size} xc:#{@paper}),
          ~w(-fill none -stroke #{@frame} -strokewidth 2 -draw),
          "rectangle 40,40 1159,589",
          # Paths are their own list elements, never inside a ~w: a space in
          # one would split it into two arguments.
          ~w[( -background none -fill #{@ink} -stroke none -font],
          goudy(),
          ~w(-size 1000x330 -gravity west),
          "caption:@" <> title_file,
          ")",
          ~w(-gravity northwest -geometry +100+110 -composite),
          ~w(-stroke #{@rule} -strokewidth 2 -draw),
          "line 100,480 1100,480",
          ~w(-stroke none -font),
          plex(),
          ~w(-pointsize 26),
          ~w(-fill #{@accent} -kerning 6 -gravity southwest -annotate +100+82 STREETSCISSORS),
          ~w(-fill #{@ink_3} -kerning 2 -gravity southeast -annotate +100+82),
          stamp,
          target
        ]
        |> List.flatten()
        |> magick()
      end)
    end)
  end

  @doc "A single frame's card: the print, whole, on the darkroom's ground."
  @spec frame(String.t() | integer(), String.t() | integer()) :: {:ok, Path.t()} | :error
  def frame(roll, frame) do
    # Fingerprinted by the print, drawn from its cached WebP preview: a card
    # is 1200 pixels wide, and the print is a scan of tens of megabytes that
    # takes seconds to open.
    with {:ok, print} <- Negatives.frame_path(roll, frame),
         {:ok, parts} <- file_parts(print),
         {:ok, source} <- Negatives.frame_preview_path(roll, frame) do
      photograph(name("frame", "#{roll}-#{frame}", parts, "jpg"), source)
    else
      _ -> :error
    end
  end

  @doc "A roll's card: its contact sheet, whole, on the darkroom's ground."
  @spec sheet(map()) :: {:ok, Path.t()} | :error
  def sheet(%{filename: filename, roll: roll}) do
    with {:ok, sheet} <- Negatives.image_path(filename),
         {:ok, parts} <- file_parts(sheet),
         {:ok, source} <- Negatives.preview_path(filename) do
      photograph(name("roll", to_string(roll), parts, "jpg"), source)
    else
      _ -> :error
    end
  end

  defp photograph(name, source) do
    ensure(name, fn target ->
      magick(
        [source] ++
          ~w(-auto-orient -resize 1120x550 -background #{@darkroom}) ++
          ~w(-gravity center -extent #{@size} -quality 86) ++ [target]
      )
    end)
  end

  # What a card is made from, and so what its fingerprint is taken over.
  defp post_parts(%{title: title, date: date}), do: [title, Calendar.strftime(date, "%-d %B %Y")]

  defp file_parts(path) do
    case File.stat(path) do
      {:ok, %{size: size, mtime: mtime}} -> {:ok, [Path.basename(path), size, mtime]}
      _ -> :error
    end
  end

  # --- Making and keeping ----------------------------------------------------

  # The card on disk, as it is or once `make` has put it there.
  defp ensure(name, make) do
    target = Path.join(dir(), name)

    cond do
      File.regular?(target) ->
        {:ok, target}

      make_card(target, make) ->
        sweep(name)
        {:ok, target}

      true ->
        :error
    end
  rescue
    error ->
      Logger.warning("share card #{name}: #{Exception.message(error)}")
      :error
  end

  # Drawn beside its name and renamed into place, so a request that arrives
  # mid-draw never serves half a picture under a one-year cache header.
  defp make_card(target, make) do
    File.mkdir_p!(dir())
    drawing = target <> ".drawing" <> Path.extname(target)

    with :ok <- make.(drawing),
         true <- File.regular?(drawing),
         :ok <- File.rename(drawing, target) do
      true
    else
      _ ->
        File.rm(drawing)
        false
    end
  end

  # Earlier cards for the same piece: a retitled post, a reprinted frame.
  defp sweep(name) do
    [_fingerprint | rest] = name |> Path.rootname() |> String.split("-") |> Enum.reverse()
    prefix = rest |> Enum.reverse() |> Enum.join("-")

    for file <- ls(dir()),
        file != name,
        Path.rootname(file) =~ ~r/^#{Regex.escape(prefix)}-[0-9a-f]{10}$/ do
      File.rm(Path.join(dir(), file))
    end
  end

  defp magick(args) do
    case System.cmd(Negatives.magick_bin(), args, stderr_to_stdout: true) do
      {_out, 0} ->
        :ok

      {out, code} ->
        Logger.warning("share card: magick exited #{code}: #{String.slice(out, 0, 300)}")
        :error
    end
  end

  defp with_title_file(title, fun) do
    path = Path.join(System.tmp_dir!(), "share-card-#{System.unique_integer([:positive])}.txt")
    File.write!(path, title)

    try do
      fun.(path)
    after
      File.rm(path)
    end
  end

  # `<kind>-<id>-<10 hex>.<ext>`: the id for a person reading the folder, the
  # fingerprint for the cache.
  defp name(kind, id, parts, ext) do
    "#{kind}-#{Keywords.slugify(to_string(id))}-#{fingerprint(parts)}.#{ext}"
  end

  defp fingerprint(parts) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(parts))
    |> Base.encode16(case: :lower)
    |> binary_part(0, 10)
  end

  defp goudy, do: Application.app_dir(:web, "priv/fonts/SortsMillGoudy-Regular.ttf")
  defp plex, do: Application.app_dir(:web, "priv/fonts/IBMPlexMono-Medium.ttf")
  defp dir, do: Uploads.dir(@subdir)

  defp ls(dir) do
    case File.ls(dir) do
      {:ok, files} -> files
      _ -> []
    end
  end
end
