defmodule Web.Backup.Drill do
  @moduledoc """
  A restore, rehearsed: once a week the newest database snapshot and the
  newest content archive are restored to scratch copies and read back.

  Every snapshot is checked when it is written (`Web.Backup.verify/1`,
  `Web.Backup.Content.verify/2`), and that answers "was this a good copy when
  it was made". It does not answer the question that matters on the day one
  is needed: is the file that has been sitting on the disk for a week *still*
  a good copy, and does the thing a restore actually does still work. A
  backup that has never been restored is a hope. This is the rehearsal.

  **The database.** The newest snapshot is copied to a scratch file — the
  copy is the restore — and that copy is opened on its own connection,
  integrity-checked, and has every one of its tables read end to end. Its
  migration version must not be ahead of the live database's, since a
  snapshot from the future could not have come from here.

  **The content.** The newest archive is unpacked into a scratch folder and
  its fingerprint recomputed from what came out. The archive's name carries
  the fingerprint it was written with, so a match proves it still holds
  exactly the files, with exactly the bytes, that it held then.

  **The copies on the drive**, when it is plugged in, get the same reading of
  whichever is newest there. An absent drive is not a failure of the drill.

  The outcome is one `site_settings` row (`restore_drill`), which the overview
  shows and `Web.Monitor` watches: a failed drill is mailed like any other
  fault. Scratch copies live beside the backups, never in `/tmp`, which on
  this machine is memory, and are removed whatever happens.

  Scheduled weekly by Quantum; `run_on_boot/0` (through
  `Web.Backup.catch_up/0`) makes up a week the machine slept through.
  """

  require Logger

  alias Exqlite.Sqlite3
  alias Web.Backup
  alias Web.Backup.Content
  alias Web.Repo
  alias Web.SiteSettings

  @setting "restore_drill"
  @stale_days 8

  @type part :: %{ok: boolean(), detail: String.t()}

  @doc """
  Runs the drill and records it. Returns
  `%{at: DateTime, database: part, content: part}`.
  """
  def run do
    result = %{
      at: DateTime.utc_now() |> DateTime.truncate(:second),
      database: database(),
      content: content()
    }

    store(result)

    for {name, %{ok: false, detail: detail}} <- Map.take(result, [:database, :content]) do
      Logger.error("restore drill: #{name} failed: #{detail}")
    end

    result
  end

  @doc "Entry point for the scheduler. Never raises."
  def run_scheduled do
    run()
    :ok
  rescue
    error ->
      Logger.error("restore drill crashed: #{Exception.message(error)}")
      :ok
  end

  @doc "Runs at boot when there has been no drill in over a week. Always `:ok`."
  def run_on_boot do
    if Application.get_env(:web, :backup_on_boot, true) and stale?() do
      Logger.info("restore drill: none in #{@stale_days} days, running at boot")
      run()
    end

    :ok
  rescue
    error ->
      Logger.error("restore drill on boot crashed: #{Exception.message(error)}")
      :ok
  end

  @doc "The last drill, as `run/0` returned it, or `nil` if there has never been one."
  def last do
    with json when is_binary(json) <- SiteSettings.get_setting(@setting),
         {:ok, %{"at" => at, "database" => database, "content" => content}} <- Jason.decode(json),
         {:ok, at, _offset} <- DateTime.from_iso8601(at) do
      %{at: at, database: part(database), content: part(content)}
    else
      _ -> nil
    end
  end

  @doc "True when there has never been a drill, or none in over a week."
  def stale? do
    case last() do
      nil -> true
      %{at: at} -> DateTime.diff(DateTime.utc_now(), at, :day) >= @stale_days
    end
  end

  # --- The database ----------------------------------------------------------

  @doc "Restores the newest snapshot to a scratch file and reads it back."
  @spec database() :: part()
  def database do
    case Backup.list() do
      [] ->
        failed("there is no snapshot to restore")

      [%{path: path} | _] ->
        with {:ok, read} <- restore_database(path),
             :ok <- mirror_copy(Backup.mirror_dir(), &Backup.list_dir/1, &restore_database/1) do
          passed("#{Path.basename(path)}: #{read}")
        else
          {:error, reason} -> failed("#{Path.basename(path)}: #{reason}")
        end
    end
  end

  defp restore_database(path) do
    scratch = Path.join(Path.dirname(path), ".drill-#{System.unique_integer([:positive])}.db")

    try do
      with :ok <- copy(path, scratch),
           {:ok, conn} <- open(scratch) do
        try do
          read_database(conn)
        after
          Sqlite3.close(conn)
        end
      end
    after
      # SQLite may leave a journal beside a database it opened for writing.
      for suffix <- ["", "-journal", "-wal", "-shm"], do: File.rm(scratch <> suffix)
    end
  end

  defp read_database(conn) do
    with {:ok, [["ok"]]} <- rows(conn, "PRAGMA integrity_check"),
         {:ok, tables} <- rows(conn, "SELECT name FROM sqlite_master WHERE type = 'table'"),
         {:ok, counts} <- count_tables(conn, List.flatten(tables)),
         :ok <- not_from_the_future(conn) do
      {:ok, "#{length(counts)} tables, #{Enum.sum(counts)} rows read back"}
    else
      {:ok, other} -> {:error, "the integrity check said #{inspect(other)}"}
      {:error, reason} -> {:error, describe(reason)}
    end
  end

  # Every table, counted: a count has to walk the whole table, so a page that
  # cannot be read fails here rather than on the day it is needed.
  defp count_tables(conn, tables) do
    Enum.reduce_while(tables, {:ok, []}, fn table, {:ok, counts} ->
      # A table name cannot be a bound parameter. It comes out of the
      # snapshot's own schema, and is quoted as an identifier regardless.
      quoted = "\"" <> String.replace(table, "\"", "\"\"") <> "\""

      case rows(conn, "SELECT count(*) FROM " <> quoted) do
        {:ok, [[count]]} ->
          {:cont, {:ok, [count | counts]}}

        {:error, reason} ->
          {:halt, {:error, "table #{table} could not be read: #{describe(reason)}"}}
      end
    end)
  end

  defp not_from_the_future(conn) do
    sql = "SELECT max(version) FROM schema_migrations"

    case {rows(conn, sql), Repo.query(sql)} do
      {{:ok, [[theirs]]}, {:ok, %{rows: [[ours]]}}}
      when is_integer(theirs) and is_integer(ours) and theirs > ours ->
        {:error, "its schema (#{theirs}) is newer than the live database's (#{ours})"}

      {{:error, reason}, _live} ->
        {:error, "its migrations could not be read: #{describe(reason)}"}

      _ ->
        :ok
    end
  end

  defp open(path) do
    case Sqlite3.open(path) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, "the restored copy would not open: #{describe(reason)}"}
    end
  end

  defp rows(conn, sql) do
    with {:ok, statement} <- Sqlite3.prepare(conn, sql) do
      result = Sqlite3.fetch_all(conn, statement)
      Sqlite3.release(conn, statement)
      result
    end
  end

  # --- The content -----------------------------------------------------------

  @doc "Unpacks the newest content archive into a scratch folder and reads it back."
  @spec content() :: part()
  def content do
    case Content.list() do
      [] ->
        failed("there is no archive to restore")

      [%{path: path} | _] ->
        with {:ok, files} <- Content.restore_check(path),
             :ok <-
               mirror_copy(Content.mirror_dir(), &Content.list_dir/1, &Content.restore_check/1) do
          passed("#{Path.basename(path)}: #{files} files unpacked and matched")
        else
          {:error, reason} -> failed("#{Path.basename(path)}: #{describe(reason)}")
        end
    end
  end

  # --- Shared ----------------------------------------------------------------

  # The newest copy on the drive, read the same way, when the drive is in and
  # holds one. Its absence is not the drill's business.
  defp mirror_copy(dir, list, restore) do
    with true <- is_binary(dir) and File.dir?(dir),
         [%{path: path} | _] <- list.(dir) do
      case restore.(path) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, "the copy on the drive failed: #{describe(reason)}"}
      end
    else
      _ -> :ok
    end
  end

  defp copy(from, to) do
    case File.cp(from, to) do
      :ok -> :ok
      {:error, reason} -> {:error, "could not be copied: #{describe(reason)}"}
    end
  end

  defp passed(detail), do: %{ok: true, detail: detail}
  defp failed(detail), do: %{ok: false, detail: detail}

  defp part(%{"ok" => ok, "detail" => detail}), do: %{ok: ok == true, detail: detail}
  defp part(_), do: failed("the record of it could not be read")

  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason) when is_atom(reason), do: to_string(reason)
  defp describe(reason), do: inspect(reason)

  defp store(result) do
    SiteSettings.put_setting(
      @setting,
      Jason.encode!(%{
        "at" => DateTime.to_iso8601(result.at),
        "database" => %{"ok" => result.database.ok, "detail" => result.database.detail},
        "content" => %{"ok" => result.content.ok, "detail" => result.content.detail}
      })
    )
  end
end
