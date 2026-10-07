defmodule Web.Bible do
  @moduledoc """
  The Bible the site hosts, read from `priv/bible/<translation>/`: an
  `index.json` naming the books in canonical order and one JSON file per book
  (`%{chapter => %{verse => text}}`).

  One translation is served at a time. The one in the repository is the
  Catholic Public Domain Version, which is in the public domain. A licensed
  text (the RSV-CE, say) must not be committed here: lay it out the same way
  somewhere outside the checkout and point `BIBLE_PATH` at the folder. Nothing
  else changes, because every caller goes through `passage/1`.

  Books are parsed on first use and kept in `:persistent_term`; the whole
  Bible is about 5 MB of JSON, so a cold chapter costs one file read.

  Citations arrive in the lectionary's numbering (the Hebrew psalm numbers,
  the New American Bible's chapters), and `Web.Bible.Versification` carries
  them over to the numbering the hosted text declares in its index.
  """

  alias Web.Bible.{Citation, Versification}

  @type book :: %{slug: String.t(), name: String.t(), testament: :ot | :nt, chapters: pos_integer}
  @type verse :: {chapter :: pos_integer, verse :: pos_integer, text :: String.t()}

  @doc "The folder the translation is read from."
  def path do
    Application.get_env(:web, :bible_path) || Application.app_dir(:web, "priv/bible/cpdv")
  end

  @doc "The translation's name, abbreviation, note and psalm numbering."
  def translation do
    index = index()
    Map.take(index, [:abbr, :name, :note, :psalm_numbering])
  end

  @doc "Every book, in the translation's own order."
  @spec books() :: [book]
  def books, do: index().books

  @spec book(String.t()) :: book | nil
  def book(slug), do: Enum.find(books(), &(&1.slug == slug))

  @doc "The books either side of `slug`, for turning the page."
  def neighbours(slug, chapter) do
    books = books()
    i = Enum.find_index(books, &(&1.slug == slug))
    book = Enum.at(books, i)

    prev =
      cond do
        chapter > 1 -> {book, chapter - 1}
        i > 0 -> books |> Enum.at(i - 1) |> then(&{&1, &1.chapters})
        true -> nil
      end

    next =
      cond do
        chapter < book.chapters -> {book, chapter + 1}
        i < length(books) - 1 -> {Enum.at(books, i + 1), 1}
        true -> nil
      end

    {prev, next}
  end

  @doc "One chapter as `[{verse, text}]`, or `nil` when there is no such chapter."
  def chapter(slug, chapter) when is_integer(chapter) do
    with %{} = chapters <- load_book(slug),
         %{} = verses <- chapters[chapter] do
      verses |> Enum.sort()
    else
      _ -> nil
    end
  end

  @doc """
  Looks a citation up in the hosted text.

  Takes what a lectionary or a psalter prints ("Lk 10:38-42", "Psalm 139:1b-3,
  13-14ab", "Is 61:10—62:5") and returns

      {:ok, %{citation: "Luke 10:38-42", book: book, verses: [{10, 38, "…"}, …],
              approximate: false}}

  `citation` is the reference as the hosted text numbers it, which for a psalm
  in a Vulgate-numbered Bible is not the number that was asked for.
  `approximate` is set for the books whose verse numbers differ between the
  lectionary's Bible and this one in ways no table here corrects, so a page
  can say so beside the text.

  `default: "psalms"` reads a citation printed without its book as a psalm.

  `{:error, reason}` when the citation cannot be read, names no book the text
  has, or points at verses it does not have.
  """
  def passage(citation, opts \\ []) when is_binary(citation) do
    with {:ok, parsed} <- Citation.parse(citation, opts),
         %{} = book <- book(parsed.book) || {:error, :unknown_book},
         {:ok, mapped} <- Versification.map(parsed, index().psalm_numbering),
         %{} = chapters <- load_book(mapped.book) || {:error, :unknown_book},
         [_ | _] = verses <- collect(chapters, mapped.ranges) do
      book = book(mapped.book) || book

      {:ok,
       %{
         citation: Citation.format(book.name, mapped.ranges),
         asked: citation,
         book: book,
         verses: verses,
         approximate: mapped.approximate
       }}
    else
      [] -> {:error, :no_such_verses}
      {:error, _} = error -> error
      _ -> {:error, :unreadable}
    end
  end

  defp collect(chapters, ranges) do
    Enum.flat_map(ranges, fn {{c1, v1}, {c2, v2}} ->
      for c <- c1..c2//1,
          verses = chapters[c],
          verses != nil,
          {v, text} <- Enum.sort(verses),
          (c > c1 or v1 == nil or v >= v1) and (c < c2 or v2 == nil or v <= v2) do
        {c, v, text}
      end
    end)
  end

  defp index do
    cached({:index, path()}, fn ->
      raw = path() |> Path.join("index.json") |> File.read!() |> Jason.decode!()

      %{
        abbr: raw["abbr"],
        name: raw["name"],
        note: raw["note"],
        psalm_numbering: if(raw["psalm_numbering"] == "vulgate", do: :vulgate, else: :hebrew),
        books:
          for b <- raw["books"] do
            %{
              slug: b["slug"],
              name: b["name"],
              testament: if(b["testament"] == "nt", do: :nt, else: :ot),
              chapters: b["chapters"]
            }
          end
      }
    end)
  end

  defp load_book(slug) do
    if book(slug) do
      cached({:book, path(), slug}, fn ->
        raw = path() |> Path.join(slug <> ".json") |> File.read!() |> Jason.decode!()

        Map.new(raw, fn {chapter, verses} ->
          {String.to_integer(chapter),
           Map.new(verses, fn {v, text} -> {String.to_integer(v), text} end)}
        end)
      end)
    end
  end

  defp cached(key, fun) do
    key = {__MODULE__, key}

    case :persistent_term.get(key, nil) do
      nil ->
        value = fun.()
        :persistent_term.put(key, value)
        value

      value ->
        value
    end
  end
end
