defmodule Web.Fitness.Photos do
  @moduledoc """
  The training block's progress photographs: the most private files the
  site holds. They live in `fitness-photos/<YYYY-MM-DD>/` **beside** the
  uploads root, never under it (everything under it is served to anyone by
  the proxy), in folders of mode 0700 and files of 0600, and are served to
  the admin session alone (`WebWeb.FitnessPhotoController`). Nothing public
  lists them: no search, feed, daybook, share card or sitemap.

  Their backup is `Web.Backup.FitnessPhotos`: a nightly copy beside the
  database's snapshots and a mirror on the drive.

  Configure with `:fitness_photos_path`.
  """

  @exts ~w(.jpg .jpeg .png .webp)
  @file_name ~r/\A(?:[a-z0-9]+(?:-[a-z0-9]+)*-)?\d{2}\.(?:jpg|png|webp)\z/

  @doc "Where the photographs are kept."
  def dir do
    Application.get_env(:web, :fitness_photos_path) ||
      Web.Uploads.root() |> Path.expand() |> Path.dirname() |> Path.join("fitness-photos")
  end

  @doc "The file types taken, as `allow_upload/3` wants them."
  def accept, do: @exts

  @doc """
  Files a picture under a day, as the next number that day, after its pose
  when it has one (`front-01.jpg`, else `01.jpg`). `ext` is the upload's own
  extension; `.jpeg` is filed as `.jpg`. The poses are the block file's
  (`poses: front, side, back`): the same poses each time, which is what
  makes two photographs comparable whatever took them.
  """
  def store(date, source, ext, pose \\ nil)

  def store(%Date{} = date, source, ext, pose) do
    ext = ext |> String.downcase() |> then(&if(&1 == ".jpeg", do: ".jpg", else: &1))

    if ext in @exts do
      day = Path.join(dir(), Date.to_iso8601(date))

      with :ok <- mkdir_private(dir()),
           :ok <- mkdir_private(day) do
        n = (day |> File.ls!() |> length()) + 1
        prefix = if pose_ok?(pose), do: pose <> "-", else: ""
        name = prefix <> String.pad_leading(Integer.to_string(n), 2, "0") <> ext
        target = Path.join(day, name)

        with :ok <- File.cp(source, target), :ok <- File.chmod(target, 0o600) do
          {:ok, %{date: date, file: name}}
        end
      end
    else
      {:error, :type}
    end
  end

  @doc """
  Each pose's photographs, oldest first: `%{pose => [%{date, file}]}`, for
  the report's first-against-latest comparison. Files with no pose are left
  out.
  """
  def by_pose(poses) do
    entries =
      for %{date: date, files: files} <- list(), file <- files, do: %{date: date, file: file}

    Map.new(poses, fn pose ->
      {pose,
       entries
       |> Enum.filter(&String.starts_with?(&1.file, pose <> "-"))
       |> Enum.sort_by(&{Date.to_gregorian_days(&1.date), &1.file})}
    end)
  end

  defp pose_ok?(pose),
    do: is_binary(pose) and Regex.match?(~r/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/, pose)

  @doc "Every day with photographs, newest first: `[%{date, files}]`."
  def list do
    case File.ls(dir()) do
      {:ok, names} ->
        for name <- names,
            {:ok, date} <- [Date.from_iso8601(name)],
            files = name |> day_files(),
            files != [] do
          %{date: date, files: files}
        end
        |> Enum.sort_by(& &1.date, {:desc, Date})

      {:error, _} ->
        []
    end
  end

  @doc """
  A stored photograph's path from its address's parts, or `:error` for
  anything that is not one. The parts come from a URL, so both are matched
  whole before they are joined into a path.
  """
  def path(date, file) when is_binary(date) and is_binary(file) do
    with {:ok, _} <- Date.from_iso8601(date),
         true <- Regex.match?(@file_name, file),
         path = Path.join([dir(), date, file]),
         true <- File.regular?(path) do
      {:ok, path}
    else
      _ -> :error
    end
  end

  def path(_date, _file), do: :error

  @doc "Takes a photograph off the record, setting it aside rather than deleting it."
  def delete(date, file) do
    with {:ok, path} <- path(date, file) do
      aside = Path.join([dir(), ".trash", date])
      :ok = mkdir_private(Path.join(dir(), ".trash"))
      :ok = mkdir_private(aside)
      File.rename(path, Path.join(aside, "#{System.os_time(:second)}-#{file}"))
    end
  end

  defp day_files(name) do
    case File.ls(Path.join(dir(), name)) do
      {:ok, files} -> files |> Enum.filter(&Regex.match?(@file_name, &1)) |> Enum.sort()
      _ -> []
    end
  end

  defp mkdir_private(path) do
    with :ok <- File.mkdir_p(path), do: File.chmod(path, 0o700)
  end
end
