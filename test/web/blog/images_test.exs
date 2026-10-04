defmodule Web.Blog.ImagesTest do
  use ExUnit.Case, async: false

  alias Web.Blog.Images

  setup do
    dir = Web.Uploads.dir("images")
    File.rm_rf!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    source = Path.join(System.tmp_dir!(), "upload-#{System.unique_integer([:positive])}")
    File.write!(source, "the bytes of a picture")
    on_exit(fn -> File.rm(source) end)

    {:ok, dir: dir, source: source}
  end

  # The library used to write into priv/static in the checkout, which a
  # release does not serve from: an uploaded image answered 404 until the
  # next deploy. The uploads root is read from disk on every request.
  test "an upload lands under the uploads root, at an address that is served at once",
       %{dir: dir, source: source} do
    path = Images.store(source, "Ferry At Dusk.PNG")

    assert path =~ ~r{^/uploads/images/ferry-at-dusk-\d+\.png$}
    assert File.read!(Path.join(dir, Path.basename(path))) == "the bytes of a picture"
    assert Web.ContentHealth.ask(path) == :ok
  end

  test "two uploads of one filename never collide", %{source: source} do
    refute Images.store(source, "scan.png") == Images.store(source, "scan.png")
    assert length(Enum.reject(Images.list(), & &1.legacy)) == 2
  end

  test "a name with nothing sluggable in it still gets a name", %{source: source} do
    assert Images.store(source, "???.jpg") =~ ~r{^/uploads/images/image-\d+\.jpg$}
  end

  test "list/0 gives each image's address, and skips what is not an image",
       %{dir: dir, source: source} do
    path = Images.store(source, "scan.png")
    File.write!(Path.join(dir, "notes.txt"), "not a picture")

    assert [%{path: ^path, legacy: false, name: name}] = Enum.reject(Images.list(), & &1.legacy)
    assert name == Path.basename(path)
  end

  test "delete/1 removes an image, and will not be talked out of its folder",
       %{dir: dir, source: source} do
    path = Images.store(source, "scan.png")
    outside = Path.join(Path.dirname(dir), "outside.png")
    File.write!(outside, "elsewhere")
    on_exit(fn -> File.rm(outside) end)

    assert Images.delete(Path.basename(path)) == :ok
    assert Enum.reject(Images.list(), & &1.legacy) == []

    assert Images.delete("../outside.png") == {:error, :unsafe}
    assert File.exists?(outside)
  end
end
