defmodule Web.Liturgy.Sanctoral do
  @moduledoc """
  The saints' days, read from the plain-text calendars in `priv/liturgy/`.

  The files are in the format of the calendarium-romanum project, whose
  General Roman Calendar (`universal-en.txt`) is used as it stands:

      = 10
      15 m teresa_avila : Saint Teresa of Jesus, virgin and doctor

  a month heading, then `DAY [RANK] [COLOUR] identifier : title`. Rank is
  nothing (optional memorial), `m`, `f`, `s`, `fl`/`f2.5` (a feast of the
  Lord), or `mp`/`fp`/`sp` for a proper celebration.

  Calendars are layered, most general first: the General Roman Calendar, the
  proper of the United States, the proper of the Discalced Carmelites. **An
  entry replaces the entry of the same identifier in an earlier layer,
  wherever that one was dated**, which covers both things a proper calendar
  does: it raises a rank (Saint Teresa is a solemnity in Carmel), and it moves
  a saint out of the way of one of its own (Saint Henry to July 10).

  Two days are neither feast nor memorial but commemorations of the dead: All
  Souls, which ranks with the solemnities, and the Order's own on November 15.
  They keep the precedence their line gives them and are named `:commemoration`.

  A celebration's `precedence` is its row in the Table of Liturgical Days
  (Universal Norms, 59): the lower number is kept when two meet.
  """

  @layers [
    general: ~w(universal-en.txt),
    usa: ~w(universal-en.txt usa-en.txt),
    ocd: ~w(universal-en.txt usa-en.txt ocd-en.txt)
  ]

  @ranks %{
    "s" => {:solemnity, 3},
    "sp" => {:solemnity, 4},
    "fl" => {:feast, 5},
    "f" => {:feast, 7},
    "fp" => {:feast, 8},
    "m" => {:memorial, 10},
    "mp" => {:memorial, 11},
    "" => {:optional, 12}
  }

  @commemorations ~w(all_souls carmelite_souls)

  @colours %{"R" => :red, "W" => :white, "V" => :violet, "G" => :green}

  @entry_re ~r/^(?:(\d+)\/)?(\d+)\s+(?:(s|sp|fl|f2\.5|f|fp|m|mp)\s+)?(?:([RWVG])\s+)?([a-z][a-z0-9_]+)\s*:\s*(.+)$/

  @type entry :: %{
          symbol: String.t(),
          title: String.t(),
          rank: :solemnity | :feast | :memorial | :commemoration | :optional,
          precedence: pos_integer,
          colour: atom,
          proper: boolean
        }

  @doc """
  The celebrations fixed to `month`/`day` in `calendar` (`:general`, `:usa`
  or `:ocd`), highest first.
  """
  @spec on(pos_integer, pos_integer, atom) :: [entry]
  def on(month, day, calendar \\ :ocd), do: Map.get(calendar(calendar), {month, day}, [])

  @doc "Where `symbol` is fixed in `calendar`: `{month, day, entry}` or `nil`."
  def find(symbol, calendar \\ :ocd) do
    Enum.find_value(calendar(calendar), fn {{month, day}, entries} ->
      if entry = Enum.find(entries, &(&1.symbol == symbol)), do: {month, day, entry}
    end)
  end

  @doc "Every solemnity with its fixed date, for working out transfers."
  def solemnities(calendar \\ :ocd) do
    for {{month, day}, entries} <- calendar(calendar), %{rank: :solemnity} = e <- entries do
      {month, day, e}
    end
  end

  defp calendar(name) do
    key = {__MODULE__, name}

    case :persistent_term.get(key, nil) do
      nil ->
        calendar = load(Keyword.fetch!(@layers, name))
        :persistent_term.put(key, calendar)
        calendar

      calendar ->
        calendar
    end
  end

  defp load(files) do
    dir = Application.app_dir(:web, "priv/liturgy")

    files
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {file, layer}, by_symbol ->
      dir
      |> Path.join(file)
      |> File.read!()
      |> parse(layer > 0)
      |> Enum.reduce(by_symbol, fn {date, entry}, acc ->
        Map.put(acc, entry.symbol, {date, entry})
      end)
    end)
    |> Map.values()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {date, entries} ->
      {date, Enum.sort_by(entries, &{&1.precedence, &1.title})}
    end)
  end

  @doc false
  def parse(text, proper?) do
    text
    |> String.split("\n")
    |> drop_front_matter()
    |> Enum.reduce({nil, []}, fn line, {month, acc} ->
      line = line |> String.replace(~r/#.*$/, "") |> String.trim()

      cond do
        line == "" ->
          {month, acc}

        String.starts_with?(line, "=") ->
          {line |> String.trim_leading("=") |> String.trim() |> String.to_integer(), acc}

        true ->
          case Regex.run(@entry_re, line) do
            [_, m, day, rank, colour, symbol, title] ->
              month = if m == "", do: month, else: String.to_integer(m)
              rank = if rank == "f2.5", do: "fl", else: rank
              {rank, precedence} = Map.fetch!(@ranks, rank)

              entry = %{
                symbol: symbol,
                title: String.trim(title),
                rank: if(symbol in @commemorations, do: :commemoration, else: rank),
                precedence: precedence,
                colour: Map.get(@colours, colour, :white),
                proper: proper?
              }

              {month, [{{month, String.to_integer(day)}, entry} | acc]}

            nil ->
              raise ArgumentError, "unreadable calendar line: #{inspect(line)}"
          end
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp drop_front_matter(["---" | rest]) do
    rest |> Enum.drop_while(&(String.trim(&1) != "---")) |> Enum.drop(1)
  end

  defp drop_front_matter(lines), do: lines
end
