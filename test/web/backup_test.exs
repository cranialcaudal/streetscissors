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
end
