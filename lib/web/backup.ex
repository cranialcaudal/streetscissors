defmodule Web.Backup do
  @moduledoc """
  Nightly snapshots of the SQLite database.

  Until this existed there was no copy of the live data anywhere — the database
  is not in git (correctly), and the deploy has never dumped it.

  **Why `VACUUM INTO` and not `cp`.** The database runs in WAL mode and
  routinely carries several MB of uncheckpointed write-ahead log. Copying the
  `.db` file alone captures the main file *without* the committed transactions
  still sitting in the WAL, producing a snapshot that is silently stale or torn.
  `VACUUM INTO` asks SQLite itself for a consistent, fully-checkpointed copy
  through the existing connection, and compacts it on the way out.

  Configure with `:backup_path` (where snapshots land) and `:backup_keep` (how
  many to retain). Both have defaults; the test env points them at a tmp dir.

  Note that `VACUUM` cannot run inside a transaction, so this will fail if
  called from a sandboxed test connection. The scheduler calls it on a plain
  pooled connection, which is fine.
  """

  require Logger

  @default_keep 14

  @doc """
  Takes a snapshot and prunes old ones. Returns `{:ok, path}` or `{:error, reason}`.
  """
  @spec run() :: {:ok, String.t()} | {:error, term()}
  def run do
    dir = backup_dir()
    File.mkdir_p!(dir)

    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    path = Path.join(dir, "web-#{stamp}.db")

    case snapshot(path) do
      :ok ->
        pruned = prune()
        size = File.stat!(path).size

        Logger.info(
          "backup: wrote #{path} (#{div(size, 1024)} KB)" <>
            if(pruned > 0, do: ", pruned #{pruned} old", else: "")
        )

        {:ok, path}

      {:error, reason} = error ->
        Logger.error("backup failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Entry point for the scheduler. Never raises — a failed backup must not take
  the Quantum job (or anything sharing its supervisor) down with it.
  """
  def run_scheduled do
    run()
    :ok
  rescue
    error ->
      Logger.error("backup crashed: #{Exception.message(error)}")
      :ok
  end

  @doc "Snapshots to an explicit path. Exposed for tests and manual runs."
  @spec snapshot(String.t()) :: :ok | {:error, term()}
  def snapshot(path) do
    # VACUUM INTO takes a string literal, not a bind parameter. The path is
    # built from config and a timestamp — never user input — but double any
    # quote regardless rather than trusting that to stay true.
    escaped = String.replace(path, "'", "''")
    Web.Repo.query!("VACUUM INTO '#{escaped}'")
    :ok
  rescue
    error -> {:error, error}
  end

  @doc "Snapshots present on disk, newest first."
  @spec list() :: [%{path: String.t(), size: non_neg_integer(), mtime: File.Stat.t() | tuple()}]
  def list do
    dir = backup_dir()

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.match?(&1, ~r/^web-\d{8}-\d{6}\.db$/))
        |> Enum.map(fn name ->
          full = Path.join(dir, name)
          stat = File.stat!(full)
          %{path: full, size: stat.size, mtime: stat.mtime}
        end)
        |> Enum.sort_by(& &1.path, :desc)

      _ ->
        []
    end
  end

  @doc "Deletes all but the newest `backup_keep` snapshots. Returns how many went."
  @spec prune() :: non_neg_integer()
  def prune do
    # Names are timestamped and zero-padded, so sorting by name is chronological
    # and does not depend on filesystem mtimes surviving a copy.
    list()
    |> Enum.drop(keep())
    |> Enum.map(fn %{path: path} -> File.rm(path) end)
    |> Enum.count(&(&1 == :ok))
  end

  def backup_dir do
    Application.get_env(:web, :backup_path) ||
      Path.join(System.user_home!(), "streetscissors-backups/db")
  end

  defp keep, do: Application.get_env(:web, :backup_keep, @default_keep)
end
