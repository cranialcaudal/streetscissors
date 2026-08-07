defmodule Web.BackupTest do
  # Deliberately NOT Web.DataCase: that wraps each test in a sandbox
  # transaction, and SQLite refuses to VACUUM inside one. The scheduler runs
  # this on a plain pooled connection, so the test takes one too.
  use ExUnit.Case, async: false

  alias Web.Backup

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Web.Repo, sandbox: false)

    dir = Path.join(System.tmp_dir!(), "backup_test_#{System.unique_integer([:positive])}")
    prev = Application.get_env(:web, :backup_path)
    Application.put_env(:web, :backup_path, dir)

    on_exit(fn ->
      File.rm_rf!(dir)

      if prev,
        do: Application.put_env(:web, :backup_path, prev),
        else: Application.delete_env(:web, :backup_path)
    end)

    {:ok, dir: dir}
  end

  test "writes a snapshot that is a real, readable database", %{dir: dir} do
    assert {:ok, path} = Backup.run()
    assert File.exists?(path)
    assert Path.dirname(path) == dir

    # A file that merely exists proves nothing — open it and read the schema
    # back out. This is what catches a truncated or torn copy.
    {out, 0} = System.cmd("sqlite3", [path, "select count(*) from sqlite_master"])
    assert String.to_integer(String.trim(out)) > 0

    {integrity, 0} = System.cmd("sqlite3", [path, "pragma integrity_check"])
    assert String.trim(integrity) == "ok"
  end

  test "the snapshot contains data committed before it ran" do
    # The reason VACUUM INTO is used instead of File.cp: the database is in WAL
    # mode, so a plain copy of the .db can miss committed transactions still in
    # the write-ahead log. Writes here are real (no sandbox), so clean up.
    # Unique per run: these writes are real, so a fixed name would collide with
    # rows left behind by any earlier run that died before its cleanup.
    canary = "backup-canary-#{System.unique_integer([:positive])}"
    {:ok, entry} = Web.General.create_guestbook_entry(%{name: canary, message: "canary"})

    try do
      assert {:ok, path} = Backup.run()

      {out, 0} =
        System.cmd("sqlite3", [
          path,
          "select count(*) from guestbook_entries where name='#{canary}'"
        ])

      assert String.trim(out) == "1"
    after
      # Cleanup has to happen inside the test: on_exit runs after the
      # connection is checked back into the pool, and the delete would fail.
      Web.General.delete_guestbook_entry(entry)
    end
  end

  test "list/0 returns snapshots newest first" do
    for _ <- 1..3 do
      {:ok, _} = Backup.run()
      # Filenames carry a whole-second timestamp, so space them out.
      Process.sleep(1100)
    end

    paths = Backup.list() |> Enum.map(& &1.path)
    assert length(paths) == 3
    assert paths == Enum.sort(paths, :desc)
  end

  test "retention keeps only the newest backup_keep snapshots", %{dir: dir} do
    prev = Application.get_env(:web, :backup_keep)
    Application.put_env(:web, :backup_keep, 2)
    on_exit(fn -> if prev, do: Application.put_env(:web, :backup_keep, prev) end)

    # Hand-made files, so the test does not need four seconds of sleeping.
    for stamp <- ~w(20260101-000000 20260102-000000 20260103-000000 20260104-000000) do
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "web-#{stamp}.db"), "x")
    end

    assert Backup.prune() == 2
    remaining = Backup.list() |> Enum.map(&Path.basename(&1.path))
    assert remaining == ["web-20260104-000000.db", "web-20260103-000000.db"]
  end

  test "only counts its own snapshots, leaving anything else in the directory alone",
       %{dir: dir} do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "notes.txt"), "keep me")
    File.write!(Path.join(dir, "web-manual-copy.db"), "keep me too")

    {:ok, _} = Backup.run()
    Backup.prune()

    assert File.exists?(Path.join(dir, "notes.txt"))
    assert File.exists?(Path.join(dir, "web-manual-copy.db"))
  end

  test "run_scheduled/0 never raises, so a bad path cannot take the scheduler down" do
    Application.put_env(:web, :backup_path, "/proc/definitely/not/writable")
    assert Backup.run_scheduled() == :ok
  end

  describe "restoring" do
    # The point of the whole module. A snapshot nobody has ever put back is a
    # guess, not a backup.
    test "a snapshot works as the database when copied into place", %{dir: dir} do
      {:ok, snapshot} = Backup.run()

      # Restore the way you would in an incident: stop writing, move the file
      # into position, open it as the live database.
      restored = Path.join(dir, "restored.db")
      :ok = File.cp(snapshot, restored)

      {:ok, conn} = Exqlite.Sqlite3.open(restored, mode: :readonly)

      on_exit(fn -> Exqlite.Sqlite3.close(conn) end)

      # The schema came across whole...
      {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM sqlite_master")
      {:ok, [[tables]]} = Exqlite.Sqlite3.fetch_all(conn, stmt)
      assert tables > 0

      # ...and so did the migration history, which is what a restored database
      # needs in order to accept later migrations rather than re-running them.
      {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM schema_migrations")
      {:ok, [[migrations]]} = Exqlite.Sqlite3.fetch_all(conn, stmt)
      assert migrations > 0
    end

    test "row counts in the snapshot match the live database" do
      {:ok, path} = Backup.run()

      live = Web.Repo.query!("SELECT count(*) FROM schema_migrations").rows

      {:ok, conn} = Exqlite.Sqlite3.open(path, mode: :readonly)
      {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM schema_migrations")
      {:ok, snapshot_rows} = Exqlite.Sqlite3.fetch_all(conn, stmt)
      Exqlite.Sqlite3.close(conn)

      assert live == snapshot_rows
    end
  end

  describe "verify/1" do
    test "accepts a snapshot it just wrote" do
      {:ok, path} = Backup.run()
      assert Backup.verify(path) == :ok
    end

    test "rejects a truncated file", %{dir: dir} do
      {:ok, path} = Backup.run()

      torn = Path.join(dir, "torn.db")
      <<head::binary-size(4096), _rest::binary>> = File.read!(path)
      File.write!(torn, head)

      assert {:error, _} = Backup.verify(torn)
    end

    test "rejects a file that is not a database at all", %{dir: dir} do
      File.mkdir_p!(dir)
      bogus = Path.join(dir, "bogus.db")
      File.write!(bogus, "this is not a database")

      assert {:error, _} = Backup.verify(bogus)
    end

    test "rejects an empty database, which passes integrity_check on its own",
         %{dir: dir} do
      File.mkdir_p!(dir)
      empty = Path.join(dir, "empty.db")
      {:ok, conn} = Exqlite.Sqlite3.open(empty)
      Exqlite.Sqlite3.close(conn)

      assert {:error, {:empty_schema, _}} = Backup.verify(empty)
    end

    test "an unwritable backup directory raises out of run/0" do
      # Documenting the real contract: run/0 does not soften this into an error
      # tuple, which is exactly why the scheduler goes through run_scheduled/0.
      Application.put_env(:web, :backup_path, "/proc/definitely/not/writable")
      assert_raise File.Error, fn -> Backup.run() end
      assert Backup.list() == []
    end
  end

  describe "the off-disk mirror" do
    test "copies a verified snapshot to the mirror directory", %{dir: dir} do
      mirror = Path.join(dir, "mirror")
      File.mkdir_p!(mirror)
      Application.put_env(:web, :backup_mirror_path, mirror)
      on_exit(fn -> Application.put_env(:web, :backup_mirror_path, nil) end)

      {:ok, path} = Backup.run()

      copied = Path.join(mirror, Path.basename(path))
      assert File.exists?(copied)
      assert Backup.verify(copied) == :ok
      assert File.read!(copied) == File.read!(path)
    end

    test "skips silently when no mirror is configured" do
      Application.put_env(:web, :backup_mirror_path, nil)
      {:ok, path} = Backup.run()
      assert Backup.mirror(path) == :skipped
    end

    test "skips rather than recreating an unplugged drive's mount point", %{dir: dir} do
      # The failure this guards against: writing the "off-disk" copy back onto
      # the very disk it was supposed to escape, by mkdir -p'ing a path whose
      # mount point is gone.
      absent = "/run/media/cesar/NO_SUCH_DRIVE/streetscissors-backups"
      Application.put_env(:web, :backup_mirror_path, absent)
      on_exit(fn -> Application.put_env(:web, :backup_mirror_path, nil) end)

      {:ok, path} = Backup.run()

      assert Backup.mirror(path) == :skipped
      refute File.exists?(absent)
      # The local snapshot is still good — an absent drive is not a failure.
      assert Backup.verify(path) == :ok
      assert File.exists?(Path.join(dir, Path.basename(path)))
    end

    test "applies retention to the mirror too", %{dir: dir} do
      mirror = Path.join(dir, "mirror")
      File.mkdir_p!(mirror)
      Application.put_env(:web, :backup_mirror_path, mirror)
      on_exit(fn -> Application.put_env(:web, :backup_mirror_path, nil) end)

      # backup_keep is 3 in the test env.
      for _ <- 1..5 do
        {:ok, _} = Backup.run()
        Process.sleep(1_000)
      end

      assert length(Backup.list_dir(mirror)) <= 3
    end
  end

  describe "catching up a missed run" do
    test "stale?/0 is true when there is no snapshot at all" do
      assert Backup.stale?()
    end

    test "stale?/0 is false immediately after a snapshot" do
      {:ok, _} = Backup.run()
      refute Backup.stale?()
    end

    test "stale?/0 is true once the newest snapshot is older than the limit" do
      {:ok, _} = Backup.run()
      Application.put_env(:web, :backup_max_age_hours, -1)
      on_exit(fn -> Application.delete_env(:web, :backup_max_age_hours) end)

      assert Backup.stale?()
    end

    test "run_on_boot/0 takes a snapshot when none exists" do
      Application.put_env(:web, :backup_on_boot, true)
      on_exit(fn -> Application.put_env(:web, :backup_on_boot, false) end)

      assert Backup.list() == []
      assert Backup.run_on_boot() == :ok
      assert length(Backup.list()) == 1
    end

    test "run_on_boot/0 does nothing when a recent snapshot already exists" do
      Application.put_env(:web, :backup_on_boot, true)
      on_exit(fn -> Application.put_env(:web, :backup_on_boot, false) end)

      {:ok, _} = Backup.run()
      assert length(Backup.list()) == 1

      assert Backup.run_on_boot() == :ok
      assert length(Backup.list()) == 1
    end

    test "run_on_boot/0 respects the off switch" do
      Application.put_env(:web, :backup_on_boot, false)
      assert Backup.run_on_boot() == :ok
      assert Backup.list() == []
    end

    test "run_on_boot/0 never raises, so a bad path cannot stop the app booting" do
      Application.put_env(:web, :backup_on_boot, true)
      Application.put_env(:web, :backup_path, "/proc/definitely/not/writable")
      on_exit(fn -> Application.put_env(:web, :backup_on_boot, false) end)

      assert Backup.run_on_boot() == :ok
    end
  end
end
