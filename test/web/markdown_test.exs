defmodule Web.MarkdownTest do
  use ExUnit.Case, async: true

  alias Web.Markdown

  test "to_html/1 renders GitHub-flavoured Markdown" do
    assert Markdown.to_html("| a |\n|---|\n| b |\n") =~ "<table"
    assert Markdown.to_html("~~gone~~") =~ "<del>gone</del>"
  end

  describe "to_text/1" do
    test "drops the marks and the tags, keeping the words" do
      assert Markdown.to_text("A **ferry** at _dawn_, see [the post](/blog/x).\n\nTwo & three.") ==
               "A ferry at dawn, see the post. Two & three."
    end

    test "leaves embeds out, and a wiki link keeps its name" do
      assert Markdown.to_text("![[roll012/3|Low tide]] Then [[push-ups|Push-ups]] and [[squat]].") ==
               "Then Push-ups and squat."
    end

    test "nothing is empty" do
      assert Markdown.to_text(nil) == ""
      assert Markdown.to_text("![[roll012]]") == ""
    end
  end
end
