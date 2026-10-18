defmodule Web.Darkroom.Film do
  @moduledoc """
  What a film stock is known to do, from its maker's datasheet
  (`priv/film/stocks.json`, each figure with the sheet it came from), and the
  arithmetic that turns it into a print's colour.

  **Colour is worked as two ratios**, `rg = log10(R/G)` and `bg = log10(B/G)`
  of the print's linear light: a density-like scale on which a colour
  compensating filter is a plain offset and a white balance is a gain. A CC
  filter's number is its density times 100, so a camera filter of 10R (red,
  which holds back green and blue) is answered on the print by taking green
  and blue down 0.10: `rg + 0.10, bg + 0.00`.

  **The print's Temp and Tint sliders are LightCraft's**, and how far each
  moves the two ratios was measured, not guessed, by rendering a neutral grey
  through each (2026-10-17, `test/web/darkroom_film_test.exs` measures it
  again when `lightcraft-cli` is there): per mired of Temp (a mired is a
  million over the kelvins) `rg` moves -0.00178 and `bg` +0.0026; per unit of
  Tint `rg` moves +0.0026 and `bg` +0.0024. The two pairs are independent, so
  any cast has one Temp and Tint that answer it (`sliders/2`).

  **What a long exposure does to colour** is the sheet's filter for that time
  (`reciprocity/2`), interpolated on the log of the time, and nothing when the
  sheet says nothing. Its extra stops are reported but not applied: each
  single is already exposed on its own by `film-develop`, so what a long
  exposure leaves on the print is its colour. A filter on the camera and the
  same correction on the print are taken as equal; the film's gamma would
  scale it, and the taste model (`Web.Darkroom.Taste`) learns the rest.
  """

  # Measured on LightCraft at 43a47e5: d(rg, bg) per mired of Temp and per
  # unit of Tint.
  @per_mired {-0.00178, 0.0026}
  @per_tint {0.0026, 0.0024}

  @doc "Every stock in the catalogue."
  def stocks do
    key = {__MODULE__, :stocks}

    case :persistent_term.get(key, nil) do
      nil ->
        stocks =
          Application.app_dir(:web, "priv/film/stocks.json")
          |> File.read!()
          |> Jason.decode!()
          |> Map.fetch!("stocks")

        :persistent_term.put(key, stocks)
        stocks

      stocks ->
        stocks
    end
  end

  @doc """
  The stock a roll's free-text film (`roll.json`'s `film`, as typed on the
  scanner page) names, or nil. The longest alias found in the words wins, so
  "Portra 400" is not taken for plain "Portra".
  """
  def match(nil), do: nil

  def match(text) when is_binary(text) do
    words = " " <> normalize(text) <> " "

    stocks()
    |> Enum.flat_map(fn stock ->
      for alias <- [stock["name"] | stock["aliases"]],
          String.contains?(words, " " <> normalize(alias) <> " "),
          do: {String.length(alias), stock}
    end)
    |> Enum.max_by(&elem(&1, 0), fn -> nil end)
    |> case do
      nil -> nil
      {_, stock} -> stock
    end
  end

  defp normalize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9+]+/u, " ")
    |> String.trim()
  end

  @doc """
  What the sheet says of an exposure of `seconds`: `%{status, stops, cast,
  filter, source}`. `status` is `:none` (within the range that needs
  nothing), `:published` (on or between the sheet's rows), `:beyond` (past
  the last row: the last row's figure, said to be a guess), `:unpublished`
  (the maker gives nothing past its range) or `:unknown` (no sheet read).
  `cast` is the `{rg, bg}` correction the print wants.
  """
  def reciprocity(_stock, seconds) when not is_number(seconds) or seconds <= 0,
    do: result(:none, 0.0, nil, nil)

  def reciprocity(%{"reciprocity" => nil}, _seconds), do: result(:unknown, 0.0, nil, nil)
  def reciprocity(nil, _seconds), do: result(:unknown, 0.0, nil, nil)

  def reciprocity(%{"reciprocity" => r}, seconds) do
    cond do
      seconds <= r["none_to"] ->
        result(:none, 0.0, nil, r["source"])

      is_number(r["p"]) ->
        stops = (r["p"] - 1) * :math.log2(seconds)
        result(:published, stops, nil, r["source"])

      is_list(r["table"]) ->
        table(r, seconds)

      true ->
        result(:unpublished, 0.0, nil, r["source"])
    end
  end

  defp table(r, seconds) do
    rows = [[r["none_to"], 0.0, nil] | r["table"]]
    x = :math.log2(seconds)

    case Enum.chunk_every(rows, 2, 1, :discard)
         |> Enum.find(fn [[t0 | _], [t1 | _]] -> seconds >= t0 and seconds <= t1 end) do
      [[t0, s0, f0], [t1, s1, f1]] ->
        k = (x - :math.log2(t0)) / (:math.log2(t1) - :math.log2(t0))
        {c0, c1} = {filter_cast(f0), filter_cast(f1)}
        cast = {lerp(elem(c0, 0), elem(c1, 0), k), lerp(elem(c0, 1), elem(c1, 1), k)}
        name = if k > 0.5, do: f1, else: f0
        result(:published, lerp(s0, s1, k), cast, r["source"], name)

      nil ->
        [_t, stops, filter] = List.last(rows)
        result(:beyond, stops, filter_cast(filter), r["source"], filter)
    end
  end

  defp lerp(a, b, k), do: a + (b - a) * k

  defp result(status, stops, cast, source, filter \\ nil) do
    %{status: status, stops: stops, cast: cast || {0.0, 0.0}, filter: filter, source: source}
  end

  @doc """
  The print correction a colour compensating filter stands for, as `{rg, bg}`.
  A filter holds back the colours it is not: magenta holds back green, red
  holds back green and blue, and so on.
  """
  def filter_cast(nil), do: {0.0, 0.0}

  def filter_cast(name) when is_binary(name) do
    case Regex.run(~r/\A(\d+(?:\.\d+)?)([RGBCMY])\z/, name) do
      [_, number, colour] ->
        d =
          String.to_float(if String.contains?(number, "."), do: number, else: number <> ".0") /
            100

        {r, g, b} = held_back(colour, d)
        # Taking a channel down by d raises the others' ratio to it.
        {g - r, g - b}

      nil ->
        {0.0, 0.0}
    end
  end

  defp held_back("R", d), do: {0.0, d, d}
  defp held_back("G", d), do: {d, 0.0, d}
  defp held_back("B", d), do: {d, d, 0.0}
  defp held_back("C", d), do: {d, 0.0, 0.0}
  defp held_back("M", d), do: {0.0, d, 0.0}
  defp held_back("Y", d), do: {0.0, 0.0, d}

  @doc """
  The Temp and Tint that move a print by `{rg, bg}`, from where its Temp
  stands now: `%{"wb.temp" => kelvins, "wb.tint" => units}` as changes, the
  temperature as the new value (kelvins do not add) and the tint as an
  offset.
  """
  def sliders({rg, bg}, temp \\ 6500.0) do
    {ar, ab} = @per_mired
    {cr, cb} = @per_tint
    det = ar * cb - ab * cr
    mired = (rg * cb - bg * cr) / det
    tint = (ar * bg - ab * rg) / det
    new_mired = 1.0e6 / temp + mired
    kelvin = if new_mired > 20, do: 1.0e6 / new_mired, else: 50_000.0
    %{"wb.temp" => kelvin |> max(2000.0) |> min(50_000.0), "wb.tint" => tint}
  end

  @doc "How far a Temp and Tint move a print, as `{rg, bg}`: the inverse of `sliders/2`."
  def cast_of(temp_from, temp_to, tint) do
    mired = 1.0e6 / temp_to - 1.0e6 / temp_from
    {ar, ab} = @per_mired
    {cr, cb} = @per_tint
    {ar * mired + cr * tint, ab * mired + cb * tint}
  end
end
