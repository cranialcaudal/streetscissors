defmodule Web.NegativesSizesTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Web.Negatives
  alias Web.NegativesFixtures, as: Fixture

  # A real, one-pixel PNG: where ImageMagick is installed it has to be able
  # to decode what it is asked to shrink.
  @pixel Base.decode64!(
           "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNgAAAAAgABSK+kcQAAAABJRU5ErkJggg=="
         )

  setup do
    root = Fixture.archive!()
    {folder, slug} = Fixture.golden_roll!(root)
    File.mkdir_p!(Path.join(folder, "frames"))
    File.write!(Path.join([folder, "frames", "01.png"]), @pixel)
    File.write!(Path.join([root, "Contact Sheets", "#{slug}.png"]), @pixel)

    %{root: root, folder: folder, slug: slug}
  end

  describe "addresses" do
    test "sized_url/2 adds the width, whether or not the address has a query" do
      assert Negatives.sized_url("/negatives/frame/13/1", 480) == "/negatives/frame/13/1?w=480"

      assert Negatives.sized_url("/negatives/preview/roll013.png?v=17", 960) ==
               "/negatives/preview/roll013.png?v=17&w=960"
    end

    test "sized_url/2 will not name a width the archive does not keep" do
      assert_raise FunctionClauseError, fn ->
        Negatives.sized_url("/negatives/frame/13/1", 123)
      end
    end

    test "srcset/1 offers every width, narrowest first, then the full preview" do
      assert Negatives.srcset("/negatives/frame/13/1") ==
               "/negatives/frame/13/1?w=480 480w, /negatives/frame/13/1?w=960 960w, " <>
                 "/negatives/frame/13/1 2000w"
    end
  end

  describe "a frame's narrower copies" do
    test "are kept beside its preview, one file per width", %{folder: folder} do
      assert {:ok, preview} = Negatives.frame_preview_path("013", 1)
      assert preview == Path.join([folder, "frames", "previews", "01.webp"])

      assert {:ok, small} = Negatives.frame_preview_path("013", 1, 480)
      assert small == Path.join([folder, "frames", "previews", "01-480.webp"])
      assert File.regular?(small)

      assert {:ok, medium} = Negatives.frame_preview_path("013", 1, 960)
      assert medium == Path.join([folder, "frames", "previews", "01-960.webp"])
    end

    test "are made once", %{folder: folder} do
      {:ok, small} = Negatives.frame_preview_path("013", 1, 480)
      mtime = File.stat!(small).mtime

      assert {:ok, ^small} = Negatives.frame_preview_path("013", 1, 480)
      assert File.stat!(small).mtime == mtime
      assert length(File.ls!(Path.join([folder, "frames", "previews"]))) == 2
    end

    # The whitelist is what stops ?w= being a way to fill the disk.
    test "an unlisted width is the full preview, and writes nothing new", %{folder: folder} do
      {:ok, preview} = Negatives.frame_preview_path("013", 1)

      for width <- [123, 0, -480, 2000, 99_999] do
        assert Negatives.frame_preview_path("013", 1, width) == {:ok, preview}
      end

      assert File.ls!(Path.join([folder, "frames", "previews"])) == ["01.webp"]
    end

    test "a frame that is not there is still an error at any width" do
      assert Negatives.frame_preview_path("013", 9, 480) == :error
    end
  end

  test "a sheet's narrower copy sits beside its preview", %{root: root, slug: slug} do
    assert {:ok, small} = Negatives.preview_path("#{slug}.png", 480)
    assert small == Path.join([root, "Contact Sheets", "previews", "#{slug}-480.webp"])
  end

  describe "over HTTP" do
    test "?w= serves the narrower copy of a frame and of a sheet",
         %{conn: conn, folder: folder, slug: slug} do
      assert conn |> get("/negatives/frame/013/1?w=480") |> response(200)
      assert File.regular?(Path.join([folder, "frames", "previews", "01-480.webp"]))

      assert conn |> get("/negatives/preview/#{slug}.png?w=960") |> response(200)
    end

    test "a width that is not kept, or is not a number, is the full preview",
         %{conn: conn, folder: folder} do
      for w <- ["123", "abc", "480px", "", "999999999999999999999"] do
        assert conn |> get("/negatives/frame/013/1", %{"w" => w}) |> response(200)
      end

      assert File.ls!(Path.join([folder, "frames", "previews"])) == ["01.webp"]
    end

    test "the strip of prints asks for the narrowest copy, the frame's own page offers them all",
         %{conn: conn} do
      {:ok, _view, sheet} = live(conn, "/negatives/roll/013")
      assert sheet =~ ~s(src="/negatives/frame/13/1?w=480")

      {:ok, _view, frame} = live(conn, "/negatives/roll/013/frame/1")
      assert frame =~ "/negatives/frame/13/1?w=480 480w"
      assert frame =~ "/negatives/frame/13/1?w=960 960w"
      assert frame =~ "/negatives/frame/13/1 2000w"
    end
  end
end
