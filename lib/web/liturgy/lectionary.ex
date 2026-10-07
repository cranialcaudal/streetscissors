defmodule Web.Liturgy.Lectionary do
  @moduledoc """
  The readings at Mass, as citations: which passages, not their words. The
  words come from whatever Bible the site hosts (`Web.Bible`).

  `priv/liturgy/lectionary.json` lists the citations day by day for the
  dioceses of the United States, 2023 through October 2027, from the
  catholic-daily-readings project. That span holds every Sunday cycle (A, B,
  C) and both weekday cycles, so the lectionary can be read back out of it for
  any later date: `for_date/1` answers a date the file has directly, and
  otherwise finds the most recent date in it that was the same liturgical day
  (the same Sunday of the same cycle, the same weekday of the same week and
  year, the same feast) and gives that day's readings, saying which day it
  borrowed them from. A memorial keeps the weekday's readings unless the file
  shows that memorial with readings of its own (Saint Martha, Our Lady of
  Sorrows), in which case those are borrowed instead.

  Upstream left the days with more than one Mass empty (Christmas, Pentecost,
  the Sundays of Lent with a scrutiny, the solemnities with a vigil). Those
  were filled in here by hand from the Lectionary for Mass.

  The days are matched on the United States calendar, not the Carmelite one:
  the file has no readings proper to the Order, so on a day only Carmel keeps
  (Saint Teresa as a solemnity, Our Lady of Mount Carmel) what comes back is
  the readings of the day everywhere else.
  """

  alias Web.Liturgy.Calendar

  @labels %{
    "first_reading" => "First Reading",
    "second_reading" => "Second Reading",
    "third_reading" => "Third Reading",
    "fourth_reading" => "Fourth Reading",
    "fifth_reading" => "Fifth Reading",
    "sixth_reading" => "Sixth Reading",
    "seventh_reading" => "Seventh Reading",
    "epistle" => "Epistle",
    "responsorial_psalm" => "Responsorial Psalm",
    "alleluia" => "Alleluia",
    "verse_before_gospel" => "Verse before the Gospel",
    "gospel" => "Gospel"
  }

  @type reading :: %{kind: String.t(), label: String.t(), citation: String.t(), psalm: boolean}
  @type mass :: %{name: String.t() | nil, readings: [reading]}

  @doc """
  The Masses of `date` and their readings.

  Returns `%{masses: [mass], from: nil | Date.t()}`; `from` is the earlier
  date the readings were borrowed from when the file does not reach `date`.
  `masses` is empty when nothing in the file matches.
  """
  @spec for_date(Date.t()) :: %{masses: [mass], from: Date.t() | nil}
  def for_date(%Date{} = date) do
    %{days: days, index: index, memorials: memorials} = data()

    with nil <- days[Date.to_iso8601(date)],
         {key, celebration} = filed(date),
         iso when is_binary(iso) <- memorials[memorial(celebration)] || index[key] do
      %{masses: masses(days[iso]), from: Date.from_iso8601!(iso)}
    else
      nil -> %{masses: [], from: nil}
      raw -> %{masses: masses(raw), from: nil}
    end
  end

  @doc "The last date the file answers directly."
  def covered_until, do: data().last

  # What the lectionary files a day under: the season's own key, with the
  # Sunday or weekday cycle filled in.
  @doc false
  def key(date), do: date |> filed() |> elem(0)

  defp filed(date) do
    day = Calendar.day(date, calendar: :usa)

    key =
      case day.celebration.key do
        key when is_tuple(key) ->
          key
          |> Tuple.to_list()
          |> Enum.map(fn
            :cycle -> day.sunday_cycle
            :weekday_cycle -> day.weekday_cycle
            part -> part
          end)
          |> List.to_tuple()

        key ->
          key
      end

    {key, day.celebration}
  end

  defp memorial(%{rank: :memorial, symbol: symbol}), do: symbol
  defp memorial(_celebration), do: nil

  defp masses(raw) do
    for mass <- raw do
      %{
        name: mass_name(mass["mass"]),
        readings:
          for [kind, citation] <- mass["readings"] do
            base = String.replace(kind, ~r/_\d+$/, "")

            %{
              kind: kind,
              label: Map.get(@labels, base, "Reading"),
              citation: citation,
              psalm: base == "responsorial_psalm"
            }
          end
      }
    end
  end

  defp mass_name(name) when name in [nil, "", "default", "Mass"], do: nil
  defp mass_name("thursday"), do: nil
  defp mass_name("Year" <> cycle), do: "Year #{cycle}"

  defp mass_name(name),
    do: "#{name} Mass" |> String.replace("alternate Mass", "Alternative readings")

  defp data do
    key = {__MODULE__, :data}

    case :persistent_term.get(key, nil) do
      nil ->
        data = load()
        :persistent_term.put(key, data)
        data

      data ->
        data
    end
  end

  defp load do
    days =
      Application.app_dir(:web, "priv/liturgy/lectionary.json")
      |> File.read!()
      |> Jason.decode!()

    filed =
      for iso <- days |> Map.keys() |> Enum.sort() do
        {key, celebration} = filed(Date.from_iso8601!(iso))
        {iso, key, memorial(celebration)}
      end

    # Later dates overwrite earlier ones, so a borrowed day is the newest, and
    # a day kept as a plain weekday is preferred to one kept as a memorial.
    plain = for {iso, key, nil} <- filed, into: %{}, do: {key, iso}
    index = filed |> Map.new(fn {iso, key, _} -> {key, iso} end) |> Map.merge(plain)

    memorials =
      for {iso, key, symbol} <- filed,
          symbol != nil,
          weekday = plain[key],
          weekday != nil,
          gist(days[iso]) != gist(days[weekday]),
          into: %{},
          do: {symbol, iso}

    # A weekday the file only ever shows under a memorial is taken from one
    # that brought no readings of its own, when there is one.
    ordinary =
      for {iso, key, symbol} <- filed,
          not is_map_key(memorials, symbol),
          into: %{},
          do: {key, iso}

    index = Map.merge(index, ordinary)

    {last, _, _} = List.last(filed)
    %{days: days, index: index, memorials: memorials, last: Date.from_iso8601!(last)}
  end

  # The first reading and Gospel of a day's first Mass, down to their digits,
  # so two spellings of one citation compare equal.
  defp gist([mass | _]) do
    for [kind, citation] <- mass["readings"], kind in ["first_reading", "gospel"] do
      String.replace(citation, ~r/\D/, "")
    end
  end
end
