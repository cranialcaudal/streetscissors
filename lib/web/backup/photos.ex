defmodule Web.Backup.Photos do
  @moduledoc """
  Copies the negatives archive onto the external drive.

  `Web.Backup` snapshots the SQLite database and nothing else, which left the
  photographs — 317 MB of scanned film — with no backup anywhere: not in git,
  not on the drive, not in the database. Rides re-sync from Komoot and
  analytics are replaceable; a lost scan is simply lost. (The writing is the
  other thing that cannot be rebuilt, and `Web.Backup.Content` keeps it.)

  Deliberately a separate module from `Web.Backup`. That one is about
  point-in-time database snapshots with verification and retention, and this is
  a file tree that only ever grows. Sharing a module would mean sharing neither
  semantics nor code. The copying itself is `Web.Backup.Tree`: rsync, with no
  `--delete`, so the mirror accumulates rather than reproducing a deletion.

  Configure with `:photos_mirror_path`; `nil` disables it. The directory must
  already exist and is never created, exactly as in `Web.Backup.mirror/1`: on
  removable media its presence *is* the signal that the drive is connected, and
  a `mkdir -p` would recreate it on the root filesystem, copying the archive
  onto the same disk it was supposed to escape.
  """

  require Logger

  alias Web.Backup.Tree
  alias Web.Negatives

  @doc "The configured destination, or `nil`. Empty string counts as unset."
  @spec mirror_dir() :: String.t() | nil
  def mirror_dir do
    case Application.get_env(:web, :photos_mirror_path) do
      nil -> nil
      "" -> nil
      dir -> dir
    end
  end

  @doc "True when a destination is configured and present."
  @spec available?() :: boolean()
  def available? do
    case mirror_dir() do
      nil -> false
      dir -> File.dir?(dir)
    end
  end

  @doc """
  Syncs the negatives archive to the mirror.

  Returns `{:ok, summary}` with file counts, `:skipped` when the destination is
  unconfigured or absent, or `{:error, reason}`. Never raises — a backup problem
  must not take down the caller, which is a supervised watcher process.
  """
  @spec sync() :: {:ok, map()} | :skipped | {:error, term()}
  def sync do
    source = Negatives.base_path()

    cond do
      not available?() -> :skipped
      not File.dir?(source) -> {:error, {:source_missing, source}}
      true -> Tree.sync(source, mirror_dir(), label: "photo")
    end
  rescue
    error ->
      Logger.error("photo backup crashed: #{Exception.message(error)}")
      {:error, error}
  end

  defdelegate count_files(dir), to: Tree
  defdelegate total_bytes(dir), to: Tree
end
