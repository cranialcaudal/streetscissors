defmodule Web.BlogOutlineTest do
  use ExUnit.Case, async: false

  alias Web.Blog
  alias Web.Blog.Outline

  setup do
    tmp = Path.join(System.tmp_dir!(), "blog-outline-#{System.unique_integer([:positive])}")
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

  describe "strip/1" do
    test "leaves a post with no outline marks untouched" do
      text = """
      > "An epigraph stays in the post."

      ## The First Section

      A plain paragraph with **bold** words.
      """

      assert Outline.strip(text) == text
    end

    test "removes beat callouts, research checklists, target suffixes, and empty sections" do
      raw = """
      > "An epigraph stays."

      ## I. Opening (~250 words)

      > [!beat] The Hook
      > Start at the ferry terminal in winter.

      The ferry left the slip at six in the morning.

      > [!beat] The Second Beat
      > Contrast the timetable with the tide chart.

      ---

      ## II. Unwritten Section (~350 words)

      > [!beat] Still Only an Idea
      > Nothing has been drafted under this heading yet.
      >1. First sub-point
      >2. Second sub-point

      ## Research Checklist

      ### Archives
      - [ ] Port Authority annual report (1974).
      - [x] Coast Guard tide tables.
      """

      stripped = Outline.strip(raw)

      assert stripped =~ ~s(> "An epigraph stays.")
      assert stripped =~ "## I. Opening"
      refute stripped =~ "(~250 words)"
      assert stripped =~ "The ferry left the slip at six in the morning."
      refute stripped =~ "[!beat]"
      refute stripped =~ "Start at the ferry terminal"
      refute stripped =~ "Contrast the timetable"
      refute stripped =~ "II. Unwritten Section"
      refute stripped =~ "Research Checklist"
      refute stripped =~ "Port Authority"
    end
  end

  describe "analyze/2" do
    test "counts drafted words, section targets, beats answered, and reading-list thoughts" do
      raw = """
      ## Master Library Research Checklist

      - [x] First verified source.
      > [!thought]
      > My own phrasing from the first book: the harbor is a clock wound by the moon.
      - [ ] Second unverified source.
      - [ ] Third unverified source.

      ## I. Opening (~100 words)

      > [!beat] The Hook
      > Describe the harbor.

      Six words written under the first beat.

      > [!beat] The Thesis
      > State the central argument.

      > [!thought]
      > The timetable is a polite lie; the tide does the work.

      ## II. Middle (~200 words)

      > [!beat] [x] Checked Beat
      > Answered earlier in the opening.
      """

      info = Outline.analyze(raw, %{})

      assert info.has_outline?
      assert info.target_words == 300
      assert info.drafted_words == 10
      assert info.beats_total == 3
      assert info.beats_done == 2
      assert info.research.total == 3
      assert info.research.checked == 1
      assert info.research.with_thoughts == 1
      assert [first_source | _] = info.research.items

      assert first_source.thoughts == [
               "My own phrasing from the first book: the harbor is a clock wound by the moon."
             ]

      assert [sec1, sec2] = info.sections
      assert sec1.title == "I. Opening"
      assert sec1.target_words == 100
      assert sec1.drafted_words == 7
      assert sec1.beats_total == 2
      assert sec1.beats_done == 1

      assert [beat1, beat2] = sec1.beats
      assert beat1.title == "The Hook"
      assert beat1.drafted?
      assert beat1.words == 7
      assert beat2.title == "The Thesis"
      assert beat2.thoughts == ["The timetable is a polite lie; the tide does the work."]
      refute beat2.drafted?

      assert sec2.title == "II. Middle"
      assert sec2.target_words == 200
      assert sec2.beats_done == 1
    end
  end

  describe "seed_beat_thoughts/2" do
    test "copies a beat's > [!thought] phrasings into a draft paragraph beneath the beat" do
      raw = """
      ## I. Opening (~100 words)

      > [!beat] The Thesis
      > State the central argument.

      > [!thought]
      > The timetable is a polite lie; the tide does the work.
      """

      seeded = Outline.seed_beat_thoughts(raw, "The Thesis")

      assert seeded =~
               "> [!thought]\n> The timetable is a polite lie; the tide does the work.\n\nThe timetable is a polite lie; the tide does the work."

      info = Outline.analyze(seeded, %{})
      assert info.beats_done == 1
      assert Outline.strip(seeded) =~ "The timetable is a polite lie; the tide does the work."
    end
  end

  describe "from_blueprint/2 and Blog.create_from_blueprint/2" do
    test "converts a raw markdown blueprint into a single-file outlined draft", %{tmp: tmp} do
      blueprint = """
      Centering the harbor gives the essay its engine: the shift from timetables to tides.

      ### Master Essay Blueprint (~600 Words / 3-Minute Read)

      **Working Title:** *Tides and Timetables at the Ferry Slip*

      ---

      #### I. Introduction: The Winter Slip (~250 words)

      * **The Morning Hook:** Open with the six o'clock boat leaving in fog.
      * **The Core Thesis:** The schedule on the wall is a polite fiction; the tide does the work.
      1. **First faction:** The commuters with folded papers.
      2. **Second faction:** The deckhands watching the pilings.

      ---

      #### II. Conclusion: The Bell (~350 words)

      * **The Closing Image:** End on the bell over the ramp.

      ---

      ### Master Library Research Checklist

      * **Harbor History (Main Stacks):**
      * **Albion, Robert.** *The Rise of New York Port* (1939).
      * **Mitchell, Joseph.** *The Bottom of the Harbor* (1959).
      """

      assert {:ok, "tides-and-timetables-at-the-ferry-slip"} =
               Blog.create_from_blueprint(blueprint, ~D[2030-03-02])

      assert {:ok, post} =
               Blog.get_post("tides-and-timetables-at-the-ferry-slip", drafts: true)

      assert post.title == "Tides and Timetables at the Ferry Slip"
      assert post.excerpt =~ "Centering the harbor gives the essay its engine"
      assert post.draft
      assert post.word_count == 0
      assert post.outline.has_outline?
      assert post.outline.target_words == 600
      assert post.outline.beats_total == 3
      assert post.outline.beats_done == 0
      assert post.outline.research.total == 2
      assert post.outline.research.checked == 0

      assert Enum.map(post.outline.sections, & &1.title) == [
               "I. Introduction: The Winter Slip",
               "II. Conclusion: The Bell"
             ]

      raw_disk = File.read!(Path.join(tmp, "tides-and-timetables-at-the-ferry-slip.md"))
      assert raw_disk =~ "> [!beat] The Morning Hook"
      assert raw_disk =~ "> 1. **First faction:**"
      assert raw_disk =~ "- [ ] **Albion, Robert.**"
      # Reading list is placed at the top, before Section I
      {reading_pos, _} = :binary.match(raw_disk, "## Master Library Research Checklist")
      {sec1_pos, _} = :binary.match(raw_disk, "## I. Introduction")
      assert reading_pos < sec1_pos
    end
  end

  describe "citation keys and citations" do
    @keyed """
    ---
    title: Harbor
    draft: true
    ---

    ## Reading List

    - [x] **Vance, Clara.** *Tide Tables of the Sound* (Harbor Press, 2021). ^vance2021
    > [!thought]
    > Slack water holds for eleven minutes.
    - [ ] **Ortiz, Ana.** *Ferries at Dusk* (2019).

    ## I. Opening (~100 words)

    Slack water holds [@vance2021, p. 19], and the gulls wait with it.
    """

    test "reading-list items carry their key apart from their text" do
      %{research: %{items: [vance, ortiz]}} = Outline.analyze(@keyed)

      assert vance.key == "vance2021"
      refute vance.text =~ "^vance2021"
      assert ortiz.key == nil
    end

    test "ensure_reading_key/2 gives a source a key once, at the end of its line" do
      {text, key} = Outline.ensure_reading_key(@keyed, 1)
      assert key == "ortiz2019"
      assert text =~ "- [ ] **Ortiz, Ana.** *Ferries at Dusk* (2019). ^ortiz2019\n"
      assert Outline.ensure_reading_key(text, 1) == {text, "ortiz2019"}
      assert Outline.ensure_reading_key(@keyed, 0) == {@keyed, "vance2021"}
      assert Outline.ensure_reading_key(@keyed, 9) == {@keyed, nil}
    end

    test "key_reading_items/1 keys every source that has none" do
      text = Outline.key_reading_items(@keyed)

      assert Enum.map(Outline.analyze(text).research.items, & &1.key) == [
               "vance2021",
               "ortiz2019"
             ]
    end

    test "insert_reading_items/2 keys new sources apart from the ones there" do
      item = %{
        key: "ZOTERO1",
        title: "Tide Tables, Second Edition",
        authors: "Vance, Clara",
        year: "2021",
        publication: nil,
        call_number: nil,
        url: nil,
        notes: []
      }

      text = Outline.insert_reading_items(@keyed, [item])
      assert text =~ "*Tide Tables, Second Edition* (2021). ^vance2021a\n"
    end

    test "the post renders citations author-date with References, and keeps keys off the page" do
      post = Blog.preview("harbor", @keyed)

      assert post.body =~ "([Vance 2021](#ref-vance2021), p. 19)"
      assert post.body =~ "## References"
      assert post.body =~ "Vance, Clara. *Tide Tables of the Sound* (Harbor Press, 2021)."
      refute post.body =~ "^vance2021"
      refute post.body =~ "Ferries at Dusk"

      html = Blog.to_html(post.body)
      assert html =~ ~s(<a href="#ref-vance2021">Vance 2021</a>)
      # The References are not the post's words: the heading and the line are.
      assert post.word_count == 16
    end
  end
end
