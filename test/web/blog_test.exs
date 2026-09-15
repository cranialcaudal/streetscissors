defmodule Web.BlogTest do
  use ExUnit.Case, async: false

  alias Web.Blog

  setup do
    tmp = Path.join(System.tmp_dir!(), "blog-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    original = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)

      if original,
        do: Application.put_env(:web, :blog_path, original),
        else: Application.delete_env(:web, :blog_path)
    end)

    {:ok, tmp: tmp}
  end

  test "parses frontmatter title, description, and date", %{tmp: tmp} do
    File.write!(Path.join(tmp, "a-post.md"), """
    ---
    title: "Quoted Title"
    description: 'Single-quoted description'
    date: 2026-03-15
    ---

    Body text.
    """)

    assert {:ok, post} = Blog.get_post("a-post")
    assert post.title == "Quoted Title"
    assert post.excerpt == "Single-quoted description"
    assert post.date == ~D[2026-03-15]
    refute post.body =~ "---"
    assert post.body =~ "Body text."
  end

  test "tolerates CRLF line endings", %{tmp: tmp} do
    File.write!(
      Path.join(tmp, "crlf.md"),
      "---\r\ntitle: CRLF Post\r\n---\r\nWindows-authored body.\r\n"
    )

    assert {:ok, post} = Blog.get_post("crlf")
    assert post.title == "CRLF Post"
    assert post.body =~ "Windows-authored body."
  end

  test "invalid date falls back to file mtime", %{tmp: tmp} do
    File.write!(Path.join(tmp, "bad-date.md"), """
    ---
    date: not-a-date
    ---
    Body.
    """)

    assert {:ok, post} = Blog.get_post("bad-date")
    assert post.date == NaiveDateTime.to_date(post.mtime)
  end

  test "missing frontmatter falls back to filename title and heuristic excerpt", %{tmp: tmp} do
    File.write!(Path.join(tmp, "some-bare-post.md"), """
    # Heading is skipped

    This line is comfortably longer than forty characters and becomes the excerpt.
    """)

    assert {:ok, post} = Blog.get_post("some-bare-post")
    assert post.title == "Some Bare Post"
    assert post.excerpt =~ "comfortably longer than forty characters"
  end

  test "list_posts sorts by frontmatter date, newest first", %{tmp: tmp} do
    File.write!(Path.join(tmp, "older.md"), "---\ndate: 2026-01-01\n---\nOld.")
    File.write!(Path.join(tmp, "newer.md"), "---\ndate: 2026-06-01\n---\nNew.")

    assert [%{slug: "newer"}, %{slug: "older"}] = Blog.list_posts()
  end

  test "list_posts returns [] when the directory is missing", %{tmp: tmp} do
    File.rm_rf!(tmp)
    assert Blog.list_posts() == []
  end

  test "get_post guards against directory traversal" do
    assert {:error, :not_found} = Blog.get_post("../secret")
  end

  describe "keywords" do
    test "reads a comma-separated frontmatter list", %{tmp: tmp} do
      File.write!(Path.join(tmp, "kw.md"), """
      ---
      keywords: Film, Bowling Green , film
      ---
      Body.
      """)

      assert {:ok, post} = Blog.get_post("kw")
      assert post.keywords == ["film", "bowling-green"]
    end

    test "reads Obsidian's block-list form under the tags alias", %{tmp: tmp} do
      File.write!(Path.join(tmp, "obsidian.md"), """
      ---
      title: Obsidian Post
      tags:
        - ferry
        - night walk
      ---
      Body.
      """)

      assert {:ok, post} = Blog.get_post("obsidian")
      assert post.keywords == ["ferry", "night-walk"]
      # The block list must not swallow the keys around it
      assert post.title == "Obsidian Post"
    end

    test "keywords wins over the tags alias when both are present", %{tmp: tmp} do
      File.write!(Path.join(tmp, "both.md"), """
      ---
      keywords: film
      tags: ferry
      ---
      Body.
      """)

      assert {:ok, post} = Blog.get_post("both")
      assert post.keywords == ["film"]
    end

    test "a post with no keywords reads as an empty list", %{tmp: tmp} do
      File.write!(Path.join(tmp, "none.md"), "Body with no frontmatter at all.")
      assert {:ok, post} = Blog.get_post("none")
      assert post.keywords == []
    end

    test "list_keywords tallies across posts, most-used first", %{tmp: tmp} do
      File.write!(Path.join(tmp, "one.md"), "---\nkeywords: film, nyc\n---\nBody.")
      File.write!(Path.join(tmp, "two.md"), "---\nkeywords: film\n---\nBody.")

      assert Blog.list_keywords() == [{"film", 2}, {"nyc", 1}]
    end
  end

  describe "set_keywords/2" do
    test "rewrites the keywords line, preserving the other frontmatter", %{tmp: tmp} do
      File.write!(Path.join(tmp, "post.md"), """
      ---
      title: Kept Title
      keywords: old
      date: 2026-03-15
      ---

      Body text stays.
      """)

      assert :ok = Blog.set_keywords("post", "New York, film")

      assert {:ok, post} = Blog.get_post("post")
      assert post.keywords == ["new-york", "film"]
      assert post.title == "Kept Title"
      assert post.date == ~D[2026-03-15]
      assert post.body =~ "Body text stays."
    end

    test "adds frontmatter to a post that had none", %{tmp: tmp} do
      File.write!(Path.join(tmp, "bare.md"), "Just a body.\n")

      assert :ok = Blog.set_keywords("bare", "film")

      assert {:ok, post} = Blog.get_post("bare")
      assert post.keywords == ["film"]
      assert post.body =~ "Just a body."
    end

    test "replaces a block list rather than leaving its items behind", %{tmp: tmp} do
      File.write!(Path.join(tmp, "block.md"), """
      ---
      title: Block Post
      tags:
        - ferry
        - night walk
      date: 2026-04-01
      ---

      Body.
      """)

      assert :ok = Blog.set_keywords("block", "film")

      raw = File.read!(Path.join(tmp, "block.md"))
      refute raw =~ "- ferry"
      refute raw =~ "- night walk"

      assert {:ok, post} = Blog.get_post("block")
      assert post.keywords == ["film"]
      assert post.title == "Block Post"
      assert post.date == ~D[2026-04-01]
    end

    test "an empty list removes the key entirely", %{tmp: tmp} do
      File.write!(Path.join(tmp, "clear.md"), "---\ntitle: T\nkeywords: film\n---\nBody.")

      assert :ok = Blog.set_keywords("clear", "")

      refute File.read!(Path.join(tmp, "clear.md")) =~ "keywords:"
      assert {:ok, post} = Blog.get_post("clear")
      assert post.keywords == []
      assert post.title == "T"
    end

    test "guards against directory traversal" do
      assert {:error, :not_found} = Blog.set_keywords("../secret", "film")
    end
  end

  test "posts no longer carry an audio_url — spoken work lives at /logs", %{tmp: tmp} do
    File.mkdir_p!(Path.join(tmp, "audio"))
    File.write!(Path.join([tmp, "audio", "orphan.mp3"]), "not really audio")
    File.write!(Path.join(tmp, "orphan.md"), "Body.")

    assert {:ok, post} = Blog.get_post("orphan")
    refute Map.has_key?(post, :audio_url)
  end
end
