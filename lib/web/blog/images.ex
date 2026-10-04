defmodule Web.Blog.Images do
  @moduledoc """
  The blog's image library: pictures uploaded from the admin to be embedded in
  posts with an ordinary markdown image link.

  **They live under the uploads root**, beside the captain's logs' media, and
  are served at `/uploads/images/<name>`. They used to be written into
  `priv/static/images/uploads` in the checkout — but a release carries its own
  copy of `priv/`, made when it was built, so an image uploaded to the running
  site was not served until the next deploy: the card offered markdown for an
  address that answered 404. The uploads root is read from disk on every
  request (Caddy in production, `WebWeb.Plugs.MediaServe` otherwise), is
  outside the release, and is on the drive's mirror (`Web.Backup.Uploads`).

  Images that went into the old folder are still listed, at the address they
  have always had, so a post that embeds one keeps working and the library
  still shows it. They cannot be deleted from here: the file the site serves
  is the release's copy, not the one in the checkout.

  A name is the uploaded file's own, slugified, with a number appended so two
  uploads of `scan.png` never collide and a path, once handed out, is never
  reused for a different picture — which is what makes the uploads root's
  one-year cache lifetime honest for these too.
  """

  alias Web.Keywords
  alias Web.Uploads

  @subdir "images"
  @legacy_dir Path.join(["priv", "static", "images", "uploads"])
  @exts ~w(.jpg .jpeg .png .gif .webp)

  @type image :: %{
          name: String.t(),
          path: String.t(),
          file: String.t(),
          mtime: tuple(),
          legacy: boolean()
        }

  @doc "The file extensions the library takes."
  def extensions, do: @exts

  @doc "Every image in the library, newest first."
  @spec list() :: [image()]
  def list do
    current =
      for name <- ls(dir()), image?(name) do
        entry(name, Uploads.web_path(@subdir, name), Path.join(dir(), name), false)
      end

    # The build's digested copies (`name-<hash>.png`) sit in the same folder
    # and are not the library's.
    legacy =
      for name <- ls(@legacy_dir), image?(name), not digested?(name) do
        entry(name, "/images/uploads/#{name}", Path.join(@legacy_dir, name), true)
      end

    Enum.sort_by(current ++ legacy, & &1.mtime, :desc)
  end

  @doc """
  Copies an uploaded file into the library under a name of its own and returns
  the address it is served at.
  """
  @spec store(Path.t(), String.t()) :: String.t()
  def store(source, client_name) do
    ext = client_name |> Path.extname() |> String.downcase()
    base = client_name |> Path.basename(Path.extname(client_name)) |> Keywords.slugify()
    name = "#{if base == "", do: "image", else: base}-#{System.unique_integer([:positive])}#{ext}"

    File.mkdir_p!(dir())
    File.cp!(source, Path.join(dir(), name))

    Uploads.web_path(@subdir, name)
  end

  @doc "Deletes a library image by name. Guards against directory traversal."
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(name) do
    case Path.safe_relative(name) do
      {:ok, safe} -> File.rm(Path.join(dir(), safe))
      :error -> {:error, :unsafe}
    end
  end

  defp dir, do: Uploads.dir(@subdir)

  defp entry(name, path, file, legacy) do
    %{name: name, path: path, file: file, mtime: File.stat!(file).mtime, legacy: legacy}
  end

  defp image?(name), do: String.downcase(Path.extname(name)) in @exts
  defp digested?(name), do: Regex.match?(~r/-[0-9a-f]{32}\.[^.]+$/, name)

  defp ls(dir) do
    case File.ls(dir) do
      {:ok, files} -> files
      _ -> []
    end
  end
end
