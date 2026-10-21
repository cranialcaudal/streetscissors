defmodule Web.Editor.CompleteTest do
  use Web.DataCase, async: true

  alias Web.Editor.Complete
  alias WebWeb.DocumentEditor.Media

  describe "items/3" do
    test "[[ in a post offers posts as plain links, drafts marked" do
      items = Complete.items("fixture", "link", "blog")

      assert %{insert: "[Fixture Post With Keywords](/blog/keyworded-post)", detail: "post"} =
               Enum.find(items, &(&1.label == "Fixture Post With Keywords"))

      assert %{detail: "draft"} = Enum.find(items, &(&1.label == "Fixture Draft"))
    end

    test "words match at the start of a word, every word" do
      assert [%{label: "Fixture Post With Keywords"}] = Complete.items("fix keyw", "link", "blog")
      assert Complete.items("ixture", "link", "blog") == []
    end

    test "[[ in the fitness editor offers the wiki as wiki links" do
      assert [%{insert: "[[push-ups|" <> _}] = Complete.items("push", "link", "fitness")
    end

    test "keywords: offers the keywords in use, drafts' too" do
      keywords = Enum.map(Complete.items("", "keyword", "blog"), & &1.insert)
      assert "film" in keywords
      assert "unfinished" in keywords
    end

    test "related: offers piece refs" do
      assert %{insert: "post:keyworded-post"} =
               Enum.find(Complete.items("keyworded", "related", "blog"), &(&1.detail == "post"))
    end

    test "no more than twelve, and an unknown kind or scope offers nothing" do
      assert length(Complete.items("", "link", "blog")) <= 12
      assert Complete.items("x", "link", "none") == []
      assert Complete.items("x", "sideways", "blog") == []
    end
  end

  describe "the media drawer's snippets" do
    test "an image with its words, and words that would break the syntax made safe" do
      assert Media.snippet(%{"src" => "/uploads/images/tide.jpg", "words" => "The tide"}) ==
               "![The tide](/uploads/images/tide.jpg)"

      assert Media.snippet(%{"src" => "/uploads/images/a.jpg", "words" => "a] b\nc"}) ==
               "![a b c](/uploads/images/a.jpg)"
    end

    test "a frame, captioned or not, a whole roll, and nothing for nonsense" do
      assert Media.snippet(%{"roll" => "12", "frame" => "3", "words" => "Low | tide"}) ==
               "![[roll012/3|Low tide]]"

      assert Media.snippet(%{"roll" => "012", "frame" => "03", "words" => ""}) == "![[roll012/3]]"
      assert Media.snippet(%{"roll" => "roll012"}) == "![[roll012]]"
      assert Media.snippet(%{"roll" => "x", "frame" => "1"}) == nil
      assert Media.snippet(%{"src" => "javascript:alert(1)"}) == nil
    end
  end
end
