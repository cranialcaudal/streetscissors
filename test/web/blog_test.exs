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

  describe "drafts" do
    setup %{tmp: tmp} do
      File.write!(
        Path.join(tmp, "out.md"),
        "---\ntitle: Out\ndate: 2026-07-02\n---\n\nPublished.\n"
      )

      File.write!(
        Path.join(tmp, "wip.md"),
        "---\ntitle: Work In Progress\ndate: 2026-07-03\ndraft: true\n---\n\nNot yet.\n"
      )

      :ok
    end

    test "a draft is off every public listing, and on the admin's" do
      assert Enum.map(Blog.list_posts(), & &1.slug) == ["out"]
      assert Enum.map(Blog.list_all_posts(), & &1.slug) == ["wip", "out"]
      assert Blog.list_keywords() == []
    end

    test "a draft is not found unless drafts are asked for" do
      assert {:error, :not_found} = Blog.get_post("wip")
      assert {:ok, %{draft: true, title: "Work In Progress"}} = Blog.get_post("wip", drafts: true)
      assert {:ok, %{draft: false}} = Blog.get_post("out")
    end

    test "draft takes the usual spellings of yes, and anything else is published", %{tmp: tmp} do
      for {value, expected} <- [{"true", true}, {"Yes", true}, {"false", false}, {"", false}] do
        File.write!(Path.join(tmp, "v.md"), "---\ntitle: V\ndraft: #{value}\n---\n\nBody.\n")
        assert {:ok, %{draft: ^expected}} = Blog.get_post("v", drafts: true)
      end
    end

    test "publishing removes the line, and unpublishing puts it back", %{tmp: tmp} do
      assert :ok = Blog.set_draft("wip", false)
      assert {:ok, %{draft: false, title: "Work In Progress"}} = Blog.get_post("wip")
      refute File.read!(Path.join(tmp, "wip.md")) =~ "draft"

      assert :ok = Blog.set_draft("wip", true)
      assert {:error, :not_found} = Blog.get_post("wip")
      assert File.read!(Path.join(tmp, "wip.md")) =~ "\ndraft: true\n---\n\nNot yet."
    end

    test "a post with no frontmatter gains a block as a draft and loses it again", %{tmp: tmp} do
      path = Path.join(tmp, "bare.md")
      File.write!(path, "Just a paragraph.\n")

      :ok = Blog.set_draft("bare", true)
      assert File.read!(path) == "---\ndraft: true\n---\n\nJust a paragraph.\n"

      :ok = Blog.set_draft("bare", false)
      assert File.read!(path) == "Just a paragraph.\n"
    end
  end

  describe "create_draft/2" do
    test "starts a post from the built-in template when the vault has none", %{tmp: tmp} do
      assert {:ok, "tides-out"} = Blog.create_draft("Tide's Out", ~D[2030-03-02])

      text = File.read!(Path.join(tmp, "tides-out.md"))
      assert text =~ ~s(title: "Tide's Out")
      assert text =~ ~s(date: "2030-03-02")
      assert text =~ "\ndraft: true\n"

      assert {:ok, post} = Blog.get_post("tides-out", drafts: true)
      assert post.title == "Tide's Out"
      assert post.date == ~D[2030-03-02]
      assert post.draft
      # The template's sample values are not carried into a real post.
      assert post.keywords == []
      refute post.described
    end

    # The same frontmatter a post begun in Obsidian gets, comments and all.
    test "uses the vault's own template when there is one" do
      vault = Path.join(System.tmp_dir!(), "vault-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(vault, "blog"))
      File.mkdir_p!(Path.join(vault, "templates"))
      Application.put_env(:web, :blog_path, Path.join(vault, "blog"))
      on_exit(fn -> File.rm_rf!(vault) end)

      File.write!(Path.join(vault, "templates/blog-template.md"), """
      ---
      title: "Your Blog Post Title"
      date: "2026-05-30"
      # a comment the author left for themselves
      keywords: film, darkroom
      location:
      ---

      Opening line from the vault's template.
      """)

      assert {:ok, "a-walk"} = Blog.create_draft("A Walk", ~D[2030-03-02])
      text = File.read!(Path.join(vault, "blog/a-walk.md"))

      assert text =~ "# a comment the author left for themselves"
      assert text =~ "location:"
      assert text =~ "Opening line from the vault's template."
      refute text =~ "film, darkroom"

      assert {:ok, %{title: "A Walk", keywords: [], draft: true}} =
               Blog.get_post("a-walk", drafts: true)
    end

    test "refuses a name already taken, and a title that is nothing" do
      assert {:ok, "once"} = Blog.create_draft("Once")
      assert {:error, :exists} = Blog.create_draft("once")
      assert {:error, :blank} = Blog.create_draft("  ?!  ")
    end
  end

  describe "editing a post's source" do
    setup do
      vault = Path.join(System.tmp_dir!(), "vault-#{System.unique_integer([:positive])}")
      blog = Path.join(vault, "blog")
      File.mkdir_p!(blog)
      Application.put_env(:web, :blog_path, blog)
      on_exit(fn -> File.rm_rf!(vault) end)

      File.write!(Path.join(blog, "essay.md"), "---\ntitle: Essay\n---\n\nAs opened.\n")
      {:ok, vault: vault, path: Path.join(blog, "essay.md")}
    end

    test "saves over the revision it was opened at, and hands back the new one", %{path: path} do
      {:ok, %{content: content, revision: revision}} = Blog.read_source("essay")
      assert content =~ "As opened."

      assert {:ok, next} = Blog.write_source("essay", "Rewritten.\n", revision)
      assert File.read!(path) == "Rewritten.\n"
      assert next != revision

      # The new revision is the one to save over next.
      assert {:ok, _} = Blog.write_source("essay", "Rewritten again.\n", next)
      refute File.exists?(path <> ".saving")
    end

    # The whole point: an edit made in Obsidian while the admin tab sat open.
    test "refuses to save over a file that changed on disk meanwhile", %{path: path} do
      {:ok, %{revision: revision}} = Blog.read_source("essay")
      File.write!(path, "Edited in Obsidian.\n")

      assert {:error, :conflict, %{content: "Edited in Obsidian.\n", revision: theirs}} =
               Blog.write_source("essay", "Edited in the admin.\n", revision)

      assert File.read!(path) == "Edited in Obsidian.\n"
      assert theirs != revision
    end

    test "forcing the save keeps the version it replaces in the vault's trash",
         %{vault: vault, path: path} do
      {:ok, %{revision: revision}} = Blog.read_source("essay")
      File.write!(path, "Edited in Obsidian.\n")

      assert {:ok, _} =
               Blog.write_source("essay", "Edited in the admin.\n", revision, force: true)

      assert File.read!(path) == "Edited in the admin.\n"

      assert [kept] = File.ls!(Path.join(vault, ".trash"))
      assert kept =~ ~r/^essay \(replaced \d{8}-\d{6}\)\.md$/
      assert File.read!(Path.join([vault, ".trash", kept])) == "Edited in Obsidian.\n"
    end

    test "a save that matches the disk leaves nothing in the trash", %{vault: vault} do
      {:ok, %{revision: revision}} = Blog.read_source("essay")
      {:ok, _} = Blog.write_source("essay", "Rewritten.\n", revision, force: true)
      refute File.exists?(Path.join(vault, ".trash"))
    end

    test "guards against directory traversal" do
      assert {:error, :not_found} = Blog.read_source("../secrets")
      assert {:error, :not_found} = Blog.write_source("../secrets", "x", "anything")
    end

    test "preview/2 reads text the way a saved post would be read" do
      post =
        Blog.preview(
          "essay",
          "---\ntitle: Retitled\nkeywords: Film, film\ndraft: true\n---\n\nBody.\n"
        )

      assert %{title: "Retitled", keywords: ["film"], draft: true} = post
      assert String.trim(post.body) == "Body."
    end

    test "mark_draft/2 changes that one line and nothing else" do
      text = "---\ntitle: Essay\n# a note\nkeywords: film\n---\n\nBody.\n"

      drafted = Blog.mark_draft(text, true)
      assert drafted == "---\ntitle: Essay\n# a note\nkeywords: film\ndraft: true\n---\n\nBody.\n"
      assert Blog.mark_draft(drafted, false) == text
      assert Blog.mark_draft(Blog.mark_draft(text, true), true) == drafted
    end
  end
end
