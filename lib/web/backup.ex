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

  **Every snapshot is verified before it counts.** A file of the right size is
  not evidence of anything; `verify/1` opens it read-only and runs
  `PRAGMA integrity_check` plus a schema read, so a torn or truncated copy is
  reported at the moment it is written rather than discovered during a restore.

  **A second copy goes off the disk.** Snapshots beside the database protect
  against a bad deploy or a mistaken `DELETE`, and against nothing else — one
  failed volume takes the database and every snapshot of it together. When
  `:backup_mirror_path` is set and that directory already exists, each verified
  snapshot is copied there too. The directory is never created — on removable
  media its presence *is* the "drive is plugged in" signal, and a `mkdir -p`
  would recreate it on the root filesystem, defeating the point. Create it once
  on the drive. An absent drive is an ordinary condition, not an error: the
  mirror is skipped with a log line and the local snapshot still stands.

  **Missed runs are caught up at boot.** Quantum fires on a schedule and does
  not make up for a run it slept through, which on a laptop means any night the
  lid is closed silently produces nothing. `run_on_boot/0` takes a snapshot at
  startup when the newest one is older than `:backup_max_age_hours`.

  Configure with `:backup_path` (where snapshots land), `:backup_keep` (how many
  to retain), `:backup_mirror_path` (the off-disk copy, `nil` to disable),
  `:backup_on_boot` and `:backup_max_age_hours`. All have defaults; the test env
  points them at a tmp dir and disables the boot run.

  Note that `VACUUM` cannot run inside a transaction, so this will fail if
  called from a sandboxed test connection. The scheduler calls it on a plain
  pooled connection, which is fine.
  """

  require Logger

  @default_keep 14
  @default_max_age_hours 20

  @doc """
  Takes a snapshot and prunes old ones. Returns `{:ok, path}` or `{:error, reason}`.
  """
  @spec run() :: {:ok, String.t()} | {:error, term()}
  def run do
    dir = backup_dir()
    File.mkdir_p!(dir)

    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    path = Path.join(dir, "web-#{stamp}.db")

    with :ok <- snapshot(path),
         :ok <- verify(path) do
      pruned = prune()
      size = File.stat!(path).size
      mirrored = mirror(path)

      Logger.info(
        "backup: wrote #{path} (#{div(size, 1024)} KB)" <>
          if(pruned > 0, do: ", pruned #{pruned} old", else: "") <>
          case mirrored do
            {:ok, dest} -> ", mirrored to #{dest}"
            :skipped -> ", mirror unavailable"
            {:error, reason} -> ", MIRROR FAILED: #{inspect(reason)}"
          end
      )

      {:ok, path}
    else
      {:error, reason} = error ->
        # A snapshot that cannot be read back is worse than no snapshot: it
        # looks like protection. Delete it so `list/0` never offers it as a
        # restore candidate.
        File.rm(path)
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

  @doc """
  Opens a snapshot read-only and proves it is a working database.

  Runs `PRAGMA integrity_check` and reads the schema back out. Deliberately
  goes through a *fresh connection to the file itself* rather than the pooled
  Repo — the whole question is whether this particular file stands on its own,
  which a query against the live database could never answer.
  """
  @spec verify(String.t()) :: :ok | {:error, term()}
  def verify(path) do
    case Exqlite.Sqlite3.open(path, mode: :readonly) do
      {:ok, conn} ->
        try do
          with :ok <- check_integrity(conn),
               :ok <- check_has_schema(conn) do
            :ok
          end
        after
          Exqlite.Sqlite3.close(conn)
        end

      {:error, reason} ->
        {:error, {:unopenable, reason}}
    end
  end

  defp check_integrity(conn) do
    case query_one(conn, "PRAGMA integrity_check") do
      {:ok, "ok"} -> :ok
      {:ok, other} -> {:error, {:integrity_check, other}}
      {:error, reason} -> {:error, {:integrity_check, reason}}
    end
  end

  # An empty file passes integrity_check — it is a valid database with nothing
  # in it. A snapshot of this application never legitimately has zero tables,
  # so treat that as a failed copy.
  defp check_has_schema(conn) do
    case query_one(conn, "SELECT count(*) FROM sqlite_master") do
      {:ok, n} when is_integer(n) and n > 0 -> :ok
      {:ok, n} -> {:error, {:empty_schema, n}}
      {:error, reason} -> {:error, {:schema_read, reason}}
    end
  end

  defp query_one(conn, sql) do
    with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, sql),
         {:ok, rows} <- Exqlite.Sqlite3.fetch_all(conn, stmt) do
      Exqlite.Sqlite3.release(conn, stmt)

      case rows do
        [[value] | _] -> {:ok, value}
        other -> {:error, {:unexpected_result, other}}
      end
    end
  end

  @doc """
  Copies a verified snapshot off the disk the database lives on.

  Returns `{:ok, dest}`, `:skipped` when no mirror is configured or the target
  is not mounted, or `{:error, reason}`. Never raises — an absent USB drive
  must not turn a good local backup into a failure.
  """
  @spec mirror(String.t()) :: {:ok, String.t()} | :skipped | {:error, term()}
  def mirror(path) do
    case mirror_dir() do
      nil ->
        :skipped

      dir ->
        # The directory must ALREADY exist; this never creates it. On removable
        # media that is the whole signal — when the drive is unplugged the path
        # simply is not there, and a `mkdir -p` would helpfully recreate it on
        # the root filesystem, writing the "off-disk" copy straight back onto
        # the disk it was supposed to escape. Create it once, on the drive.
        if File.dir?(dir) do
          copy_to_mirror(path, dir)
        else
          :skipped
        end
    end
  end

  defp copy_to_mirror(path, dir) do
    dest = Path.join(dir, Path.basename(path))

    with :ok <- File.cp(path, dest),
         :ok <- verify(dest) do
      prune_dir(dir)
      {:ok, dest}
    else
      {:error, reason} ->
        File.rm(dest)
        {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  # An unset environment variable arrives as nil, but one exported empty —
  # BACKUP_MIRROR_PATH="" in a unit file or a staging script — arrives as "".
  # Both mean "no mirror"; without this the watcher would start up and poll for
  # a directory named "".
  def mirror_dir do
    case Application.get_env(:web, :backup_mirror_path) do
      nil -> nil
      "" -> nil
      dir -> dir
    end
  end

  @doc "True when the mirror is configured and its directory is present."
  @spec mirror_available?() :: boolean()
  def mirror_available? do
    case mirror_dir() do
      nil -> false
      dir -> File.dir?(dir)
    end
  end

  @doc """
  Brings the mirror up to date. This is what running when the drive is plugged
  in means in practice.

  Takes a fresh snapshot first when the newest is stale, so plugging the drive
  in gets you a *current* backup rather than whatever happened to be lying
  around, then copies across every local snapshot the mirror does not already
  have and applies retention.

  Returns `{:ok, summary}`, or `:unavailable` when the drive is not there.
  Never raises.
  """
  @spec sync_mirror() :: {:ok, map()} | :unavailable
  def sync_mirror do
    if mirror_available?() do
      if stale?(), do: run()

      dir = mirror_dir()
      have = MapSet.new(list_dir(dir), &Path.basename(&1.path))

      results =
        list()
        |> Enum.reject(&MapSet.member?(have, Path.basename(&1.path)))
        # Newest first from list/0; copy oldest first so an interrupted sync
        # still leaves the mirror's newest file being the newest one it has.
        |> Enum.reverse()
        |> Enum.map(fn %{path: path} -> copy_to_mirror(path, dir) end)

      copied = Enum.count(results, &match?({:ok, _}, &1))
      failed = Enum.count(results, &match?({:error, _}, &1))

      if copied > 0 or failed > 0 do
        Logger.info(
          "backup: mirror sync copied #{copied}" <>
            if(failed > 0, do: ", #{failed} FAILED", else: "") <>
            " to #{dir}"
        )
      end

      {:ok, %{copied: copied, failed: failed, present: length(list_dir(dir))}}
    else
      :unavailable
    end
  rescue
    error ->
      Logger.error("backup: mirror sync crashed: #{Exception.message(error)}")
      {:ok, %{copied: 0, failed: 1, present: 0}}
  end

  @doc """
  Entry point for application start. Takes a snapshot when the newest one is
  older than `:backup_max_age_hours`, so a night the machine spent asleep is
  made up for rather than lost.

  Runs in a temporary supervised task and always returns `:ok`; a backup
  problem must never stop the application from booting.
  """
  def run_on_boot do
    cond do
      not Application.get_env(:web, :backup_on_boot, true) -> :ok
      not stale?() -> :ok
      true -> log_boot_run()
    end

    :ok
  rescue
    error ->
      Logger.error("backup on boot crashed: #{Exception.message(error)}")
      :ok
  end

  defp log_boot_run do
    Logger.info("backup: newest snapshot is stale or missing, taking one at boot")
    run()
  end

  @doc """
  True when there is no snapshot, or the newest is older than
  `:backup_max_age_hours`.
  """
  @spec stale?() :: boolean()
  def stale? do
    case list() do
      [] ->
        true

      [%{mtime: mtime} | _] ->
        age_hours = NaiveDateTime.diff(NaiveDateTime.utc_now(), to_naive(mtime), :second) / 3600
        age_hours > max_age_hours()
    end
  end

  # File.stat/1 returns erlang datetime tuples by default.
  defp to_naive({{y, mo, d}, {h, mi, s}}), do: NaiveDateTime.new!(y, mo, d, h, mi, s)
  defp to_naive(%NaiveDateTime{} = naive), do: naive

  defp max_age_hours,
    do: Application.get_env(:web, :backup_max_age_hours, @default_max_age_hours)

  @doc "Snapshots present on disk, newest first."
  @spec list() :: [%{path: String.t(), size: non_neg_integer(), mtime: File.Stat.t() | tuple()}]
  def list, do: list_dir(backup_dir())

  @doc "Snapshots in an arbitrary directory, newest first. Used for the mirror."
  @spec list_dir(String.t()) :: [
          %{path: String.t(), size: non_neg_integer(), mtime: File.Stat.t() | tuple()}
        ]
  def list_dir(dir) do
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
  def prune, do: prune_dir(backup_dir())

  @doc "Applies the retention policy to an arbitrary directory."
  @spec prune_dir(String.t()) :: non_neg_integer()
  def prune_dir(dir) do
    # Names are timestamped and zero-padded, so sorting by name is chronological
    # and does not depend on filesystem mtimes surviving a copy.
    dir
    |> list_dir()
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
