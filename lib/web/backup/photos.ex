defmodule Web.Backup.Photos do
  @moduledoc """
  Copies the negatives archive onto the external drive.

  `Web.Backup` snapshots the SQLite database and nothing else, which left the
  photographs — 317 MB of scanned film — with no backup anywhere: not in git,
  not on the drive, not in the database. They are also the one thing here that
  cannot be reconstructed. Rides re-sync from Komoot, written content is tracked
  in git, analytics are replaceable; a lost scan is simply lost.

  Deliberately a separate module from `Web.Backup`. That one is about
  point-in-time database snapshots with verification and retention, and this is
  a file tree that only ever grows. Sharing a module would mean sharing neither
  semantics nor code.

  **Why rsync and not an Elixir file walk.** rsync already solves incremental
  copying, partial transfers and permissions, and after the first run it moves
  only what changed. Reimplementing that badly for 219 files is not a good
  trade.

  **`--delete` is deliberately absent.** A backup that propagates local
  deletions is not a backup — it would faithfully reproduce the accident you
  most want protection from. The mirror accumulates.

  Configure with `:photos_mirror_path`; `nil` disables it. The directory must
  already exist and is never created, exactly as in `Web.Backup.mirror/1`: on
  removable media its presence *is* the signal that the drive is connected, and
  a `mkdir -p` would recreate it on the root filesystem, copying the archive
  onto the same disk it was supposed to escape.
  """

  require Logger

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
      true -> run_rsync(source, mirror_dir())
    end
  rescue
    error ->
      Logger.error("photo backup crashed: #{Exception.message(error)}")
      {:error, error}
  end

  defp run_rsync(source, dest) do
    # Trailing slash on the source: copy the *contents* of Negatives into the
    # destination, rather than nesting a Negatives/ directory inside it on every
    # run.
    args = ["-a", "--no-perms", "--no-owner", "--no-group", source <> "/", dest <> "/"]

    case System.cmd("rsync", args, stderr_to_stdout: true) do
      {_out, 0} ->
        summary = %{files: count_files(dest), bytes: total_bytes(dest)}
        Logger.info("photo backup: #{summary.files} files on #{dest}")
        {:ok, summary}

      {out, code} ->
        Logger.error("photo backup: rsync exited #{code}: #{String.trim(out)}")
        {:error, {:rsync_failed, code}}
    end
  end

  @doc "Number of regular files under a directory, at any depth."
  @spec count_files(String.t()) :: non_neg_integer()
  def count_files(dir) do
    dir |> walk() |> Enum.count()
  end

  @doc "Total size in bytes of every regular file under a directory."
  @spec total_bytes(String.t()) :: non_neg_integer()
  def total_bytes(dir) do
    dir
    |> walk()
    |> Enum.reduce(0, fn path, acc ->
      case File.stat(path) do
        {:ok, %{size: size}} -> acc + size
        _ -> acc
      end
    end)
  end

  defp walk(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          full = Path.join(dir, entry)
          if File.dir?(full), do: walk(full), else: [full]
        end)

      _ ->
        []
    end
  end
end
