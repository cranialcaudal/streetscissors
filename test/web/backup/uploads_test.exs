defmodule Web.Backup.UploadsTest do
  use ExUnit.Case, async: false

  alias Web.Backup.Uploads

  setup do
    base = Path.join(System.tmp_dir!(), "uploads_backup_#{System.unique_integer([:positive])}")
    source = Path.join(base, "uploads")
    drive = Path.join(base, "drive/streetscissors-backups")

    File.mkdir_p!(Path.join(source, "logs/2030-03-02-a1b2c3d4"))
    File.mkdir_p!(Path.join(source, "staging"))

    File.write!(
      Path.join(source, "logs/2030-03-02-a1b2c3d4/video.mp4"),
      String.duplicate("v", 4096)
    )

    File.write!(
      Path.join(source, "logs/2030-03-02-a1b2c3d4/poster.jpg"),
      String.duplicate("p", 512)
    )

    File.write!(Path.join(source, "staging/f849b8cb.webm"), String.duplicate("s", 8192))

    prev_uploads = Application.get_env(:web, :uploads_path)
    Application.put_env(:web, :uploads_path, source)

    on_exit(fn ->
      File.rm_rf!(base)
      Application.put_env(:web, :uploads_mirror_path, nil)
      Application.put_env(:web, :uploads_path, prev_uploads)
    end)

    {:ok, source: source, drive: drive, mirror: Path.join(drive, "uploads")}
  end

  test "skips when unset, empty, or on a drive that is not there", %{mirror: mirror} do
    Application.put_env(:web, :uploads_mirror_path, nil)
    assert Uploads.sync() == :skipped

    Application.put_env(:web, :uploads_mirror_path, "")
    assert Uploads.mirror_dir() == nil

    # Neither the mirror nor the folder it sits in exists: the drive is out.
    Application.put_env(:web, :uploads_mirror_path, mirror)
    refute Uploads.available?()
    assert Uploads.sync() == :skipped
    refute File.exists?(mirror)
  end

  test "copies the recordings and leaves the staging takes behind",
       %{source: source, drive: drive, mirror: mirror} do
    File.mkdir_p!(drive)
    Application.put_env(:web, :uploads_mirror_path, mirror)

    assert Uploads.available?()
    assert {:ok, %{files: 2, bytes: 4608}} = Uploads.sync()

    copied = Path.join(mirror, "logs/2030-03-02-a1b2c3d4/video.mp4")

    assert File.read!(copied) ==
             File.read!(Path.join(source, "logs/2030-03-02-a1b2c3d4/video.mp4"))

    refute File.exists?(Path.join(mirror, "staging"))
  end

  # A re-transcode drops the old directory. The drive keeping it is what makes
  # a recording deleted by mistake recoverable.
  test "keeps a recording that was deleted locally",
       %{source: source, drive: drive, mirror: mirror} do
    File.mkdir_p!(drive)
    Application.put_env(:web, :uploads_mirror_path, mirror)
    {:ok, _} = Uploads.sync()

    File.rm_rf!(Path.join(source, "logs/2030-03-02-a1b2c3d4"))
    assert {:ok, %{files: 2}} = Uploads.sync()
    assert File.exists?(Path.join(mirror, "logs/2030-03-02-a1b2c3d4/video.mp4"))
  end

  test "reports a missing source rather than silently succeeding", %{drive: drive, mirror: mirror} do
    File.mkdir_p!(drive)
    Application.put_env(:web, :uploads_mirror_path, mirror)
    Application.put_env(:web, :uploads_path, "/nonexistent/uploads")

    assert {:error, {:source_missing, _}} = Uploads.sync()
  end
end
