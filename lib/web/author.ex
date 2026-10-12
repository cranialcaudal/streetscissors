defmodule Web.Author do
  @moduledoc """
  What the site says about the person who makes it, where the code needs to
  say it: the structured data on `/about`, the description a link to that
  page unfurls with, a profile linked from the homepage.

  None of it is the code's to know. It is read from `content/about.json`,
  beside `about.md` in the vault that git ignores, and every key is optional:

      {
        "job_title": "Researcher",
        "works_for": "A University",
        "description": "researcher, writer and photographer",
        "spotify_profile": "https://open.spotify.com/user/…"
      }

  The author's *name* is `AUTHOR_NAME` in the environment (`WebWeb.SEO`), as
  it was already. A clone with neither still builds, boots and renders: the
  pages simply say less.
  """

  @path "content/about.json"

  @doc "The file as a map of its string keys; empty when it is absent or unreadable."
  def profile do
    with {:ok, body} <- File.read(path()),
         {:ok, %{} = profile} <- Jason.decode(body) do
      profile
    else
      _ -> %{}
    end
  end

  @portraits "about"
  @every 4 * 60 * 60

  @doc """
  The pictures of the author the About page turns through: the image files in
  the `about` folder under the uploads root (`/uploads/about/…`, which the
  proxy serves), as web paths in order of name. Dropping a file in the folder
  adds it and taking one out removes it; nothing is deployed. Empty when the
  folder is absent, and the page then shows no picture.
  """
  def portraits do
    dir = Path.join(Web.Uploads.root(), @portraits)

    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&(String.downcase(Path.extname(&1)) in ~w(.jpg .jpeg .png .webp)))
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.sort()
        |> Enum.map(&Web.Uploads.web_path(@portraits, &1))

      _ ->
        []
    end
  end

  @doc """
  Take in a picture from wherever it was uploaded to: turned the way the
  camera held it, brought down to 1600 pixels on its longer side and kept as
  a JPEG, so a phone's ten-megabyte photograph does not go out to every
  reader. Named by the moment it came in, which keeps the pictures in the
  order they were added. `{:ok, web_path}` or `{:error, text}`. There is no
  limit to how many are kept.
  """
  def add_portrait(source) do
    dir = Path.join(Web.Uploads.root(), @portraits)
    File.mkdir_p!(dir)
    name = "#{System.os_time(:millisecond)}-#{:erlang.unique_integer([:positive])}.jpg"
    target = Path.join(dir, name)

    args = [
      source <> "[0]",
      "-auto-orient",
      "-resize",
      "1600x1600>",
      "-strip",
      "-quality",
      "84",
      target
    ]

    case System.cmd(Web.Negatives.magick_bin(), args, stderr_to_stdout: true) do
      {_, 0} ->
        {:ok, Web.Uploads.web_path(@portraits, name)}

      {said, _} ->
        {:error, "could not read that picture: #{String.slice(String.trim(said), 0, 160)}"}
    end
  rescue
    error in ErlangError -> {:error, "could not run ImageMagick: #{inspect(error.original)}"}
  end

  @doc """
  Take a picture out of the turn. It is set aside in the folder's `removed`
  subfolder, not destroyed. `web_path` is one of `portraits/0`.
  """
  def remove_portrait(web_path) do
    if web_path in portraits() do
      dir = Path.join(Web.Uploads.root(), @portraits)
      aside = Path.join(dir, "removed")
      File.mkdir_p!(aside)
      name = Path.basename(web_path)
      File.rename(Path.join(dir, name), Path.join(aside, name))
    else
      {:error, :not_found}
    end
  end

  @doc """
  The one shown now: the pictures take turns of four hours each, in order,
  the same for every visitor (the turn is counted from the clock, not from
  the visit). `{path, place, count}` or nil when there are none.
  """
  def portrait(now \\ System.os_time(:second)) do
    case portraits() do
      [] -> nil
      all -> turn(all, now)
    end
  end

  @doc false
  def turn(all, now) do
    at = rem(div(now, @every), length(all))
    {Enum.at(all, at), at + 1, length(all)}
  end

  @doc "One key of it, as trimmed text, or nil."
  def get(key) do
    case profile()[key] do
      value when is_binary(value) ->
        if String.trim(value) == "", do: nil, else: String.trim(value)

      _ ->
        nil
    end
  end

  @doc "A key that is a link: kept only when it is an https address."
  def link(key) do
    case get(key) do
      "https://" <> _ = url -> url
      _ -> nil
    end
  end

  defp path, do: Application.get_env(:web, :about_json_path, @path)
end
