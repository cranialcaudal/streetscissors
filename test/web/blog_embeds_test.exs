defmodule Web.Blog.EmbedsTest do
  use ExUnit.Case, async: false

  alias Web.Blog.Embeds

  @fixtures Path.expand("../support/fixtures/negatives", __DIR__)

  setup do
    original = Application.get_env(:web, :negatives_path)
    Application.put_env(:web, :negatives_path, @fixtures)

    on_exit(fn ->
      if original,
        do: Application.put_env(:web, :negatives_path, original),
        else: Application.delete_env(:web, :negatives_path)
    end)

    :ok
  end

  test "expands a contact sheet embed into a linked preview" do
    html = Embeds.transform("<p>![[roll001]]</p>")
    assert html =~ ~s(<figure class="blog-embed blog-embed-sheet">)
    assert html =~ ~s(href="/negatives/image/roll001_2026-01-01_120_bw.png")
    assert html =~ ~s(src="/negatives/preview/roll001_2026-01-01_120_bw.png")
  end

  test "accepts bare roll numbers and full sheet slugs" do
    assert Embeds.transform("![[1]]") =~ "blog-embed-sheet"
    assert Embeds.transform("![[roll001_2026-01-01_120_bw]]") =~ "blog-embed-sheet"
  end

  test "expands a frame embed with caption (120 naming convention)" do
    html = Embeds.transform("<p>![[roll001/1|My caption]]</p>")
    assert html =~ ~s(<figure class="blog-embed blog-embed-frame">)
    assert html =~ ~s(src="/negatives/frame/roll001/1")
    assert html =~ "<figcaption>My caption</figcaption>"
  end

  test "expands a frame embed (35mm naming convention)" do
    html = Embeds.transform("![[2/3]]")
    assert html =~ ~s(src="/negatives/frame/roll002/3")
  end

  test "escapes captions" do
    html = Embeds.transform("![[roll001/1|<script>alert(1)</script>]]")
    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end

  test "leaves unresolvable targets as literal text" do
    assert Embeds.transform("![[roll999]]") == "![[roll999]]"
    assert Embeds.transform("![[roll001/99]]") == "![[roll001/99]]"
    assert Embeds.transform("![[some obsidian note]]") == "![[some obsidian note]]"
  end

  test "degrades to literal text when the negatives directory is missing" do
    Application.put_env(:web, :negatives_path, "/nonexistent-negatives")
    assert Embeds.transform("![[roll001]]") == "![[roll001]]"
    assert Embeds.transform("![[roll001/1]]") == "![[roll001/1]]"
  end
end
