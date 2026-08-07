defmodule Web.Backup.PhotosTest do
  use ExUnit.Case, async: false

  alias Web.Backup.Photos

  setup do
    root = Path.join(System.tmp_dir!(), "photos_test_#{System.unique_integer([:positive])}")
    source = Path.join(root, "Negatives")
    dest = Path.join(root, "mirror")

    File.mkdir_p!(Path.join(source, "35mm Film"))
    File.write!(Path.join(source, "catalog.csv"), "roll,format\n007,35mm\n")
    File.write!(Path.join([source, "35mm Film", "roll007.jpg"]), String.duplicate("x", 2048))
    File.write!(Path.join([source, "35mm Film", "roll008.jpg"]), String.duplicate("y", 4096))

    prev_neg = Application.get_env(:web, :negatives_path)
    Application.put_env(:web, :negatives_path, source)

    on_exit(fn ->
      File.rm_rf!(root)
      Application.put_env(:web, :photos_mirror_path, nil)

      if prev_neg,
        do: Application.put_env(:web, :negatives_path, prev_neg),
        else: Application.delete_env(:web, :negatives_path)
    end)

    {:ok, source: source, dest: dest}
  end

  describe "when the drive is not there" do
    test "skips when no mirror is configured" do
      Application.put_env(:web, :photos_mirror_path, nil)
      assert Photos.sync() == :skipped
      refute Photos.available?()
    end

    test "treats an empty string as unset" do
      Application.put_env(:web, :photos_mirror_path, "")
      assert Photos.mirror_dir() == nil
      assert Photos.sync() == :skipped
    end

    test "skips rather than recreating an unplugged drive's directory" do
      # The failure this guards against: copying 317 MB of negatives onto the
      # very disk they were supposed to escape, by mkdir -p'ing a path whose
      # mount point is gone.
      absent = "/run/media/cesar/NO_SUCH_DRIVE/negatives"
      Application.put_env(:web, :photos_mirror_path, absent)

      assert Photos.sync() == :skipped
      refute File.exists?(absent)
    end
  end

  describe "syncing" do
    setup %{dest: dest} do
      File.mkdir_p!(dest)
      Application.put_env(:web, :photos_mirror_path, dest)
      :ok
    end

    test "copies the archive contents, not a nested directory", %{source: source, dest: dest} do
      assert {:ok, summary} = Photos.sync()

      # Contents land directly in the mirror. Without the trailing slash on the
      # rsync source this would nest a Negatives/ dir on every single run.
      assert File.exists?(Path.join(dest, "catalog.csv"))
      assert File.exists?(Path.join([dest, "35mm Film", "roll007.jpg"]))
      refute File.exists?(Path.join(dest, "Negatives"))

      assert summary.files == Photos.count_files(source)
      assert summary.bytes == Photos.total_bytes(source)
    end

    test "file contents survive intact", %{source: source, dest: dest} do
      {:ok, _} = Photos.sync()

      original = Path.join([source, "35mm Film", "roll008.jpg"])
      copied = Path.join([dest, "35mm Film", "roll008.jpg"])
      assert File.read!(copied) == File.read!(original)
    end

    test "a second sync is a no-op rather than a full recopy", %{dest: dest} do
      {:ok, first} = Photos.sync()
      mtime_before = File.stat!(Path.join(dest, "catalog.csv")).mtime

      {:ok, second} = Photos.sync()

      assert second.files == first.files
      assert second.bytes == first.bytes
      # rsync leaves an unchanged file alone, so its mtime is untouched.
      assert File.stat!(Path.join(dest, "catalog.csv")).mtime == mtime_before
    end

    test "picks up newly added scans", %{source: source, dest: dest} do
      {:ok, first} = Photos.sync()

      File.write!(Path.join([source, "35mm Film", "roll009.jpg"]), String.duplicate("z", 1024))
      {:ok, second} = Photos.sync()

      assert second.files == first.files + 1
      assert File.exists?(Path.join([dest, "35mm Film", "roll009.jpg"]))
    end

    test "KEEPS files deleted from the source — the point of omitting --delete",
         %{source: source, dest: dest} do
      {:ok, _} = Photos.sync()
      copied = Path.join([dest, "35mm Film", "roll007.jpg"])
      assert File.exists?(copied)

      # Delete a scan locally, by accident or otherwise, and sync again.
      File.rm!(Path.join([source, "35mm Film", "roll007.jpg"]))
      assert {:ok, _} = Photos.sync()

      # A backup that propagated the deletion would faithfully reproduce the
      # accident it exists to protect against.
      assert File.exists?(copied)
    end

    test "reports a missing source rather than silently succeeding" do
      Application.put_env(:web, :negatives_path, "/nonexistent/negatives/archive")
      assert {:error, {:source_missing, _}} = Photos.sync()
    end
  end
end
