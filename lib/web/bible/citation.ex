defmodule Web.Bible.Citation do
  @moduledoc """
  Reads a scripture reference the way a lectionary prints one.

      iex> Web.Bible.Citation.parse("Lk 10:38-42")
      {:ok, %{book: "luke", ranges: [{{10, 38}, {10, 42}}]}}

      iex> Web.Bible.Citation.parse("Is 61:10—62:5")
      {:ok, %{book: "isaiah", ranges: [{{61, 10}, {62, 5}}]}}

      iex> Web.Bible.Citation.parse("Ps 95")
      {:ok, %{book: "psalms", ranges: [{{95, nil}, {95, nil}}]}}

  A range is `{{chapter, verse}, {chapter, verse}}`, with `nil` verses for a
  whole chapter. The part-of-a-verse letters a lectionary adds ("14ab") are
  dropped: the hosted text is divided by verse and no finer. Where a citation
  offers a shorter form ("… or 27:11-54") the first, longer one is taken.

  A responsorial psalm is often printed with no book at all ("103:1-2, 3-4"),
  so a caller that knows what it is reading passes `default: "psalms"`.
  """

  @books [
    {"genesis", ~w(gn gen genesis)},
    {"exodus", ~w(ex exod exodus)},
    {"leviticus", ~w(lv lev leviticus)},
    {"numbers", ~w(nm num numbers)},
    {"deuteronomy", ~w(dt deut deuteronomy)},
    {"joshua", ~w(jos josh joshua)},
    {"judges", ~w(jgs judg judges)},
    {"ruth", ~w(ru ruth)},
    {"1-samuel", ["1 sm", "1 sam", "1 samuel"]},
    {"2-samuel", ["2 sm", "2 sam", "2 samuel"]},
    {"1-kings", ["1 kgs", "1 kings"]},
    {"2-kings", ["2 kgs", "2 kings"]},
    {"1-chronicles", ["1 chr", "1 chron", "1 chronicles"]},
    {"2-chronicles", ["2 chr", "2 chron", "2 chronicles"]},
    {"ezra", ~w(ezr ezra)},
    {"nehemiah", ~w(neh nehemiah)},
    {"tobit", ~w(tb tob tobit)},
    {"judith", ~w(jdt jud judith)},
    {"esther", ~w(est esth esther)},
    {"job", ~w(jb job)},
    {"psalms", ~w(ps pss psalm psalms)},
    {"proverbs", ~w(prv prov proverbs)},
    {"ecclesiastes", ~w(eccl eccles ecclesiastes)},
    {"song-of-songs", ["sg", "sgs", "song", "song of songs", "song of solomon"]},
    {"wisdom", ~w(wis wisdom)},
    {"sirach", ~w(sir sirach)},
    {"isaiah", ~w(is isa isaiah)},
    {"jeremiah", ~w(jer jeremiah)},
    {"lamentations", ~w(lam lamentations)},
    {"baruch", ~w(bar baruch)},
    {"ezekiel", ~w(ez ezek ezekiel)},
    {"daniel", ~w(dn dan daniel)},
    {"hosea", ~w(hos hosea)},
    {"joel", ~w(jl joel)},
    {"amos", ~w(am amos)},
    {"obadiah", ~w(ob obad obadiah)},
    {"jonah", ~w(jon jonah)},
    {"micah", ~w(mi mic micah)},
    {"nahum", ~w(na nah nahum)},
    {"habakkuk", ~w(hb hab habakkuk)},
    {"zephaniah", ~w(zep zeph zephaniah)},
    {"haggai", ~w(hg hag haggai)},
    {"zechariah", ~w(zec zech zechariah)},
    {"malachi", ~w(mal malachi)},
    {"1-maccabees", ["1 mc", "1 macc", "1 maccabees"]},
    {"2-maccabees", ["2 mc", "2 macc", "2 maccabees"]},
    {"matthew", ~w(mt matt matthew)},
    {"mark", ~w(mk mark)},
    {"luke", ~w(lk luke)},
    {"john", ~w(jn john)},
    {"acts", ["acts", "acts of the apostles"]},
    {"romans", ~w(rom romans)},
    {"1-corinthians", ["1 cor", "1 corinthians"]},
    {"2-corinthians", ["2 cor", "2 corinthians"]},
    {"galatians", ~w(gal galatians)},
    {"ephesians", ~w(eph ephesians)},
    {"philippians", ~w(phil philippians)},
    {"colossians", ~w(col colossians)},
    {"1-thessalonians", ["1 thes", "1 thess", "1 thessalonians"]},
    {"2-thessalonians", ["2 thes", "2 thess", "2 thessalonians"]},
    {"1-timothy", ["1 tm", "1 tim", "1 timothy"]},
    {"2-timothy", ["2 tm", "2 tim", "2 timothy"]},
    {"titus", ~w(ti tit titus)},
    {"philemon", ~w(phlm philem philemon)},
    {"hebrews", ~w(heb hebrews)},
    {"james", ~w(jas james)},
    {"1-peter", ["1 pt", "1 pet", "1 peter"]},
    {"2-peter", ["2 pt", "2 pet", "2 peter"]},
    {"1-john", ["1 jn", "1 john"]},
    {"2-john", ["2 jn", "2 john"]},
    {"3-john", ["3 jn", "3 john"]},
    {"jude", ~w(jude)},
    {"revelation", ~w(rv rev revelation apocalypse)}
  ]

  @aliases for {slug, names} <- @books, name <- names, into: %{}, do: {name, slug}
  @single_chapter ~w(obadiah philemon 2-john 3-john jude)

  @split_re ~r/^((?:[123]\s*)?[[:alpha:]\.]+(?:\s+[[:alpha:]\.]+)*)\s*(.*)$/u

  @type range :: {{pos_integer, pos_integer | nil}, {pos_integer, pos_integer | nil}}

  @spec parse(String.t(), keyword) :: {:ok, %{book: String.t(), ranges: [range]}} | {:error, atom}
  def parse(citation, opts \\ []) when is_binary(citation) do
    cleaned =
      citation
      |> String.replace(~r/\(.*?\)/u, "")
      |> String.replace(~r/^\s*(see|cf\.?)\s+/iu, "")
      |> String.split(~r/\s+or\s+/iu)
      |> hd()
      |> String.replace(~r/[–—−]/u, "-")
      |> String.replace(~r/\s+and\s+|\+|&/iu, ",")
      |> String.trim()

    with {:ok, slug, rest} <- split(cleaned, opts[:default]),
         {:ok, ranges} <- ranges(rest, slug) do
      {:ok, %{book: slug, ranges: ranges}}
    else
      {:error, _} = error -> error
      _ -> {:error, :unreadable}
    end
  end

  defp split(cleaned, default) do
    case Regex.run(@split_re, cleaned) do
      [_, name, rest] ->
        with {:ok, slug} <- book_slug(name), do: {:ok, slug, rest}

      nil when is_binary(default) ->
        {:ok, default, cleaned}

      nil ->
        {:error, :unreadable}
    end
  end

  @doc "The slug of the book a name or abbreviation means."
  def book_slug(name) do
    key =
      name
      |> String.downcase()
      |> String.replace(".", "")
      |> String.replace(~r/^([123])\s*/, "\\1 ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    case @aliases[key] do
      nil -> {:error, :unknown_book}
      slug -> {:ok, slug}
    end
  end

  @doc """
  Prints ranges back as a reference under `book_name`.

      iex> Web.Bible.Citation.format("Luke", [{{10, 38}, {10, 42}}])
      "Luke 10:38-42"

      iex> Web.Bible.Citation.format("Psalms", [{{138, 1}, {138, 3}}, {{138, 13}, {138, 15}}])
      "Psalm 138:1-3, 13-15"
  """
  def format(book_name, ranges) do
    name = if book_name == "Psalms", do: "Psalm", else: book_name

    {parts, _} =
      Enum.map_reduce(ranges, nil, fn range, last_chapter ->
        case range do
          {{c, nil}, {c, nil}} ->
            {"; #{c}", nil}

          {{c1, nil}, {c2, nil}} ->
            {"; #{c1}-#{c2}", nil}

          {{c, v1}, {c, v2}} ->
            verses = if v1 == v2, do: "#{v1}", else: "#{v1}-#{v2}"
            if c == last_chapter, do: {", #{verses}", c}, else: {"; #{c}:#{verses}", c}

          {{c1, v1}, {c2, v2}} ->
            {"; #{c1}:#{v1}-#{c2}:#{v2}", c2}
        end
      end)

    reference = parts |> Enum.join() |> String.replace_prefix("; ", "")
    String.trim("#{name} #{reference}")
  end

  defp ranges("", _slug), do: {:error, :unreadable}

  defp ranges(rest, slug) do
    whole_chapters? = not String.contains?(rest, ":") and slug not in @single_chapter
    start = if slug in @single_chapter, do: 1

    rest
    |> String.split(~r/[;,]/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce_while({[], start}, fn part, {acc, chapter} ->
      case part(part, chapter, whole_chapters?) do
        {:ok, range, chapter} -> {:cont, {[range | acc], chapter}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {[_ | _] = acc, _} -> {:ok, Enum.reverse(acc)}
      _ -> {:error, :unreadable}
    end
  end

  defp part(part, chapter, whole_chapters?) do
    case String.split(part, "-", parts: 2) do
      [single] ->
        with {:ok, {c, v}} <- point(single, chapter, whole_chapters?) do
          {:ok, {{c, v}, {c, v}}, c}
        end

      [from, to] ->
        with {:ok, {c1, v1}} <- point(from, chapter, whole_chapters?),
             {:ok, {c2, v2}} <- point(to, c1, whole_chapters?),
             true <- {c1, v1 || 0} <= {c2, v2 || 0} do
          {:ok, {{c1, v1}, {c2, v2}}, c2}
        else
          _ -> :error
        end
    end
  end

  # "53:12" names its chapter; a bare number is a verse of the chapter in
  # hand, or a chapter when the citation has no verses at all ("Ps 95").
  defp point(text, chapter, whole_chapters?) do
    case text |> String.trim() |> String.split(":") |> Enum.map(&number/1) do
      [{:ok, c}, {:ok, v}] -> {:ok, {c, v}}
      [{:ok, c}] when whole_chapters? -> {:ok, {c, nil}}
      [{:ok, v}] when is_integer(chapter) -> {:ok, {chapter, v}}
      _ -> :error
    end
  end

  defp number(text) do
    case Regex.run(~r/^\s*(\d+)\s*[a-z]*\s*$/i, text) do
      [_, digits] -> {:ok, String.to_integer(digits)}
      _ -> :error
    end
  end
end
