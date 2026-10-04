defmodule Web.ShareCardTest do
  use ExUnit.Case, async: false

  alias Web.NegativesFixtures, as: Fixture
  alias Web.ShareCard

  # The smallest PNG that really is one: a single grey pixel. ImageMagick has
  # to decode a frame's source, so the header-only PNGs the layout tests use
  # would not do where it is installed; where it is not, the stub copies it.
  @pixel Base.decode64!(
           "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNgAAAAAgABSK+kcQAAAABJRU5ErkJggg=="
         )

  setup do
    dir = Web.Uploads.dir("cards")
    File.rm_rf!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp post(overrides \\ %{}) do
    Map.merge(
      %{slug: "tides-out", title: "Tide's Out", date: ~D[2030-03-02], draft: false},
      overrides
    )
  end

  describe "a post's card" do
    test "is named by an address that costs nothing to give", %{dir: dir} do
      assert ShareCard.post_url(post()) =~ ~r|^/share/post/tides-out\.png\?v=[0-9a-f]{10}$|
      # Naming a card does not draw it.
      assert File.ls(dir) in [{:ok, []}, {:error, :enoent}]
    end

    test "is drawn once, when asked for, and then is a file", %{dir: dir} do
      assert {:ok, path} = ShareCard.post(post())
      assert Path.dirname(path) == dir
      assert Path.basename(path) =~ ~r|^post-tides-out-[0-9a-f]{10}\.png$|
      assert File.regular?(path)

      # Asked again, it is the same file: nothing is redrawn.
      mtime = File.stat!(path).mtime
      assert ShareCard.post(post()) == {:ok, path}
      assert File.stat!(path).mtime == mtime
      assert File.ls!(dir) == [Path.basename(path)]
    end

    # The response is cached for a year, so a card that changed has to move.
    test "a retitled or redated post has a new address, and the old card is swept",
         %{dir: dir} do
      versions = [
        post(),
        post(%{title: "The Tide Is Out"}),
        post(%{title: "The Tide Is Out", date: ~D[2030-03-03]})
      ]

      assert versions |> Enum.map(&ShareCard.post_url/1) |> Enum.uniq() |> length() == 3

      files = for version <- versions, {:ok, path} = ShareCard.post(version), do: path
      assert File.ls!(dir) == [Path.basename(List.last(files))]
    end

    test "the address and the file carry the same fingerprint" do
      [_, v] = Regex.run(~r/v=([0-9a-f]{10})/, ShareCard.post_url(post()))
      {:ok, path} = ShareCard.post(post())
      assert Path.basename(path) == "post-tides-out-#{v}.png"
    end

    test "another post's card is left alone by the sweep", %{dir: dir} do
      {:ok, other} = ShareCard.post(post(%{slug: "tides-out-again", title: "Again"}))
      {:ok, _} = ShareCard.post(post())
      {:ok, _} = ShareCard.post(post(%{title: "Retitled"}))

      assert Path.basename(other) in File.ls!(dir)
      assert length(File.ls!(dir)) == 2
    end

    # A title is the author's text, and ImageMagick reads `@name` as a file
    # and `%w` as an escape when either arrives as an argument.
    test "a title that looks like an instruction is set as text" do
      assert {:ok, _} = ShareCard.post(post(%{title: "@/etc/passwd and 100%w of it"}))
    end

    test "a draft has no card and no address" do
      assert ShareCard.post_url(post(%{draft: true})) == nil
      assert ShareCard.post(post(%{draft: true})) == :error
    end

    test "is an error, with nothing left behind, when it cannot be drawn", %{dir: dir} do
      System.put_env("STUB_MAGICK_FAIL", "1")
      on_exit(fn -> System.delete_env("STUB_MAGICK_FAIL") end)

      assert ShareCard.post(post()) == :error
      assert File.ls(dir) in [{:ok, []}, {:error, :enoent}]
    end
  end

  describe "a photograph's card" do
    setup do
      root = Fixture.archive!()
      {folder, slug} = Fixture.golden_roll!(root)
      %{root: root, folder: folder, slug: slug}
    end

    test "a printed frame is drawn from its preview", %{folder: folder, dir: dir} do
      File.mkdir_p!(Path.join(folder, "frames"))
      File.write!(Path.join([folder, "frames", "01.png"]), @pixel)

      assert ShareCard.frame_url("013", 1) =~ ~r|^/share/frame/013/1\.jpg\?v=[0-9a-f]{10}$|

      assert {:ok, path} = ShareCard.frame("013", 1)
      assert Path.dirname(path) == dir
      assert Path.basename(path) =~ ~r|^frame-013-1-[0-9a-f]{10}\.jpg$|
      assert ShareCard.frame("013", "1") == {:ok, path}
    end

    test "reprinting a frame moves its address", %{folder: folder} do
      File.mkdir_p!(Path.join(folder, "frames"))
      print = Path.join([folder, "frames", "01.png"])
      File.write!(print, @pixel)
      before = ShareCard.frame_url("013", 1)

      File.write!(print, @pixel <> "a different print")
      refute ShareCard.frame_url("013", 1) == before
    end

    test "a frame that was never printed has neither" do
      assert ShareCard.frame_url("013", 7) == nil
      assert ShareCard.frame("013", 7) == :error
      assert ShareCard.frame("999", 1) == :error
    end

    test "a roll is drawn from its sheet", %{root: root, slug: slug} do
      File.write!(Path.join([root, "Contact Sheets", "#{slug}.png"]), @pixel)
      sheet = %{filename: "#{slug}.png", roll: "013"}

      assert ShareCard.sheet_url(sheet) =~ ~r|^/share/roll/013\.jpg\?v=[0-9a-f]{10}$|
      assert {:ok, path} = ShareCard.sheet(sheet)
      assert Path.basename(path) =~ ~r|^roll-013-[0-9a-f]{10}\.jpg$|
    end

    test "a sheet that is not there has neither" do
      sheet = %{filename: "roll099_missing.png", roll: "099"}
      assert ShareCard.sheet_url(sheet) == nil
      assert ShareCard.sheet(sheet) == :error
    end
  end
end
