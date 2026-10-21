defmodule Web.AuthorPortraitsTest do
  # The About page shows one picture of the author, a different one each time
  # it loads. The pictures are whatever image files are in the uploads root's
  # `about` folder.
  use ExUnit.Case, async: false

  alias Web.Author

  # These make and inspect real pictures with ImageMagick 7's `magick`; where it
  # is not installed (Ubuntu's apt ships version 6) they skip, as the tests that
  # want the real ffmpeg or node do.
  @no_magick is_nil(System.find_executable("magick")) && "ImageMagick 7 (magick) is not installed"

  setup do
    dir = Path.join(Web.Uploads.root(), "about")
    File.mkdir_p!(dir)

    for name <- ~w(b.jpg a.png c.webp notes.txt .hidden.jpg),
        do: File.write!(Path.join(dir, name), "x")

    on_exit(fn -> File.rm_rf!(dir) end)
    :ok
  end

  test "the pictures are the folder's image files, in order of name" do
    assert Author.portraits() ==
             ~w(/uploads/about/a.png /uploads/about/b.jpg /uploads/about/c.webp)
  end

  test "the one shown is drawn by lot, unless the reader chose one" do
    seen = for _ <- 1..60, into: MapSet.new(), do: elem(Author.portrait(), 0)
    assert MapSet.size(seen) == 3
    assert {"/uploads/about/b.jpg", 2, 3} = Author.portrait(2)
    # a place that does not exist is drawn by lot like no choice at all
    assert {_, place, 3} = Author.portrait(9)
    assert place in 1..3
  end

  @tag skip: @no_magick
  test "a picture taken in is shrunk, kept as a JPEG and joins the turn" do
    source = Path.join(System.tmp_dir!(), "portrait-#{System.unique_integer([:positive])}.png")
    {_, 0} = System.cmd("magick", ["-size", "3000x2000", "xc:gray", source])
    on_exit(fn -> File.rm(source) end)

    assert {:ok, "/uploads/about/" <> name = path} = Author.add_portrait(source)
    assert path in Author.portraits()
    kept = Path.join([Web.Uploads.root(), "about", name])
    {size, 0} = System.cmd("magick", ["identify", "-format", "%wx%h", kept])
    assert size == "1600x1067"
  end

  @tag skip: @no_magick
  test "the same picture sent twice is kept once" do
    source = Path.join(System.tmp_dir!(), "twice-#{System.unique_integer([:positive])}.png")
    {_, 0} = System.cmd("magick", ["-size", "300x200", "gradient:", source])
    on_exit(fn -> File.rm(source) end)

    assert {:ok, first} = Author.add_portrait(source)
    count = length(Author.portraits())
    assert {:ok, ^first} = Author.add_portrait(source)
    assert length(Author.portraits()) == count
  end

  @tag skip: @no_magick
  test "what is not a picture is refused, and nothing is kept" do
    source =
      Path.join(System.tmp_dir!(), "not-a-picture-#{System.unique_integer([:positive])}.jpg")

    File.write!(source, "words")
    on_exit(fn -> File.rm(source) end)
    before = Author.portraits()
    assert {:error, _} = Author.add_portrait(source)
    assert Author.portraits() == before
  end

  test "a picture removed is set aside, not destroyed" do
    assert :ok = Author.remove_portrait("/uploads/about/b.jpg")
    refute "/uploads/about/b.jpg" in Author.portraits()
    assert File.exists?(Path.join([Web.Uploads.root(), "about", "removed", "b.jpg"]))
    assert {:error, :not_found} = Author.remove_portrait("/uploads/about/../../etc/passwd")
  end

  test "with no pictures there is none" do
    File.rm_rf!(Path.join(Web.Uploads.root(), "about"))
    assert Author.portrait() == nil
  end
end
