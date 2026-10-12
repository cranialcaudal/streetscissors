defmodule Web.AuthorPortraitsTest do
  # The About page shows one picture of the author and changes it every four
  # hours. The pictures are whatever image files are in the uploads root's
  # `about` folder.
  use ExUnit.Case, async: false

  alias Web.Author

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

  test "each has a turn of four hours, and they come round again" do
    hour = 3600
    assert {"/uploads/about/a.png", 1, 3} = Author.portrait(0)
    assert {"/uploads/about/a.png", 1, 3} = Author.portrait(4 * hour - 1)
    assert {"/uploads/about/b.jpg", 2, 3} = Author.portrait(4 * hour)
    assert {"/uploads/about/c.webp", 3, 3} = Author.portrait(8 * hour)
    assert {"/uploads/about/a.png", 1, 3} = Author.portrait(12 * hour)
  end

  test "with no pictures there is none" do
    File.rm_rf!(Path.join(Web.Uploads.root(), "about"))
    assert Author.portrait() == nil
  end
end
