defmodule Web.BibleTest do
  use ExUnit.Case, async: true

  alias Web.Bible
  alias Web.Bible.Citation

  doctest Web.Bible.Citation

  describe "the hosted text" do
    test "is the whole Catholic canon" do
      books = Bible.books()
      assert length(books) == 73
      assert Enum.count(books, &(&1.testament == :nt)) == 27

      assert Enum.all?(
               ~w(tobit judith wisdom sirach baruch 1-maccabees 2-maccabees),
               &Bible.book/1
             )
    end

    test "reads a chapter in verse order" do
      assert [{1, "In the beginning, God created heaven and earth."} | _] =
               Bible.chapter("genesis", 1)

      assert Bible.chapter("genesis", 51) == nil
      assert Bible.chapter("no-such-book", 1) == nil
    end

    test "turns the page across books" do
      assert {nil, {%{slug: "genesis"}, 2}} = Bible.neighbours("genesis", 1)
      assert {{%{slug: "genesis"}, 50}, {%{slug: "exodus"}, 2}} = Bible.neighbours("exodus", 1)
      assert {{%{slug: "revelation"}, 21}, nil} = Bible.neighbours("revelation", 22)
    end
  end

  describe "Citation.parse/2" do
    test "reads the forms a lectionary prints" do
      assert {:ok,
              %{
                book: "psalms",
                ranges: [{{139, 1}, {139, 3}}, {{139, 13}, {139, 14}}, {{139, 14}, {139, 15}}]
              }} =
               Citation.parse("Psalm 139:1b-3, 13-14ab, 14c-15")

      assert {:ok,
              %{
                book: "revelation",
                ranges: [
                  {{4, 11}, {4, 11}},
                  {{5, 9}, {5, 9}},
                  {{5, 10}, {5, 10}},
                  {{5, 12}, {5, 12}}
                ]
              }} =
               Citation.parse("Rev 4:11; 5:9, 10, 12")

      assert {:ok, %{book: "1-john", ranges: [{{2, 22}, {2, 28}}]}} =
               Citation.parse("1 Jn 2:22-28")

      assert {:ok, %{book: "jude", ranges: [{{1, 17}, {1, 17}}, {{1, 20}, {1, 25}}]}} =
               Citation.parse("Jude 17, 20b-25")

      assert {:ok, %{book: "matthew", ranges: [{{26, 14}, {27, 66}}]}} =
               Citation.parse("Mt 26:14—27:66 or 27:11-54")

      assert {:ok, %{book: "philippians"}} = Citation.parse("PHIL 3:3-8A")
    end

    test "takes a default book for a psalm printed without one" do
      assert {:error, _} = Citation.parse("103:1-2, 3-4")

      assert {:ok, %{book: "psalms", ranges: [{{103, 1}, {103, 2}}, {{103, 3}, {103, 4}}]}} =
               Citation.parse("103:1-2, 3-4", default: "psalms")
    end

    test "refuses what it cannot read" do
      assert {:error, :unknown_book} = Citation.parse("Hezekiah 3:1")
      assert {:error, _} = Citation.parse("Est C:12, 14-16")
      assert {:error, :unreadable} = Citation.parse("Luke")
    end
  end

  describe "passage/2 in a Vulgate-numbered Bible" do
    test "finds a Gospel where it is cited" do
      assert {:ok, %{citation: "Luke 10:38-42", verses: verses, approximate: false}} =
               Bible.passage("Lk 10:38-42")

      assert [{10, 38, first} | _] = verses
      assert first =~ "Martha"
      assert length(verses) == 5
    end

    test "carries the psalms over to the Vulgate's numbers" do
      assert {:ok, %{citation: "Psalm 22", verses: [{22, 1, shepherd} | _]}} =
               Bible.passage("Ps 23")

      assert shepherd =~ "The Lord directs me"

      assert {:ok, %{citation: "Psalm 50:3-4"}} = Bible.passage("Ps 51:3-4")
      # Hebrew 9 and 10 are one psalm, as are 114 and 115.
      assert {:ok, %{citation: "Psalm 9:22-39"}} = Bible.passage("Ps 10")
      assert {:ok, %{citation: "Psalm 113:9-26"}} = Bible.passage("Ps 115")
      # Hebrew 116 and 147 are two each.
      assert {:ok, %{citation: "Psalm 114:1-9"}} = Bible.passage("Ps 116:1-9")
      assert {:ok, %{citation: "Psalm 115:1-10"}} = Bible.passage("Ps 116:10-19")
      assert {:ok, %{citation: "Psalm 146:1-11"}} = Bible.passage("Ps 147:1-11")
      assert {:ok, %{citation: "Psalm 147:1-9"}} = Bible.passage("Ps 147:12-20")
      assert {:ok, %{citation: "Psalm 150"}} = Bible.passage("Ps 150")
    end

    test "carries Joel, Malachi and Zechariah over" do
      assert {:ok, %{citation: "Joel 2:28-32", verses: [{2, 28, spirit} | _]}} =
               Bible.passage("Jl 3:1-5")

      assert spirit =~ "pour out my spirit"
      assert {:ok, %{citation: "Malachi 4:1-2"}} = Bible.passage("Mal 3:19-20a")

      assert {:ok, %{citation: "Zechariah 2:10-13", verses: [{2, 10, sion} | _]}} =
               Bible.passage("Zec 2:14-17")

      assert sion =~ "daughter of Zion"
    end

    test "says when the numbering cannot be trusted, and refuses Esther" do
      assert {:ok, %{approximate: true}} = Bible.passage("Sir 36:1-5")
      assert {:error, :versification} = Bible.passage("Est 4:1-3")
      assert {:error, :no_such_verses} = Bible.passage("Lk 99:1")
    end
  end
end
