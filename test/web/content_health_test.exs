defmodule Web.ContentHealthTest do
  use WebWeb.ConnCase

  alias Web.ContentHealth

  # A vault of its own: a blog folder beside an about page, so nothing here
  # depends on what the committed fixtures happen to link to.
  setup do
    vault = Path.join(System.tmp_dir!(), "health-#{System.unique_integer([:positive])}")
    blog = Path.join(vault, "blog")
    File.mkdir_p!(blog)
    original = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, blog)

    on_exit(fn ->
      File.rm_rf!(vault)
      Application.put_env(:web, :blog_path, original)
    end)

    post = fn slug, text -> File.write!(Path.join(blog, slug <> ".md"), text) end

    post.("target", """
    ---
    title: Target
    description: "Somewhere for a link to land."
    keywords: film
    ---

    A post that exists.
    """)

    {:ok, vault: vault, post: post}
  end

  defp problems(report, label) do
    for %{source: %{label: ^label}, target: target, problem: problem} <- report.broken,
        into: %{},
        do: {target, problem}
  end

  describe "ask/1" do
    test "answers the way the site would" do
      assert ContentHealth.ask("/blog/target") == :ok
      assert ContentHealth.ask("/how-to") == :ok
      assert ContentHealth.ask("/blog/no-such-post") == :missing
      assert ContentHealth.ask("/no/such/route") == :missing
      # A retired address still works, and says where it went.
      assert ContentHealth.ask("/audio") == {:moved, "/logs"}
      assert ContentHealth.ask("/robots.txt") == :ok
    end

    test "is not counted as a visit" do
      before = Web.Repo.aggregate(Web.Analytics.Hit, :count)
      ContentHealth.ask("/blog/target")
      Process.sleep(50)
      assert Web.Repo.aggregate(Web.Analytics.Hit, :count) == before
    end
  end

  describe "links" do
    setup %{post: post} do
      post.("linker", """
      ---
      title: Linker
      description: "A post full of links."
      keywords: film
      ---

      [Fine](/blog/target), [also fine](/how-to#part-1), and [with a query](/blog?keyword=film).

      [Gone](/blog/renamed-away). [Retired](/manuscripts/latent-sensus/old).

      [Elsewhere](https://example.com/page) and [here by its full name](http://localhost/blog/nope).

      [From the vault](notes/idea.md). [Just an anchor](#top). [Mail](mailto:a@example.com).

      ![A picture that is not there](/uploads/images/never-uploaded.png)
      """)

      {:ok, report: ContentHealth.report()}
    end

    test "a link to nothing is reported with the post it is in", %{report: report} do
      found = problems(report, "Linker")

      assert found["/blog/renamed-away"] == "there is nothing at that address"
      assert found["/uploads/images/never-uploaded.png"] == "there is nothing at that address"
      # The site's own name in front does not hide a broken path.
      assert found["http://localhost/blog/nope"] == "there is nothing at that address"

      assert %{source: %{edit: "/admin/blog/linker/edit"}} =
               Enum.find(report.broken, &(&1.target == "/blog/renamed-away"))
    end

    test "a retired address is reported with where it goes now", %{report: report} do
      assert problems(report, "Linker")["/manuscripts/latent-sensus/old"] =~
               "an old address: it now redirects to /blog"
    end

    test "a link relative to the vault is reported as one", %{report: report} do
      assert problems(report, "Linker")["notes/idea.md"] =~ "works in Obsidian, not on the site"
    end

    test "working links, anchors and mail are left alone", %{report: report} do
      found = problems(report, "Linker")

      for fine <- ["/blog/target", "/how-to#part-1", "/blog?keyword=film", "#top"] do
        refute Map.has_key?(found, fine), "#{fine} was reported"
      end

      refute Enum.any?(Map.keys(found), &String.starts_with?(&1, "mailto:"))
    end

    test "links to other sites are counted, not followed", %{report: report} do
      refute Map.has_key?(problems(report, "Linker"), "https://example.com/page")
      assert report.external >= 1
    end
  end

  test "an embed that names nothing is listed; one that resolves is not", %{post: post} do
    post.("embeds", """
    ---
    title: Embeds
    description: "Two embeds."
    keywords: film
    ---

    ![[roll001]]

    ![[roll999/4|A frame that was never printed]]
    """)

    report = ContentHealth.report()
    targets = for %{source: %{label: "Embeds"}, target: target} <- report.embeds, do: target

    assert targets == ["![[roll999/4|A frame that was never printed]]"]
  end

  describe "posts missing their particulars" do
    test "lists published posts without a description or keywords, and says which",
         %{post: post} do
      post.("bare", "Only a paragraph, comfortably long enough to be taken for an excerpt.\n")
      post.("half", "---\ntitle: Half\nkeywords: film\n---\n\nKeywords but no description.\n")

      missing = Map.new(ContentHealth.report().posts, &{&1.post.slug, &1.missing})

      assert missing["bare"] == [:description, :keywords]
      assert missing["half"] == [:description]
      refute Map.has_key?(missing, "target")
    end

    test "a draft is allowed to be unfinished", %{post: post} do
      post.("wip", "---\ntitle: WIP\ndraft: true\n---\n\nNot yet.\n")
      refute Enum.any?(ContentHealth.report().posts, &(&1.post.slug == "wip"))
    end
  end

  describe "files nothing uses" do
    setup do
      dir = Web.Uploads.dir("images")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, images: dir}
    end

    test "a library image no page embeds is listed, and an embedded one is not",
         %{post: post, images: images} do
      File.write!(Path.join(images, "used-1.png"), "png")
      File.write!(Path.join(images, "spare-2.png"), "png")

      post.("pictures", """
      ---
      title: Pictures
      description: "One picture."
      keywords: film
      ---

      ![Used](/uploads/images/used-1.png)
      """)

      report = ContentHealth.report()
      unused = for %{kind: :image, name: name} <- report.unused, do: name

      assert "spare-2.png" in unused
      refute "used-1.png" in unused
      # And the one that is embedded really is served.
      refute Map.has_key?(problems(report, "Pictures"), "/uploads/images/used-1.png")
    end
  end

  test "the fixture regimen joins up, and a roll never analysed is in the archive list" do
    report = ContentHealth.report()

    refute Enum.any?(report.unused, &(&1.kind in [:module, :day]))
    refute Enum.any?(report.broken, &String.starts_with?(&1.target, "[["))

    assert %{reason: reason, fix: "negatives --analyze 001"} =
             Enum.find(report.archive, &(&1.roll == "001"))

    assert reason =~ "never been analysed"
  end

  test "count/1 is what wants attention; an unprinted roll's marks do not" do
    quiet = %{
      broken: [],
      embeds: [],
      posts: [],
      unused: [],
      archive: [%{roll: "001", prints: 0}]
    }

    assert ContentHealth.count(quiet) == 0
    assert ContentHealth.count(%{quiet | archive: [%{roll: "001", prints: 2}]}) == 1
    assert ContentHealth.count(%{quiet | broken: [%{}], posts: [%{}, %{}]}) == 3
  end
end
