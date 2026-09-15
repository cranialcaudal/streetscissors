defmodule Web.DocsTest do
  use ExUnit.Case, async: true

  doctest Web.Docs

  describe "render/1" do
    test "anchors h2 and h3 with slugs taken from their own text" do
      {html, contents} = Web.Docs.render("## Part 3 — Film\n\n### What a contact sheet is")

      assert html =~ ~s(<h2 id="part-3-film">)
      assert html =~ ~s(<h3 id="what-a-contact-sheet-is">)

      assert contents == [
               %{level: 2, id: "part-3-film", text: "Part 3 — Film"},
               %{level: 3, id: "what-a-contact-sheet-is", text: "What a contact sheet is"}
             ]
    end

    test "keeps repeated headings separately reachable" do
      {html, contents} = Web.Docs.render("## Film\n\n## Film\n\n## Film")

      assert Enum.map(contents, & &1.id) == ["film", "film-2", "film-3"]
      assert html =~ ~s(<h2 id="film-2">)
      assert html =~ ~s(<h2 id="film-3">)
    end

    test "strips markup out of the contents label but leaves it in the heading" do
      {html, [entry]} = Web.Docs.render("## Run `mix setup` first")

      assert entry.text == "Run mix setup first"
      assert entry.id == "run-mix-setup-first"
      assert html =~ ~s(<code class="inline">mix setup</code>)
    end

    test "hands back entities decoded, since HEEx escapes the label again" do
      {_html, [entry]} = Web.Docs.render("## Words & pictures")

      assert entry.text == "Words & pictures"
    end

    test "leaves h1 alone — the page title is not a place in the document" do
      {html, contents} = Web.Docs.render("# The manual\n\n## Part 1")

      refute html =~ "<h1 id="
      assert html =~ "The manual"
      assert Enum.map(contents, & &1.id) == ["part-1"]
    end

    test "renders GitHub-flavoured tables and fenced code" do
      markdown = """
      | Command | What it does |
      |---|---|
      | `mix setup` | First time only |

      ```
      negatives --list
      ```
      """

      {html, _contents} = Web.Docs.render(markdown)

      assert html =~ "<table>"
      assert html =~ "<td"
      assert html =~ "negatives --list"
    end

    test "a document with no headings still renders" do
      assert {html, []} = Web.Docs.render("Just a paragraph.")
      assert html =~ "Just a paragraph."
    end
  end
end
