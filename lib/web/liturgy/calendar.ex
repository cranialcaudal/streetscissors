defmodule Web.Liturgy.Calendar do
  @moduledoc """
  The liturgical day: what the Church keeps on a date, worked out from the
  date alone.

  `day/1` lays the saints' days (`Web.Liturgy.Sanctoral`) over the seasons and
  keeps whichever ranks higher in the Table of Liturgical Days (Universal
  Norms on the Liturgical Year and the Calendar, 59). The lower `precedence`
  wins:

      1  the Paschal Triduum
      2  Christmas, Epiphany, Ascension, Pentecost; Sundays of Advent, Lent
         and Easter; Ash Wednesday; Holy Week; the Easter octave
      3  solemnities of the general calendar, All Souls
      4  proper solemnities (in Carmel: Our Lady of Mount Carmel, Saint
         Teresa, Saint John of the Cross)
      5  feasts of the Lord
      6  Sundays of Christmas and of Ordinary Time
      7  feasts of the general calendar        8  proper feasts
      9  December 17-24, the Christmas octave, weekdays of Lent
      10 obligatory memorials                  11 proper memorials
      12 optional memorials                    13 other weekdays

  The movable days follow the calendar of the dioceses of the United States,
  since the readings do (`Web.Liturgy.Lectionary`): Epiphany on the Sunday
  between January 2 and 8, the Ascension on the Seventh Sunday of Easter, and
  Corpus Christi on the Sunday after Trinity.

  A solemnity that falls on a day ranking above it is moved to the next free
  day, and Saint Joseph, when March 19 falls in Holy Week, to the Saturday
  before Palm Sunday. A memorial that meets a day of row 9 is kept as an
  optional commemoration; one that meets anything higher is dropped that year.
  """

  alias Web.Liturgy.Sanctoral

  @ordinals ~w(First Second Third Fourth Fifth Sixth Seventh Eighth Ninth Tenth Eleventh
    Twelfth Thirteenth Fourteenth Fifteenth Sixteenth Seventeenth Eighteenth Nineteenth
    Twentieth Twenty-first Twenty-second Twenty-third Twenty-fourth Twenty-fifth
    Twenty-sixth Twenty-seventh Twenty-eighth Twenty-ninth Thirtieth Thirty-first
    Thirty-second Thirty-third Thirty-fourth)

  @weekdays ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday)

  @season_names %{
    advent: "Advent",
    christmas: "Christmas Time",
    ordinary: "Ordinary Time",
    lent: "Lent",
    triduum: "the Paschal Triduum",
    easter: "Easter Time"
  }

  @doc """
  The liturgical day for `date`.

  `calendar:` chooses whose saints are laid over the seasons: `:ocd` (the
  default, the Discalced Carmelite proper on top of the United States'),
  `:usa`, or `:general`.
  """
  def day(%Date{} = date, opts \\ []) do
    calendar = Keyword.get(opts, :calendar, :ocd)
    temporal = temporal(date)
    entries = entries(date, calendar)
    {celebration, optional} = resolve(temporal, entries)
    year = liturgical_year(date)

    %{
      date: date,
      season: temporal.season,
      season_name: @season_names[temporal.season],
      week: temporal.week,
      weekday: Date.day_of_week(date),
      psalter_week: psalter_week(date, temporal),
      sunday_cycle: Enum.at(~w(C A B), rem(year, 3)),
      weekday_cycle: if(rem(year, 2) == 1, do: "I", else: "II"),
      temporal: temporal,
      celebration: celebration,
      optional: optional,
      colour: celebration.colour
    }
  end

  @doc "Easter Sunday of `year` (the Gregorian computus)."
  def easter(year) do
    a = rem(year, 19)
    b = div(year, 100)
    c = rem(year, 100)
    d = div(b, 4)
    e = rem(b, 4)
    f = div(b + 8, 25)
    g = div(b - f + 1, 3)
    h = rem(19 * a + b - d - g + 15, 30)
    i = div(c, 4)
    k = rem(c, 4)
    l = rem(32 + 2 * e + 2 * i - h - k, 7)
    m = div(a + 11 * h + 22 * l, 451)
    month = div(h + l - 7 * m + 114, 31)
    day = rem(h + l - 7 * m + 114, 31) + 1
    Date.new!(year, month, day)
  end

  @doc "The First Sunday of Advent in the civil year `year`."
  def advent(year), do: year |> Date.new!(12, 25) |> sunday_before() |> Date.add(-21)

  @doc "The year whose name the liturgical year containing `date` carries."
  def liturgical_year(date) do
    if Date.compare(date, advent(date.year)) == :lt, do: date.year, else: date.year + 1
  end

  @doc "\"Twenty-seventh\" for 27."
  def ordinal(n), do: Enum.at(@ordinals, n - 1)

  @doc "\"Tuesday\" for a date."
  def weekday_name(date), do: Enum.at(@weekdays, Date.day_of_week(date) - 1)

  # ── The seasons ───────────────────────────────────────────────────────────

  @doc """
  The day the season alone would give, before any saint is considered:
  `%{season, week, title, kind, precedence, colour, key}`. `key` is what the
  lectionary files the day's readings under.
  """
  def temporal(%Date{year: year} = date) do
    easter = easter(year)
    ash = Date.add(easter, -46)
    pentecost = Date.add(easter, 49)
    advent = advent(year)
    baptism = baptism(year)

    cond do
      before?(date, baptism) or date == baptism ->
        christmas(date, year)

      before?(date, ash) ->
        ordinary(date, 1 + div(Date.diff(date, sunday_on_or_before(baptism)), 7))

      before?(date, easter) ->
        lent(date, ash, easter)

      not before?(pentecost, date) ->
        eastertide(date, easter)

      before?(date, advent) ->
        after_pentecost(date, pentecost, advent)

      before?(date, Date.new!(year, 12, 25)) ->
        advent(date, advent)

      true ->
        christmas(date, year)
    end
  end

  defp christmas(%Date{month: 12, day: 25}, _year) do
    base(:christmas, nil, "The Nativity of the Lord", :solemnity, 2, :white, :christmas)
  end

  defp christmas(%Date{month: 12, day: day} = date, year) do
    holy_family =
      if sunday?(Date.new!(year, 12, 25)),
        do: Date.new!(year, 12, 30),
        else: sunday_on_or_after(Date.new!(year, 12, 26))

    if date == holy_family do
      base(
        :christmas,
        nil,
        "The Holy Family of Jesus, Mary and Joseph",
        :feast,
        5,
        :white,
        {:holy_family, :cycle}
      )
    else
      title = "#{ordinal(day - 24)} day within the Octave of the Nativity of the Lord"
      base(:christmas, nil, title, :weekday, 9, :white, {:date, 12, day})
    end
  end

  defp christmas(%Date{month: 1, day: 1}, _year) do
    base(:christmas, nil, "Mary, the Holy Mother of God", :solemnity, 3, :white, {:date, 1, 1})
  end

  defp christmas(%Date{month: 1, day: day} = date, year) do
    epiphany = epiphany(year)

    cond do
      date == epiphany ->
        base(:christmas, nil, "The Epiphany of the Lord", :solemnity, 2, :white, :epiphany)

      date == baptism(year) ->
        base(:christmas, nil, "The Baptism of the Lord", :feast, 5, :white, {:baptism, :cycle})

      before?(date, epiphany) ->
        base(
          :christmas,
          nil,
          "#{weekday_name(date)} before Epiphany (January #{day})",
          :weekday,
          13,
          :white,
          {:date, 1, day}
        )

      true ->
        base(
          :christmas,
          nil,
          "#{weekday_name(date)} after Epiphany",
          :weekday,
          13,
          :white,
          {:after_epiphany, Date.day_of_week(date)}
        )
    end
  end

  defp ordinary(date, week) do
    if sunday?(date) do
      base(
        :ordinary,
        week,
        "#{ordinal(week)} Sunday in Ordinary Time",
        :sunday,
        6,
        :green,
        {:ordinary, week, 7, :cycle}
      )
    else
      title = "#{weekday_name(date)} of the #{ordinal(week)} Week in Ordinary Time"

      base(
        :ordinary,
        week,
        title,
        :weekday,
        13,
        :green,
        {:ordinary, week, Date.day_of_week(date), :weekday_cycle}
      )
    end
  end

  defp lent(date, ash, easter) do
    dow = Date.day_of_week(date)
    # The First Sunday is four days after Ash Wednesday; the days before it are week 0.
    week = div(Date.diff(date, Date.add(ash, 4)) + 7, 7)
    until_easter = Date.diff(easter, date)

    cond do
      date == ash ->
        base(:lent, 0, "Ash Wednesday", :weekday, 2, :violet, {:lent, 0, 3})

      before?(date, Date.add(ash, 4)) ->
        base(
          :lent,
          0,
          "#{weekday_name(date)} after Ash Wednesday",
          :weekday,
          9,
          :violet,
          {:lent, 0, dow}
        )

      until_easter == 7 ->
        base(
          :lent,
          6,
          "Palm Sunday of the Passion of the Lord",
          :sunday,
          2,
          :red,
          {:lent, 6, 7, :cycle}
        )

      until_easter == 3 ->
        base(
          :triduum,
          6,
          "Thursday of the Lord's Supper (Holy Thursday)",
          :triduum,
          1,
          :white,
          {:lent, 6, 4}
        )

      until_easter == 2 ->
        base(
          :triduum,
          6,
          "Friday of the Passion of the Lord (Good Friday)",
          :triduum,
          1,
          :red,
          {:lent, 6, 5}
        )

      until_easter == 1 ->
        base(:triduum, 6, "Holy Saturday", :triduum, 1, :violet, {:lent, 6, 6})

      until_easter < 7 ->
        base(
          :lent,
          6,
          "#{weekday_name(date)} of Holy Week",
          :weekday,
          2,
          :violet,
          {:lent, 6, dow}
        )

      dow == 7 ->
        colour = if week == 4, do: :rose, else: :violet

        base(
          :lent,
          week,
          "#{ordinal(week)} Sunday of Lent",
          :sunday,
          2,
          colour,
          {:lent, week, 7, :cycle}
        )

      true ->
        title = "#{weekday_name(date)} of the #{ordinal(week)} Week of Lent"
        base(:lent, week, title, :weekday, 9, :violet, {:lent, week, dow})
    end
  end

  defp eastertide(date, easter) do
    days = Date.diff(date, easter)
    week = 1 + div(days, 7)
    dow = Date.day_of_week(date)

    cond do
      days == 0 ->
        base(
          :easter,
          1,
          "Easter Sunday of the Resurrection of the Lord",
          :solemnity,
          1,
          :white,
          {:easter, 1, 7, :cycle}
        )

      days < 7 ->
        base(
          :easter,
          1,
          "#{weekday_name(date)} within the Octave of Easter",
          :weekday,
          2,
          :white,
          {:easter, 1, dow}
        )

      days == 7 ->
        base(
          :easter,
          2,
          "Second Sunday of Easter (of Divine Mercy)",
          :sunday,
          2,
          :white,
          {:easter, 2, 7, :cycle}
        )

      days == 42 ->
        base(:easter, 7, "The Ascension of the Lord", :solemnity, 2, :white, {:ascension, :cycle})

      days == 49 ->
        base(:easter, 8, "Pentecost Sunday", :solemnity, 2, :red, {:pentecost, :cycle})

      dow == 7 ->
        base(
          :easter,
          week,
          "#{ordinal(week)} Sunday of Easter",
          :sunday,
          2,
          :white,
          {:easter, week, 7, :cycle}
        )

      true ->
        title = "#{weekday_name(date)} of the #{ordinal(week)} Week of Easter"
        base(:easter, week, title, :weekday, 13, :white, {:easter, week, dow})
    end
  end

  defp after_pentecost(date, pentecost, advent) do
    christ_the_king = Date.add(advent, -7)
    week = 34 - div(Date.diff(christ_the_king, sunday_on_or_before(date)), 7)

    case Date.diff(date, pentecost) do
      7 ->
        base(:ordinary, week, "The Most Holy Trinity", :solemnity, 3, :white, {:trinity, :cycle})

      14 ->
        base(
          :ordinary,
          week,
          "The Most Holy Body and Blood of Christ (Corpus Christi)",
          :solemnity,
          3,
          :white,
          {:corpus_christi, :cycle}
        )

      19 ->
        base(
          :ordinary,
          week,
          "The Most Sacred Heart of Jesus",
          :solemnity,
          3,
          :white,
          {:sacred_heart, :cycle}
        )

      _ when date == christ_the_king ->
        base(
          :ordinary,
          34,
          "Our Lord Jesus Christ, King of the Universe",
          :solemnity,
          3,
          :white,
          {:christ_the_king, :cycle}
        )

      _ ->
        ordinary(date, week)
    end
  end

  defp advent(date, advent) do
    week = 1 + div(Date.diff(date, advent), 7)
    dow = Date.day_of_week(date)

    cond do
      dow == 7 ->
        colour = if week == 3, do: :rose, else: :violet

        base(
          :advent,
          week,
          "#{ordinal(week)} Sunday of Advent",
          :sunday,
          2,
          colour,
          {:advent, week, 7, :cycle}
        )

      date.day >= 17 ->
        title =
          "#{weekday_name(date)} of the #{ordinal(week)} Week of Advent (December #{date.day})"

        base(:advent, week, title, :weekday, 9, :violet, {:date, 12, date.day})

      true ->
        title = "#{weekday_name(date)} of the #{ordinal(week)} Week of Advent"
        base(:advent, week, title, :weekday, 13, :violet, {:advent, week, dow})
    end
  end

  defp base(season, week, title, kind, precedence, colour, key) do
    %{
      season: season,
      week: week,
      title: title,
      kind: kind,
      precedence: precedence,
      colour: colour,
      key: key
    }
  end

  # The psalter begins again at Week I on the First Sunday of Advent, the
  # first week of Ordinary Time, the First Sunday of Lent and Easter Sunday
  # (General Instruction of the Liturgy of the Hours, 133). Christmas Time
  # carries on from Advent, and the days after Ash Wednesday are Week IV.
  defp psalter_week(date, %{season: :christmas}) do
    advent = advent(liturgical_year(date) - 1)
    rem(div(Date.diff(date, advent), 7), 4) + 1
  end

  defp psalter_week(_date, %{season: season, week: 0}) when season in [:lent, :triduum], do: 4
  defp psalter_week(_date, %{week: week}), do: rem(week - 1, 4) + 1

  # ── The saints, and what gives way ────────────────────────────────────────

  defp entries(%Date{year: year, month: month, day: day} = date, calendar) do
    moved = moved_solemnities(year, calendar)

    fixed =
      Sanctoral.on(month, day, calendar)
      |> Enum.reject(&Map.has_key?(moved, &1.symbol))
      |> Enum.reject(&(&1.symbol == "carmelite_souls" and sunday?(date)))

    arriving = for {_symbol, {^date, entry}} <- moved, do: entry

    fixed ++ arriving ++ movable(date) ++ displaced_commemoration(date, calendar)
  end

  # Solemnities that cannot be kept on their own date this year, as
  # `%{symbol => {new_date, entry}}`.
  defp moved_solemnities(year, calendar) do
    easter = easter(year)
    palm = Date.add(easter, -7)

    for {month, day, entry} <- Sanctoral.solemnities(calendar),
        date = Date.new!(year, month, day),
        temporal(date).precedence <= 3,
        into: %{} do
      target =
        if entry.symbol == "joseph" and not before?(date, palm) and before?(date, easter) do
          Date.add(palm, -1)
        else
          next_free_day(Date.add(date, 1), calendar)
        end

      {entry.symbol, {target, entry}}
    end
  end

  defp next_free_day(date, calendar) do
    taken? = Enum.any?(Sanctoral.on(date.month, date.day, calendar), &(&1.rank == :solemnity))

    if temporal(date).precedence >= 5 and not taken?,
      do: date,
      else: next_free_day(Date.add(date, 1), calendar)
  end

  # The two memorials that follow Pentecost rather than a date.
  defp movable(%Date{year: year} = date) do
    case Date.diff(date, easter(year)) do
      50 ->
        [movable_entry("bvm_mother_of_church", "The Blessed Virgin Mary, Mother of the Church")]

      69 ->
        [movable_entry("bvm_immaculate_heart", "The Immaculate Heart of the Blessed Virgin Mary")]

      _ ->
        []
    end
  end

  defp movable_entry(symbol, title) do
    %{
      symbol: symbol,
      title: title,
      rank: :memorial,
      precedence: 10,
      colour: :white,
      proper: false
    }
  end

  # The Order's commemoration of its dead is kept on the Monday when
  # November 15 is a Sunday.
  defp displaced_commemoration(%Date{month: 11, day: 16} = date, calendar) do
    if Date.day_of_week(date) == 1,
      do: Enum.filter(Sanctoral.on(11, 15, calendar), &(&1.symbol == "carmelite_souls")),
      else: []
  end

  defp displaced_commemoration(_date, _calendar), do: []

  defp resolve(temporal, entries) do
    obligatory = Enum.filter(entries, &(&1.rank != :optional))
    best = Enum.min_by(obligatory, & &1.precedence, fn -> nil end)
    lesser = Enum.filter(entries, &(&1.precedence >= 10))

    cond do
      # Two obligatory memorials on one day both become optional.
      temporal.precedence == 13 and Enum.count(obligatory, &(&1.precedence >= 10)) > 1 ->
        {from_temporal(temporal), lesser}

      best != nil and best.precedence < temporal.precedence ->
        {from_entry(best, temporal), []}

      temporal.precedence in [9, 13] ->
        {from_temporal(temporal), lesser}

      true ->
        {from_temporal(temporal), []}
    end
  end

  defp from_temporal(temporal) do
    %{
      title: temporal.title,
      rank: temporal.kind,
      precedence: temporal.precedence,
      colour: temporal.colour,
      symbol: nil,
      proper: false,
      source: :temporal,
      key: temporal.key
    }
  end

  # A memorial keeps the weekday's readings; a feast or a solemnity brings its own.
  defp from_entry(entry, temporal) do
    key = if entry.precedence >= 10, do: temporal.key, else: {:sanctoral, entry.symbol}
    entry |> Map.put(:source, :sanctoral) |> Map.put(:key, key)
  end

  # ── Dates ─────────────────────────────────────────────────────────────────

  # In the United States: the Sunday between January 2 and 8.
  defp epiphany(year), do: sunday_on_or_after(Date.new!(year, 1, 2))

  # The Sunday after Epiphany, or the Monday when Epiphany falls on January
  # 7 or 8 and that Sunday would be gone.
  defp baptism(year) do
    epiphany = epiphany(year)
    if epiphany.day >= 7, do: Date.add(epiphany, 1), else: Date.add(epiphany, 7)
  end

  defp sunday?(date), do: Date.day_of_week(date) == 7
  defp before?(a, b), do: Date.compare(a, b) == :lt
  defp sunday_before(date), do: Date.add(date, -Date.day_of_week(date))
  defp sunday_on_or_before(date), do: Date.add(date, -rem(Date.day_of_week(date), 7))
  defp sunday_on_or_after(date), do: Date.add(date, rem(7 - Date.day_of_week(date), 7))
end
