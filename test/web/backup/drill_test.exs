defmodule Web.Backup.DrillTest do
  use Web.DataCase

  alias Exqlite.Sqlite3
  alias Web.Backup
  alias Web.Backup.Content
  alias Web.Backup.Drill
  alias Web.SystemStatus

  @env [:backup_path, :content_backup_path, :backup_mirror_path, :content_mirror_path]

  # Backups of its own, so nothing another test left in the shared tmp dirs
  # is mistaken for the newest snapshot.
  setup do
    base = Path.join(System.tmp_dir!(), "drill-#{System.unique_integer([:positive])}")
    prev = Map.new(@env, &{&1, Application.get_env(:web, &1)})

    Application.put_env(:web, :backup_path, Path.join(base, "db"))
    Application.put_env(:web, :content_backup_path, Path.join(base, "content"))
    File.mkdir_p!(Path.join(base, "db"))

    on_exit(fn ->
      File.rm_rf!(base)
      for {key, value} <- prev, do: Application.put_env(:web, key, value)
    end)

    {:ok, base: base}
  end

  # A snapshot made by hand. The real ones come from VACUUM INTO, which
  # SQLite refuses inside the sandbox's transaction; what the drill reads is
  # an ordinary database file either way.
  defp snapshot!(dir \\ Backup.backup_dir(), opts \\ []) do
    version = Keyword.get(opts, :version, 1)
    stamp = Keyword.get(opts, :stamp, "20300302-031700")
    path = Path.join(dir, "web-#{stamp}.db")

    {:ok, conn} = Sqlite3.open(path)

    :ok =
      Sqlite3.execute(conn, """
      CREATE TABLE schema_migrations (version INTEGER);
      INSERT INTO schema_migrations VALUES (#{version});
      CREATE TABLE "odd ""name\""" (id INTEGER, title TEXT);
      INSERT INTO "odd ""name\""" VALUES (1, 'a'), (2, 'b'), (3, 'c');
      """)

    :ok = Sqlite3.close(conn)
    path
  end

  describe "the database" do
    test "the newest snapshot is restored to a scratch copy and every table read", %{base: base} do
      snapshot!()

      assert %{ok: true, detail: detail} = Drill.database()
      assert detail == "web-20300302-031700.db: 2 tables, 4 rows read back"

      # The scratch copy is gone, journals and all.
      assert File.ls!(Path.join(base, "db")) == ["web-20300302-031700.db"]
    end

    test "it is the newest that is rehearsed, since that is the one a restore would use" do
      snapshot!(Backup.backup_dir(), stamp: "20300301-031700")
      newest = snapshot!(Backup.backup_dir(), stamp: "20300302-031700")
      File.write!(newest, "torn in half")

      assert %{ok: false, detail: "web-20300302-031700.db: " <> _} = Drill.database()
    end

    test "a snapshot that has rotted on disk fails the drill" do
      path = snapshot!()
      size = File.stat!(path).size
      File.write!(path, :binary.part(File.read!(path), 0, div(size, 2)))

      assert %{ok: false} = Drill.database()
    end

    # A snapshot whose schema is ahead of the live database's did not come
    # from this database.
    test "a snapshot from the future fails" do
      snapshot!(Backup.backup_dir(), version: 99_999_999_999_999)

      assert %{ok: false, detail: detail} = Drill.database()
      assert detail =~ "is newer than the live database's"
    end

    test "having no snapshot at all fails" do
      assert %{ok: false, detail: "there is no snapshot to restore"} = Drill.database()
    end

    test "the copy on the drive is read too, when the drive is in", %{base: base} do
      snapshot!()
      drive = Path.join(base, "drive/db")
      File.mkdir_p!(drive)
      Application.put_env(:web, :backup_mirror_path, drive)

      # In, and empty: nothing to read is not a failure.
      assert %{ok: true} = Drill.database()

      File.write!(Path.join(drive, "web-20300302-031700.db"), "not a database")
      assert %{ok: false, detail: detail} = Drill.database()
      assert detail =~ "the copy on the drive failed"

      # Out: the drive's absence is not the drill's business.
      Application.put_env(:web, :backup_mirror_path, "/run/media/nobody/NO_SUCH_DRIVE/db")
      assert %{ok: true} = Drill.database()
    end
  end

  describe "the content" do
    test "the newest archive is unpacked and matched against its own fingerprint", %{base: base} do
      {:ok, path} = Content.run()

      assert %{ok: true, detail: detail} = Drill.content()
      assert detail =~ ~r/^#{Regex.escape(Path.basename(path))}: \d+ files unpacked and matched$/

      # Nothing is left beside the archives but the archive and its marker.
      assert Enum.sort(File.ls!(Path.join(base, "content"))) ==
               Enum.sort([Path.basename(path), "last-run"])
    end

    test "an archive that no longer holds what it was written with fails" do
      {:ok, path} = Content.run()

      # A valid archive, under the name of a different one.
      other = String.replace(path, ~r/-[0-9a-f]{12}\.tar\.gz$/, "-000000000000.tar.gz")
      File.rename!(path, other)

      assert %{ok: false, detail: detail} = Drill.content()
      assert detail =~ "what unpacked is not what was archived"
    end

    test "a truncated archive fails" do
      {:ok, path} = Content.run()
      File.write!(path, :binary.part(File.read!(path), 0, 40))

      assert %{ok: false} = Drill.content()
    end

    test "having no archive at all fails" do
      assert %{ok: false, detail: "there is no archive to restore"} = Drill.content()
    end
  end

  describe "run/0" do
    test "records both halves, and the overview reports them" do
      assert Drill.last() == nil
      assert Drill.stale?()
      assert %{state: :off, detail: "none run yet"} = SystemStatus.restore_drill()

      snapshot!()
      {:ok, _} = Content.run()
      result = Drill.run()

      assert %{database: %{ok: true}, content: %{ok: true}} = result
      assert Drill.last() == result
      refute Drill.stale?()

      assert %{state: :ok, detail: "database and content restored and read back", at: at} =
               SystemStatus.restore_drill()

      assert at == result.at
    end

    test "a failed half is a fault the overview names" do
      {:ok, _} = Content.run()
      Drill.run()

      assert %{state: :fail, detail: "database: there is no snapshot to restore"} =
               SystemStatus.restore_drill()
    end

    test "a drill that passed long ago is a warning that it has stopped" do
      snapshot!()
      {:ok, _} = Content.run()
      Drill.run()

      long_ago = DateTime.utc_now() |> DateTime.add(-20, :day) |> DateTime.to_iso8601()

      Web.SiteSettings.put_setting(
        "restore_drill",
        Jason.encode!(%{
          "at" => long_ago,
          "database" => %{"ok" => true, "detail" => "fine"},
          "content" => %{"ok" => true, "detail" => "fine"}
        })
      )

      assert Drill.stale?()
      assert %{state: :warn, detail: "none in over a week"} = SystemStatus.restore_drill()
    end

    test "run_on_boot/0 catches up only when asked to and only when stale" do
      prev = Application.get_env(:web, :backup_on_boot)
      on_exit(fn -> Application.put_env(:web, :backup_on_boot, prev) end)

      assert :ok = Drill.run_on_boot()
      assert Drill.last() == nil

      Application.put_env(:web, :backup_on_boot, true)
      assert :ok = Drill.run_on_boot()
      assert %{database: %{ok: false}} = Drill.last()

      # Just ran: not stale, so the next boot leaves it alone.
      at = Drill.last().at
      Process.sleep(1100)
      assert :ok = Drill.run_on_boot()
      assert Drill.last().at == at
    end

    test "run_scheduled/0 never raises" do
      assert :ok = Drill.run_scheduled()
    end
  end
end
