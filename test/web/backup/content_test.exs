defmodule Web.Backup.ContentTest do
  use ExUnit.Case, async: false

  alias Web.Backup.Content

  @env [
    :content_backup_path,
    :content_backup_root,
    :content_backup_sources,
    :content_backup_keep,
    :content_mirror_path
  ]

  setup do
    base = Path.join(System.tmp_dir!(), "content_test_#{System.unique_integer([:positive])}")
    root = Path.join(base, "checkout")
    dir = Path.join(base, "backups")

    File.mkdir_p!(Path.join(root, "content/blog"))
    File.mkdir_p!(Path.join(root, "content/.obsidian"))
    File.write!(Path.join(root, "content/about.md"), "# About\n")
    File.write!(Path.join(root, "content/blog/first.md"), "The first essay.\n")
    File.write!(Path.join(root, "content/blog/Tide's Out — Ærø.md"), "A title with marks.\n")
    File.write!(Path.join(root, "content/.obsidian/app.json"), "{}")
    File.write!(Path.join(root, "content/.obsidian/workspace.json"), ~s({"pane":1}))
    File.write!(Path.join(root, "reading.txt"), "A file beside the code.\n")

    prev = Map.new(@env, &{&1, Application.get_env(:web, &1)})
    Application.put_env(:web, :content_backup_path, dir)
    Application.put_env(:web, :content_backup_root, root)
    Application.put_env(:web, :content_backup_sources, ["content", "reading.txt", "absent"])
    Application.put_env(:web, :content_backup_keep, 3)
    Application.put_env(:web, :content_mirror_path, nil)

    on_exit(fn ->
      File.rm_rf!(base)
      for {key, value} <- prev, do: Application.put_env(:web, key, value)
    end)

    {:ok, base: base, root: root, dir: dir}
  end

  # Filenames carry a whole-second timestamp, so two versions written in the
  # same second would sort by fingerprint instead of by time.
  defp next_second, do: Process.sleep(1100)

  defp names(archive) do
    {:ok, names} = :erl_tar.table(String.to_charlist(archive), [:compressed])
    names |> Enum.map(&List.to_string/1) |> Enum.sort()
  end

  describe "run/0" do
    test "archives every source that exists, by its path from the root", %{dir: dir} do
      assert {:ok, path} = Content.run()
      assert Path.dirname(path) == dir

      assert names(path) == [
               "content/.obsidian/app.json",
               "content/about.md",
               "content/blog/Tide's Out — Ærø.md",
               "content/blog/first.md",
               "reading.txt"
             ]
    end

    test "restoring the archive gives back the files as they were", %{base: base, root: root} do
      {:ok, path} = Content.run()

      restored = Path.join(base, "restored")
      File.mkdir_p!(restored)
      {_, 0} = System.cmd("tar", ["-xzf", path, "-C", restored])

      for name <- ["content/blog/first.md", "content/blog/Tide's Out — Ærø.md", "reading.txt"] do
        assert File.read!(Path.join(restored, name)) == File.read!(Path.join(root, name))
      end
    end

    test "a night with nothing new writes no second version" do
      {:ok, path} = Content.run()
      next_second()

      assert {:unchanged, ^path} = Content.run()
      assert [%{path: ^path}] = Content.list()
    end

    # Obsidian rewrites its workspace file every time a note is opened. If that
    # counted as a change, every run would be a new version of nothing.
    test "the editor's own bookkeeping is not a change", %{root: root} do
      {:ok, path} = Content.run()
      File.write!(Path.join(root, "content/.obsidian/workspace.json"), ~s({"pane":2}))

      assert {:unchanged, ^path} = Content.run()
      refute "content/.obsidian/workspace.json" in names(path)
    end

    test "an edit, a new file and a deleted one are each a new version", %{root: root} do
      {:ok, first} = Content.run()

      next_second()
      File.write!(Path.join(root, "content/blog/first.md"), "The first essay, revised.\n")
      assert {:ok, second} = Content.run()

      next_second()
      File.write!(Path.join(root, "content/blog/second.md"), "Another.\n")
      assert {:ok, third} = Content.run()

      next_second()
      File.rm!(Path.join(root, "content/about.md"))
      assert {:ok, fourth} = Content.run()

      assert length(Enum.uniq([first, second, third, fourth])) == 4
      # Keep is 3 here: the oldest version went, the newest three stay.
      assert Enum.map(Content.list(), & &1.path) == [fourth, third, second]
      refute File.exists?(first)
    end

    test "leaves no scratch folder behind", %{dir: dir} do
      {:ok, _} = Content.run()
      assert Enum.reject(File.ls!(dir), &(&1 =~ ~r/^content-|^last-run$/)) == []
    end

    test "refuses to call an empty archive a backup" do
      Application.put_env(:web, :content_backup_sources, ["absent"])
      assert {:error, :nothing_to_back_up} = Content.run()
      assert Content.list() == []
    end
  end

  describe "verify/2" do
    test "passes the archive it was built from, and fails one that differs", %{root: root} do
      {:ok, path} = Content.run()
      manifest = Content.manifest()
      assert :ok = Content.verify(path, manifest)

      File.write!(Path.join(root, "content/about.md"), "# About, changed after the fact\n")
      assert {:error, :contents_differ} = Content.verify(path, Content.manifest())

      File.write!(Path.join(root, "content/extra.md"), "Not in the archive.\n")
      assert {:error, {:file_count, 5}} = Content.verify(path, Content.manifest())
    end

    test "a truncated archive is unreadable, not a backup", %{dir: dir} do
      {:ok, path} = Content.run()
      torn = Path.join(dir, "torn.tar.gz")
      File.write!(torn, binary_part(File.read!(path), 0, 60))

      assert {:error, _} = Content.verify(torn, Content.manifest())
    end
  end

  describe "when it last ran" do
    test "is nil, and stale, before the first run" do
      assert Content.last_run() == nil
      assert Content.stale?()
    end

    test "is recorded by an unchanged run as well as by a new version" do
      {:ok, _} = Content.run()
      first = Content.last_run()
      assert %DateTime{} = first
      refute Content.stale?()

      next_second()
      {:unchanged, _} = Content.run()
      assert DateTime.compare(Content.last_run(), first) == :gt
    end

    test "run_on_boot/0 catches up only when asked to and only when stale" do
      prev = Application.get_env(:web, :backup_on_boot)
      on_exit(fn -> Application.put_env(:web, :backup_on_boot, prev) end)

      assert :ok = Content.run_on_boot()
      assert Content.list() == []

      Application.put_env(:web, :backup_on_boot, true)
      assert :ok = Content.run_on_boot()
      assert [_] = Content.list()
    end
  end

  describe "the mirror" do
    test "is unavailable when unset, empty, or on a drive that is not there" do
      assert Content.sync_mirror() == :unavailable

      Application.put_env(:web, :content_mirror_path, "")
      assert Content.mirror_dir() == nil

      # The failure this guards against: writing the off-disk copy back onto
      # the disk it was meant to escape, by recreating an unplugged mount.
      absent = "/run/media/nobody/NO_SUCH_DRIVE/streetscissors-backups/content"
      Application.put_env(:web, :content_mirror_path, absent)

      refute Content.mirror_available?()
      assert Content.sync_mirror() == :unavailable
      refute File.exists?("/run/media/nobody")
    end

    test "makes its own folder inside one that is there, and copies every version",
         %{base: base, root: root} do
      drive = Path.join(base, "drive/streetscissors-backups")
      File.mkdir_p!(drive)
      mirror = Path.join(drive, "content")
      Application.put_env(:web, :content_mirror_path, mirror)

      {:ok, first} = Content.run()
      next_second()
      File.write!(Path.join(root, "content/about.md"), "# About, again\n")
      {:ok, second} = Content.run()

      mirrored = mirror |> Content.list_dir() |> Enum.map(&Path.basename(&1.path))
      assert mirrored == [Path.basename(second), Path.basename(first)]

      assert File.read!(Path.join(mirror, Path.basename(second))) == File.read!(second)
      assert {:ok, %{copied: 0, failed: 0, present: 2}} = Content.sync_mirror()
    end

    test "plugging the drive in later brings it up to date", %{base: base} do
      {:ok, path} = Content.run()

      drive = Path.join(base, "drive/streetscissors-backups")
      Application.put_env(:web, :content_mirror_path, Path.join(drive, "content"))
      assert Content.sync_mirror() == :unavailable

      File.mkdir_p!(drive)
      assert {:ok, %{copied: 1, failed: 0, present: 1}} = Content.sync_mirror()
      assert File.exists?(Path.join([drive, "content", Path.basename(path)]))
    end
  end
end
