defmodule Web.Fitness.PhotosTest do
  # Not async: the photographs folder is one directory for the suite.
  use ExUnit.Case

  alias Web.Fitness.Photos

  setup do
    File.rm_rf!(Photos.dir())
    src = Path.join(System.tmp_dir!(), "photo-#{System.unique_integer([:positive])}.jpg")
    File.write!(src, "not really a jpeg")
    on_exit(fn -> File.rm_rf!(Photos.dir()) end)
    %{src: src}
  end

  test "a photograph is filed under its day, numbered, private", %{src: src} do
    assert {:ok, %{file: "01.jpg"}} = Photos.store(~D[2026-10-26], src, ".JPEG")
    assert {:ok, %{file: "02.png"}} = Photos.store(~D[2026-10-26], src, ".png")

    assert [%{date: ~D[2026-10-26], files: ["01.jpg", "02.png"]}] = Photos.list()

    {:ok, path} = Photos.path("2026-10-26", "01.jpg")
    assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600
    assert File.stat!(Path.dirname(path)).mode |> Bitwise.band(0o777) == 0o700
  end

  test "only images are taken", %{src: src} do
    assert Photos.store(~D[2026-10-26], src, ".heic") == {:error, :type}
    assert Photos.store(~D[2026-10-26], src, ".svg") == {:error, :type}
  end

  test "an address that is not a stored photograph names nothing", %{src: src} do
    {:ok, _} = Photos.store(~D[2026-10-26], src, ".jpg")

    for {date, file} <- [
          {"2026-10-26", "../../x.jpg"},
          {"../2026-10-26", "01.jpg"},
          {"2026-10-26", "01.svg"},
          {"2026-10-27", "01.jpg"},
          {"not-a-date", "01.jpg"}
        ] do
      assert Photos.path(date, file) == :error, "#{date}/#{file}"
    end
  end

  test "the folder is beside the uploads root, never under it" do
    Application.delete_env(:web, :fitness_photos_path)

    try do
      uploads = Path.expand(Web.Uploads.root())
      refute String.starts_with?(Photos.dir(), uploads <> "/")
      assert Path.dirname(Photos.dir()) == Path.dirname(uploads)
    after
      Application.put_env(
        :web,
        :fitness_photos_path,
        Path.expand("../../tmp/test_fitness_photos", __DIR__)
      )
    end
  end

  test "setting one aside takes it off the list and keeps it", %{src: src} do
    {:ok, _} = Photos.store(~D[2026-10-26], src, ".jpg")
    assert :ok = Photos.delete("2026-10-26", "01.jpg")

    assert Photos.list() == []
    assert [_] = Path.wildcard(Path.join([Photos.dir(), ".trash", "2026-10-26", "*-01.jpg"]))
  end

  test "the nightly copy carries them", %{src: src} do
    dest = Web.Backup.FitnessPhotos.backup_dir()
    File.rm_rf!(dest)
    on_exit(fn -> File.rm_rf!(dest) end)

    {:ok, _} = Photos.store(~D[2026-10-26], src, ".jpg")
    assert {:ok, _} = Web.Backup.FitnessPhotos.run_scheduled()
    assert File.regular?(Path.join([dest, "2026-10-26", "01.jpg"]))
  end
end
