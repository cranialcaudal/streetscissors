defmodule Web.Cuts.Titles do
  @moduledoc """
  A title as a transparent 1280x720 PNG, for `Web.Cuts.Render` to lay over the
  picture. Set by ImageMagick in the site's own two faces (vendored in
  `priv/fonts/`, as the share cards are): `title` is Goudy across the middle
  with a soft shadow, wrapped to the frame; `lower` is the instrument voice
  along the foot on a dark band, in capitals. The words reach ImageMagick
  through a file (`caption:@`, `label:@`), never as an argument, so a title
  beginning with `@` or `-` is only words.
  """

  alias Web.Negatives

  def render(%{"text" => text, "style" => style}, path) do
    File.mkdir_p!(Path.dirname(path))
    words = path <> ".txt"
    File.write!(words, if(style == "lower", do: String.upcase(text), else: text))

    try do
      case System.cmd(Negatives.magick_bin(), args(style, words, path), stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, _} -> {:error, "magick could not set the title: #{String.slice(output, 0, 300)}"}
      end
    after
      File.rm(words)
    end
  end

  defp args("lower", words, path) do
    # +size: the canvas's size would otherwise be the label's too.
    ["-size", "1280x720", "xc:none", "-fill", "rgba(10,9,8,0.62)"] ++
      ["-draw", "rectangle 0,598 1280,674"] ++
      [
        "(",
        "+size",
        "-background",
        "none",
        "-fill",
        "#f3eee4",
        "-font",
        font("IBMPlexMono-Medium.ttf")
      ] ++
      ["-pointsize", "26", "-kerning", "2", "label:@" <> words, ")"] ++
      ["-gravity", "southwest", "-geometry", "+56+62", "-composite", "PNG32:" <> path]
  end

  defp args(_title, words, path) do
    ["-size", "1280x720", "xc:none"] ++
      ["(", "-size", "1120x", "-background", "none", "-fill", "#f3eee4"] ++
      ["-font", font("SortsMillGoudy-Regular.ttf"), "-pointsize", "72", "-gravity", "center"] ++
      ["caption:@" <> words] ++
      ["(", "+clone", "-background", "rgba(10,9,8,0.9)", "-shadow", "70x5+0+3", ")"] ++
      ["+swap", "-background", "none", "-layers", "merge", "+repage", ")"] ++
      ["-gravity", "center", "-composite", "PNG32:" <> path]
  end

  defp font(name), do: Application.app_dir(:web, Path.join("priv/fonts", name))
end
