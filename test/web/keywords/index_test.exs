defmodule Web.Keywords.IndexTest do
  use Web.DataCase

  import Web.AudioFixtures

  alias Web.Audio
  alias Web.Audio.Log
  alias Web.Blog
  alias Web.Keywords.Index

  setup do
    tmp = Path.join(System.tmp_dir!(), "keywords-index-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    original = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:web, :blog_path, original)
    end)

    post = fn slug, frontmatter ->
      File.write!(Path.join(tmp, slug <> ".md"), "---\n#{frontmatter}\n---\n\nBody of #{slug}.\n")
    end

    post.("ferry", "title: Ferry\nkeywords: nyc, film, ferry")
    post.("bridge", "title: Bridge\nkeywords: new-york, film")
    post.("wip", "title: Unfinished\nkeywords: nyc\ndraft: true")

    {:ok, tmp: tmp}
  end

  describe "usage/0" do
    test "counts a keyword across posts and logs, most used first" do
      log_fixture(keywords: "film, harbour")

      assert [%{keyword: "film", count: 3, posts: posts, logs: [_]} | rest] = Index.usage()
      assert Enum.map(posts, & &1.slug) |> Enum.sort() == ["bridge", "ferry"]

      assert Enum.map(rest, &{&1.keyword, &1.count}) == [
               {"nyc", 2},
               {"ferry", 1},
               {"harbour", 1},
               {"new-york", 1}
             ]
    end

    # A rename that skipped them would leave the old spelling to resurface on
    # the day they are published.
    test "sees drafts and unpublished logs" do
      log_fixture(keywords: "hidden", published: false)
      usage = Index.usage()

      assert %{posts: posts} = Enum.find(usage, &(&1.keyword == "nyc"))
      assert "wip" in Enum.map(posts, & &1.slug)
      assert Enum.find(usage, &(&1.keyword == "hidden"))
    end

    test "singletons/1 is what only one piece carries" do
      assert Index.singletons() |> Enum.map(& &1.keyword) == ["ferry", "new-york"]
    end
  end

  describe "rename/2" do
    test "rewrites the keyword in every post's file and every log" do
      log = log_fixture(keywords: "film, harbour")

      assert {:ok, %{keyword: "analog", posts: 2, logs: 1, merged: false}} =
               Index.rename("film", "Analog")

      assert {:ok, %{keywords: ["nyc", "analog", "ferry"]}} = Blog.get_post("ferry")
      assert {:ok, %{keywords: ["new-york", "analog"]}} = Blog.get_post("bridge")
      assert Log.keyword_list(Audio.get_log!(log.id)) == ["analog", "harbour"]
      refute Enum.find(Index.usage(), &(&1.keyword == "film"))
    end

    test "leaves the rest of each file exactly as it was", %{tmp: tmp} do
      {:ok, _} = Index.rename("film", "analog")

      assert File.read!(Path.join(tmp, "ferry.md")) ==
               "---\ntitle: Ferry\nkeywords: nyc, analog, ferry\n---\n\nBody of ferry.\n"
    end

    # nyc and new-york are one place. Renaming one to the other is the merge.
    test "renaming to a keyword that exists merges the two, drafts included" do
      assert {:ok, %{keyword: "new-york", posts: 2, logs: 0, merged: true}} =
               Index.rename("nyc", "New York")

      assert {:ok, %{keywords: ["new-york", "film", "ferry"]}} = Blog.get_post("ferry")
      assert {:ok, %{keywords: ["new-york"]}} = Blog.get_post("wip", drafts: true)

      assert %{count: 3} = Enum.find(Index.usage(), &(&1.keyword == "new-york"))
    end

    test "a piece that carried both keeps one copy, where the first stood", %{tmp: tmp} do
      File.write!(Path.join(tmp, "both.md"), "---\nkeywords: film, nyc, new-york\n---\n\nBoth.\n")

      {:ok, _} = Index.rename("new-york", "nyc")
      assert {:ok, %{keywords: ["film", "nyc"]}} = Blog.get_post("both")
    end

    test "refuses a blank name, the same name and a keyword nothing carries" do
      assert Index.rename("film", " ?! ") == {:error, :blank}
      assert Index.rename("film", "Film") == {:error, :same}
      assert Index.rename("nowhere", "somewhere") == {:error, :unknown}
      assert {:ok, %{keywords: ["nyc", "film", "ferry"]}} = Blog.get_post("ferry")
    end
  end
end
