defmodule Web.Writing.ExportTest do
  use ExUnit.Case, async: true

  alias Web.Writing.{Citations, Export}

  @paper """
  ---
  title: "Slack Water"
  author: A. Writer; B. Writer
  date: 2030-03-02
  abstract: "On the eleven minutes."
  ---

  ## Reading List

  - [x] **Vance, Clara.** *Tide Tables of the Sound* (Harbor Press, 2021). ^vance2021
  - [ ] **Ortiz, Ana.** "Ferries at Dusk," *Journal of Harbors* 4, no. 2 (2019): 1–20. https://doi.org/10.1234/harbors.2019 ^ortiz2019

  ## Introduction (~100 words)

  > [!beat] The hook
  > Open on the narrows.

  Slack water holds for eleven minutes [@vance2021, p. 19], as the ferries knew [@ortiz2019].
  See [[harbor-notes|the notes]] and ![[roll012/3]].
  """

  describe "for_pandoc/1" do
    test "reduces wiki links to their words and leaves embeds out" do
      assert Export.for_pandoc("See [[a|the notes]], [[b]] and ![[roll012/3]].") ==
               "See the notes, b and ."
    end
  end

  describe "Citations.csl_items/3" do
    test "builds CSL JSON from the reading list for the keys cited" do
      items = Web.Writing.Outline.analyze(@paper).research.items
      [ortiz] = Citations.csl_items(items, ["ortiz2019"])

      assert ortiz["id"] == "ortiz2019"
      assert ortiz["type"] == "article-journal"
      assert ortiz["title"] == "Ferries at Dusk"
      assert ortiz["author"] == [%{"family" => "Ortiz", "given" => "Ana"}]
      assert ortiz["issued"] == %{"date-parts" => [[2019]]}
      assert ortiz["container-title"] == "Journal of Harbors"
      assert ortiz["issue"] == "2"
      assert ortiz["page"] =~ "1"
      assert ortiz["DOI"] == "10.1234/harbors.2019"
    end

    test "a title written as a link keeps its words, and its address is the URL" do
      [item] =
        Web.Writing.Outline.analyze("""
        ## Reading List

        - [ ] **Harbor Gazette.** "[Ferries return to the narrows](https://example.org/ferries)," *Harbor Gazette* (Nov. 3, 2030). ^gazette2030
        """).research.items
        |> Citations.csl_items(["gazette2030"])

      assert item["title"] == "Ferries return to the narrows"
      assert item["URL"] == "https://example.org/ferries"
      assert item["issued"] == %{"date-parts" => [[2030]]}
    end

    test "prefers Zotero's own CSL item, matched by title" do
      items = Web.Writing.Outline.analyze(@paper).research.items
      zotero = [%{"id" => "ZKEY", "title" => "Tide tables of the sound", "page" => "19-40"}]

      assert [%{"id" => "vance2021", "page" => "19-40"}] =
               Citations.csl_items(items, ["vance2021"], zotero)
    end
  end

  test "an unknown format is refused" do
    assert Export.export(@paper, "slack", "rtf") == {:error, :unknown_format}
  end

  @tag :pandoc
  test "exports LaTeX with the citations formatted and the References written" do
    assert {:ok, tex, "slack.tex"} = Export.export(@paper, "slack", "tex")

    assert tex =~ "Slack Water"
    assert tex =~ ~r/Vance\s+2021, 19/
    assert tex =~ "Tide Tables of the Sound"
    assert tex =~ "References"
    # The scaffolding stays out.
    refute tex =~ "Open on the narrows"
    refute tex =~ "[@vance2021"
  end

  @tag :pandoc
  test "exports Word" do
    assert {:ok, <<"PK", _::binary>>, "slack.docx"} = Export.export(@paper, "slack", "docx")
  end
end
