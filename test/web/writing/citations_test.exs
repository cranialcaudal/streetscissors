defmodule Web.Writing.CitationsTest do
  use ExUnit.Case, async: true

  alias Web.Writing.Citations

  doctest Citations

  @items [
    %{
      text:
        "**Vance, Clara.** *Tide Tables of the Sound* (Harbor Press, 2021). *Call Number: GC1 V36* ^vance2021"
    },
    %{text: "**Ortiz, Ana & Reyes, Tomas.** *Ferries at Dusk* (2019). ^ortiz2019"},
    %{
      text: "**Lund, Mara, et al.** *Fog Signals* (2015). — check the chapter on horns ^lund2015"
    },
    %{text: "*An Unsigned Pamphlet on Moorings* ^pamphlet"},
    %{text: "A source with no key yet"}
  ]

  describe "split_key/1" do
    test "takes the block id off the end of the line" do
      assert Citations.split_key("*Tides* (2021). ^vance2021") == {"*Tides* (2021).", "vance2021"}
      assert Citations.split_key("*Tides* (2021).") == {"*Tides* (2021).", nil}
      # A caret inside the line is not a key.
      assert Citations.split_key("x^2 is not ^ a key") == {"x^2 is not ^ a key", nil}
    end
  end

  describe "sources/1" do
    test "names each keyed source author-date, and keeps the entry as written" do
      sources = Citations.sources(@items)

      assert map_size(sources) == 4
      assert %{label: "Vance", year: "2021"} = sources["vance2021"]

      assert sources["vance2021"].entry ==
               "Vance, Clara. *Tide Tables of the Sound* (Harbor Press, 2021)."

      assert sources["ortiz2019"].label == "Ortiz and Reyes"
      assert sources["lund2015"].label == "Lund et al."
      assert sources["lund2015"].entry == "Lund, Mara, et al. *Fog Signals* (2015)."
      assert sources["pamphlet"].label =~ "An Unsigned Pamphlet"
    end
  end

  describe "citations/1" do
    test "reads prefixes, locators and author suppression, and skips code and links" do
      text = """
      As shown [@vance2021, p. 19] and [see @ortiz2019; -@lund2015 ch. 2].
      Not these: `[@vance2021]`, [@vance2021](https://example.org), [[note]], [mail@example.org].

      ```
      [@ortiz2019]
      ```
      """

      assert [
               %{key: "vance2021", locator: "p. 19", prefix: nil, suppress?: false},
               %{key: "ortiz2019", prefix: "see", locator: nil},
               %{key: "lund2015", locator: "ch. 2", suppress?: true}
             ] = Citations.citations(text)
    end
  end

  describe "render/2" do
    test "writes citations author-date, linked to a References section in order" do
      sources = Citations.sources(@items)
      {text, refs} = Citations.render("Slack water [@vance2021, p. 19; -@ortiz2019].", sources)

      assert text ==
               "Slack water ([Vance 2021](#ref-vance2021), p. 19; [2019](#ref-ortiz2019))."

      assert refs =~ "## References"
      # Alphabetical: Ortiz before Vance; the uncited are left out.
      [ortiz, vance] = refs |> String.split("\n\n", trim: true) |> Enum.drop(1)

      assert ortiz =~
               "Ortiz, Ana & Reyes, Tomas. *Ferries at Dusk* (2019).\n{: .ref-entry #ref-ortiz2019}"

      assert vance =~ "{: .ref-entry #ref-vance2021}"
      refute refs =~ "Fog Signals"
    end

    test "leaves a citation with an unknown key as typed" do
      sources = Citations.sources(@items)
      assert Citations.render("See [@nobody2000].", sources) == {"See [@nobody2000].", ""}
      # One unknown key in a group leaves the whole group as typed.
      assert {"[@vance2021; @nobody2000]", ""} =
               Citations.render("[@vance2021; @nobody2000]", sources)
    end

    test "renders to linked HTML with ids on the entries" do
      {text, refs} = Citations.render("A line [@vance2021].", Citations.sources(@items))
      html = Web.Markdown.to_html(text <> refs)

      assert html =~ ~s(<a href="#ref-vance2021">Vance 2021</a>)
      assert html =~ ~s(<p class="ref-entry" id="ref-vance2021">)
    end
  end

  describe "check/2" do
    test "lists keys with no source and sources never cited" do
      assert %{cited: ["vance2021", "ghost"], unknown: ["ghost"], uncited: uncited} =
               Citations.check("[@vance2021] and [@ghost].", @items)

      assert uncited == ["ortiz2019", "lund2015", "pamphlet"]
    end
  end

  describe "new_key/2" do
    test "surname and year, made unique" do
      fields = %{authors: "Vance, Clara", year: "2021", title: "Tides"}
      assert Citations.new_key(fields, []) == "vance2021"
      assert Citations.new_key(fields, ["vance2021"]) == "vance2021a"
      assert Citations.new_key(fields, ["vance2021", "vance2021a"]) == "vance2021b"
    end

    test "prefers the source's own key, cleaned for a block id" do
      assert Citations.new_key(%{citation_key: "Vance_2021:tides", authors: "x"}, []) ==
               "vance2021tides"
    end

    test "falls back to the title's first word" do
      assert Citations.new_key(%{authors: "", year: nil, title: "The Harbor Ledger"}, []) ==
               "harbor"
    end
  end
end
