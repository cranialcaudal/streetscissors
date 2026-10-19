defmodule Web.Backup.FitnessPhotos do
  @moduledoc """
  Keeps the progress photographs (`Web.Fitness.Photos`) in two more places:

    * **nightly**, a copy at `:fitness_photos_backup_path` (by default
      `fitness-photos/` beside the database's snapshot folder), so a
      deleted or overwritten file is still on this machine;
    * **on the drive**, a mirror at `:fitness_photos_mirror_path` (by
      default `fitness-photos/` beside the recordings' mirror), made when
      the drive watcher sees the drive.

  Both are `Web.Backup.Tree`'s rsync with no `--delete`, so a photograph
  set aside stays in the copies. Like the cutting room's bin, they are
  **never** under the uploads root and never in the content archive,
  whose thirty versions would each carry every photograph. A folder is made
  only inside one that is already there (`Web.Backup.claim_mirror/1`).
  """

  require Logger

  alias Web.Backup
  alias Web.Backup.Tree
  alias Web.Fitness.Photos

  @doc "The nightly copy's folder, or nil."
  def backup_dir do
    case Application.fetch_env(:web, :fitness_photos_backup_path) do
      {:ok, dir} -> blank(dir)
      :error -> beside(Application.get_env(:web, :backup_path))
    end
  end

  @doc "The drive's folder, or nil."
  def mirror_dir do
    case Application.fetch_env(:web, :fitness_photos_mirror_path) do
      {:ok, dir} -> blank(dir)
      :error -> beside(Web.Backup.Uploads.mirror_dir())
    end
  end

  @doc "The Quantum entry: the nightly copy."
  def run_scheduled, do: copy_to(backup_dir(), "progress photos (local)")

  @doc "The drive watcher's entry: the mirror, when the drive is in."
  def sync, do: copy_to(mirror_dir(), "progress photos (drive)")

  defp copy_to(dest, label) do
    source = Photos.dir()

    cond do
      not File.dir?(source) ->
        :skipped

      true ->
        case Backup.claim_mirror(dest) do
          :absent ->
            :skipped

          {:ok, dest} ->
            File.chmod(dest, 0o700)
            Tree.sync(source, dest, label: label)
        end
    end
  rescue
    error ->
      Logger.error("progress photos backup crashed: #{Exception.message(error)}")
      {:error, error}
  end

  defp beside(nil), do: nil
  defp beside(""), do: nil
  defp beside(dir), do: dir |> Path.expand() |> Path.dirname() |> Path.join("fitness-photos")

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(dir), do: dir
end
