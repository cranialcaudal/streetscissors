defmodule Web.KeywordsTest do
  use ExUnit.Case, async: true

  alias Web.Keywords

  doctest Web.Keywords

  describe "parse/1" do
    test "splits a comma-separated scalar, normalizing and de-duplicating" do
      assert Keywords.parse("Film, Bowling Green , film") == ["film", "bowling-green"]
    end

    test "accepts an inline YAML list" do
      assert Keywords.parse("[film, ferry]") == ["film", "ferry"]
    end

    test "accepts an already-split list" do
      assert Keywords.parse(["Film", "NYC"]) == ["film", "nyc"]
    end

    test "nil and blanks parse to no keywords" do
      assert Keywords.parse(nil) == []
      assert Keywords.parse("") == []
      assert Keywords.parse(" , , ") == []
    end

    test "keeps the author's order" do
      assert Keywords.parse("zebra, apple") == ["zebra", "apple"]
    end
  end

  describe "normalize/1" do
    test "downcases, hyphenates whitespace, and drops punctuation" do
      assert Keywords.normalize("  New York! ") == "new-york"
      assert Keywords.normalize("night_walk") == "night-walk"
      assert Keywords.normalize("a -- b") == "a-b"
    end

    test "strips surrounding quotes left by frontmatter" do
      assert Keywords.normalize(~s("film")) == "film"
      assert Keywords.normalize("'film'") == "film"
    end

    test "keeps non-ASCII letters" do
      assert Keywords.normalize("Café") == "café"
    end

    test "punctuation-only input normalizes to nothing" do
      assert Keywords.normalize("!!!") == ""
    end
  end

  describe "format/1" do
    test "round-trips through parse" do
      assert "film, ferry" |> Keywords.parse() |> Keywords.format() == "film, ferry"
    end
  end

  describe "tally/1" do
    test "counts most-used first, alphabetical within a tie" do
      assert Keywords.tally([["film", "nyc"], ["film", "apple"]]) == [
               {"film", 2},
               {"apple", 1},
               {"nyc", 1}
             ]
    end

    test "no keywords tallies to an empty bar" do
      assert Keywords.tally([[], []]) == []
    end
  end

  describe "match?/2" do
    test "a blank filter matches everything" do
      assert Keywords.match?(["film"], nil)
      assert Keywords.match?([], "")
    end

    test "matches on the normalized token, not the raw string" do
      assert Keywords.match?(["bowling-green"], "Bowling Green")
      refute Keywords.match?(["film"], "ferry")
    end
  end
end
