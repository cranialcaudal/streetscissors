defmodule Web.Uploads do
  @moduledoc """
  Single source of truth for where uploaded media lives on disk.

  Both the writer (`Web.Media.Transcoder`) and the readers (Caddy in
  production, `WebWeb.Plugs.MediaServe` in dev) resolve through here, so the
  two can never drift. Configurable via `config :web, :uploads_path` — the test
  env points it at `tmp/` so a suite run never writes into `priv/static`.

  ## Layout

      uploads/
        staging/<token>.webm        a source, alive only until it transcodes
        logs/<slug>-<token>/        one directory per captain's log
          master.m3u8  v0/…  v1/…   an HLS ladder, for video
          audio.m4a                 a progressive rendition, for audio
          poster.jpg

  The `<token>` on an entry directory is what makes the files inside it
  immutable: a re-transcode writes a *new* directory and swaps the pointer on
  the row, so nothing served under a given path ever changes. That is what
  earns the one-year `cache-control` the media carries.
  """

  @default_root Path.join(["priv", "static", "uploads"])
  @logs_subdir "logs"
  @staging_subdir "staging"

  # An entry directory name is written by this module, but it reaches the
  # filesystem by way of a database column — so it is checked on the way back
  # out rather than trusted.
  @dir_name ~r/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/

  @doc "Absolute-or-relative root directory holding every upload."
  def root, do: Application.get_env(:web, :uploads_path, @default_root)

  @doc "Directory for one kind of upload, e.g. `dir(\"logs\")`."
  def dir(subdir), do: Path.join(root(), subdir)

  @doc "The public URL a stored file is served at."
  def web_path(subdir, filename), do: "/uploads/#{subdir}/#{filename}"

  @doc """
  A fresh entry-directory name for a log: its slug with a short random suffix.

  The suffix is not for uniqueness — the slug is already unique — but for
  cache safety, so a re-transcode of the same log never reuses a path a
  browser or proxy may still be holding.
  """
  def new_media_dir(slug) do
    "#{slug}-#{Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)}"
  end

  @doc "Absolute path to one log's media directory, or `:error` if the name is not one we wrote."
  def entry_dir(media_dir) when is_binary(media_dir) do
    if Regex.match?(@dir_name, media_dir) do
      {:ok, Path.join(dir(@logs_subdir), media_dir)}
    else
      :error
    end
  end

  def entry_dir(_media_dir), do: :error

  @doc "Same as `entry_dir/1`, raising rather than returning `:error`."
  def entry_dir!(media_dir) do
    case entry_dir(media_dir) do
      {:ok, path} -> path
      :error -> raise ArgumentError, "unsafe media_dir: #{inspect(media_dir)}"
    end
  end

  @doc """
  The public URL of a file inside one log's media directory.

      iex> Web.Uploads.entry_web_path("2026-09-18-a1b2c3d4", "master.m3u8")
      "/uploads/logs/2026-09-18-a1b2c3d4/master.m3u8"
  """
  def entry_web_path(media_dir, relative) do
    "/uploads/#{@logs_subdir}/#{media_dir}/#{relative}"
  end

  @doc "Creates and returns one log's media directory."
  def create_entry_dir!(media_dir) do
    path = entry_dir!(media_dir)
    File.mkdir_p!(path)
    path
  end

  @doc """
  Removes a log's media directory and everything in it.

  One `rm_rf` of a directory this module named, rather than a file-by-file
  dance over paths from the database — there is nothing inside an entry
  directory that does not belong to that entry.
  """
  def destroy_entry(nil), do: :ok

  def destroy_entry(media_dir) do
    case entry_dir(media_dir) do
      {:ok, path} ->
        File.rm_rf(path)
        :ok

      :error ->
        :ok
    end
  end

  @doc """
  Moves a consumed upload into staging and returns its path.

  Sources live here only until they transcode: the recording is trimmed and
  posterised on the way in, and the rendition is what the site keeps.
  """
  def stage_upload!(source_path, client_name) do
    ext =
      case client_name |> Path.extname() |> String.downcase() do
        "" -> ".bin"
        ext -> ext
      end

    dir = dir(@staging_subdir)
    File.mkdir_p!(dir)

    path =
      Path.join(dir, "#{Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)}#{ext}")

    # Across filesystems (LiveView's temp dir is often /tmp) a rename fails,
    # so fall back to a copy rather than losing the upload.
    case File.rename(source_path, path) do
      :ok -> path
      {:error, _} -> File.cp!(source_path, path) && path
    end
  end

  @doc "Deletes a staged source, if it is still there."
  def discard_staged(nil), do: :ok

  def discard_staged(path) do
    if String.starts_with?(path, dir(@staging_subdir) <> "/"), do: File.rm(path)
    :ok
  end
end
