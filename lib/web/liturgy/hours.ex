defmodule Web.Liturgy.Hours do
  @moduledoc """
  Morning, Evening and Night Prayer, laid out from the Church's four-week
  psalter and prayed from the Bible the site hosts.

  Which psalm falls on which day is the psalter's own arrangement (the tables
  below are the distribution in the Liturgy of the Hours, cited in the Hebrew
  numbering the modern books print). The words are not the official ones: the
  approved English psalter, antiphons, intercessions and collects are under
  copyright, so the psalms and canticles come from `Web.Bible`, the antiphons
  are left out, and the fixed prayers are the traditional texts in
  `Web.Liturgy.Prayers`. What a reader gets is the hour's real shape and its
  real psalms in another translation, which is enough to pray it; it is not a
  substitute for the breviary where the office is an obligation.

  Three simplifications, all of which the page states:

    * On solemnities and feasts Morning Prayer takes the psalms of Sunday,
      Week I, as the books direct; Evening Prayer keeps the weekday's rather
      than the proper psalms of the feast.
    * The short readings are those of Week I of the psalter, every week.
    * A Saturday evening is always the First Evening Prayer of Sunday.

  `office/2` returns the hour as a list of parts for a template to walk, each
  `%{type: …}`; anything with a `:citation` is looked up in the hosted Bible.
  """

  alias Web.Liturgy.{Calendar, Prayers}

  @hours [:lauds, :vespers, :compline]

  # {week, weekday} with Monday = 1 … Sunday = 7.
  @lauds %{
    {1, 7} => ["Ps 63:2-9", "Dan 3:57-88, 56", "Ps 149"],
    {1, 1} => ["Ps 5:2-10, 12-13", "1 Chr 29:10-13", "Ps 29"],
    {1, 2} => ["Ps 24", "Tobit 13:1-8", "Ps 33"],
    {1, 3} => ["Ps 36", "Judith 16:2-3, 13-15", "Ps 47"],
    {1, 4} => ["Ps 57", "Jer 31:10-14", "Ps 48"],
    {1, 5} => ["Ps 51", "Isa 45:15-25", "Ps 100"],
    {1, 6} => ["Ps 119:145-152", "Exod 15:1-4, 8-13, 17-18", "Ps 117"],
    {2, 7} => ["Ps 118", "Dan 3:52-57", "Ps 150"],
    {2, 1} => ["Ps 42", "Sirach 36:1-5, 10-13", "Ps 19:2-7"],
    {2, 2} => ["Ps 43", "Isa 38:10-14, 17-20", "Ps 65"],
    {2, 3} => ["Ps 77", "1 Sam 2:1-10", "Ps 97"],
    {2, 4} => ["Ps 80", "Isa 12:1-6", "Ps 81"],
    {2, 5} => ["Ps 51", "Hab 3:2-4, 13, 15-19", "Ps 147:12-20"],
    {2, 6} => ["Ps 92", "Deut 32:1-12", "Ps 8"],
    {3, 7} => ["Ps 93", "Dan 3:57-88, 56", "Ps 148"],
    {3, 1} => ["Ps 84", "Isa 2:2-5", "Ps 96"],
    {3, 2} => ["Ps 85", "Isa 26:1-4, 7-9, 12", "Ps 67"],
    {3, 3} => ["Ps 86", "Isa 33:13-16", "Ps 98"],
    {3, 4} => ["Ps 87", "Isa 40:10-17", "Ps 99"],
    {3, 5} => ["Ps 51", "Jer 14:17-21", "Ps 100"],
    {3, 6} => ["Ps 119:145-152", "Wis 9:1-6, 9-11", "Ps 117"],
    {4, 7} => ["Ps 118", "Dan 3:52-57", "Ps 150"],
    {4, 1} => ["Ps 90", "Isa 42:10-16", "Ps 135:1-12"],
    {4, 2} => ["Ps 101", "Dan 3:26, 27, 29, 34-41", "Ps 144:1-10"],
    {4, 3} => ["Ps 108", "Isa 61:10—62:5", "Ps 146"],
    {4, 4} => ["Ps 143:1-11", "Isa 66:10-14", "Ps 147:1-11"],
    {4, 5} => ["Ps 51", "Tobit 13:8-11, 13-15", "Ps 147:12-20"],
    {4, 6} => ["Ps 92", "Ezek 36:24-28", "Ps 8"]
  }

  # {week, weekday}; 6 is Saturday's First Evening Prayer of the Sunday that
  # opens `week`, and 7 is that Sunday's Second.
  @vespers %{
    {1, 6} => ["Ps 141:1-9", "Ps 142", "Phil 2:6-11"],
    {1, 7} => ["Ps 110:1-5, 7", "Ps 114", "Rev 19:1-7"],
    {1, 1} => ["Ps 11", "Ps 15", "Eph 1:3-10"],
    {1, 2} => ["Ps 20", "Ps 21:2-8, 14", "Rev 4:11; 5:9, 10, 12"],
    {1, 3} => ["Ps 27:1-6", "Ps 27:7-14", "Col 1:12-20"],
    {1, 4} => ["Ps 30", "Ps 32", "Rev 11:17-18; 12:10-12"],
    {1, 5} => ["Ps 41", "Ps 46", "Rev 15:3-4"],
    {2, 6} => ["Ps 119:105-112", "Ps 16", "Phil 2:6-11"],
    {2, 7} => ["Ps 110:1-5, 7", "Ps 115", "Rev 19:1-7"],
    {2, 1} => ["Ps 45:2-10", "Ps 45:11-18", "Eph 1:3-10"],
    {2, 2} => ["Ps 49:2-13", "Ps 49:14-21", "Rev 4:11; 5:9, 10, 12"],
    {2, 3} => ["Ps 62", "Ps 67", "Col 1:12-20"],
    {2, 4} => ["Ps 72:2-11", "Ps 72:12-19", "Rev 11:17-18; 12:10-12"],
    {2, 5} => ["Ps 116:1-9", "Ps 121", "Rev 15:3-4"],
    {3, 6} => ["Ps 113", "Ps 116:10-19", "Phil 2:6-11"],
    {3, 7} => ["Ps 110:1-5, 7", "Ps 111", "Rev 19:1-7"],
    {3, 1} => ["Ps 123", "Ps 124", "Eph 1:3-10"],
    {3, 2} => ["Ps 125", "Ps 131", "Rev 4:11; 5:9, 10, 12"],
    {3, 3} => ["Ps 126", "Ps 127", "Col 1:12-20"],
    {3, 4} => ["Ps 132:1-10", "Ps 132:11-18", "Rev 11:17-18; 12:10-12"],
    {3, 5} => ["Ps 135:1-12", "Ps 135:13-21", "Rev 15:3-4"],
    {4, 6} => ["Ps 122", "Ps 130", "Phil 2:6-11"],
    {4, 7} => ["Ps 110:1-5, 7", "Ps 112", "Rev 19:1-7"],
    {4, 1} => ["Ps 136:1-9", "Ps 136:10-26", "Eph 1:3-10"],
    {4, 2} => ["Ps 137:1-6", "Ps 138", "Rev 4:11; 5:9, 10, 12"],
    {4, 3} => ["Ps 139:1-12", "Ps 139:13-18, 23-24", "Col 1:12-20"],
    {4, 4} => ["Ps 144:1-8", "Ps 144:9-15", "Rev 11:17-18; 12:10-12"],
    {4, 5} => ["Ps 145:1-13", "Ps 145:13-21", "Rev 15:3-4"]
  }

  # Night Prayer is one week long: {psalms, reading}.
  @compline %{
    6 => {["Ps 4", "Ps 134"], "Deut 6:4-7"},
    7 => {["Ps 91"], "Rev 22:4-5"},
    1 => {["Ps 86"], "1 Thess 5:9-10"},
    2 => {["Ps 143:1-11"], "1 Pet 5:8-9"},
    3 => {["Ps 31:2-6", "Ps 130"], "Eph 4:26-27"},
    4 => {["Ps 16"], "1 Thess 5:23"},
    5 => {["Ps 88"], "Jer 14:9"}
  }

  # The short readings of Week I (Wednesday morning's is Week II's, because
  # Week I reads Tobit there and the Vulgate numbers Tobit differently).
  @lauds_readings %{
    7 => "Rev 7:10, 12",
    1 => "2 Thess 3:10-13",
    2 => "Rom 13:11-13",
    3 => "Rom 8:35, 37",
    4 => "Isa 66:1-2",
    5 => "Eph 4:29-32",
    6 => "2 Pet 1:10-11"
  }

  @vespers_readings %{
    6 => "Rom 11:33-36",
    7 => "2 Cor 1:3-4",
    1 => "Col 1:9-11",
    2 => "1 John 3:1-2",
    3 => "James 1:22, 25",
    4 => "1 Pet 1:6-9",
    5 => "Rom 15:1-3"
  }

  @names %{lauds: "Morning Prayer", vespers: "Evening Prayer", compline: "Night Prayer"}
  @latin %{lauds: "Lauds", vespers: "Vespers", compline: "Compline"}

  def hours, do: @hours
  def name(hour), do: @names[hour]
  def latin(hour), do: @latin[hour]

  @doc "The citations an hour is built from on `date`, for a summary line."
  def psalms(hour, date), do: date |> Calendar.day() |> psalmody(hour) |> elem(0)

  @doc "The hour on `date`: `%{hour, name, latin, day, note, parts}`."
  def office(hour, %Date{} = date) when hour in @hours do
    day = Calendar.day(date)
    {psalms, reading, note} = psalmody(day, hour)
    alleluia? = day.season not in [:lent, :triduum]

    parts =
      [opening(alleluia?)] ++
        examen(hour) ++
        Enum.map(psalms, &psalm/1) ++
        [%{type: :reading, citation: reading}] ++
        closing(hour, day)

    %{hour: hour, name: @names[hour], latin: @latin[hour], day: day, note: note, parts: parts}
  end

  defp psalmody(day, :lauds) do
    festal? = day.celebration.rank in [:solemnity, :feast, :triduum] and day.weekday != 7

    if festal? do
      {@lauds[{1, 7}], @lauds_readings[7],
       "On a solemnity or feast the psalms are those of Sunday, Week I."}
    else
      {@lauds[{day.psalter_week, day.weekday}], @lauds_readings[day.weekday], nil}
    end
  end

  defp psalmody(day, :vespers) do
    case day.weekday do
      6 ->
        sunday = Calendar.day(Date.add(day.date, 1))

        {@vespers[{sunday.psalter_week, 6}], @vespers_readings[6],
         "Saturday evening is the First Evening Prayer of Sunday."}

      7 ->
        [first, second, canticle] = @vespers[{day.psalter_week, 7}]
        canticle = if day.season == :lent, do: "1 Pet 2:21-24", else: canticle
        {[first, second, canticle], @vespers_readings[7], nil}

      weekday ->
        {@vespers[{day.psalter_week, weekday}], @vespers_readings[weekday], nil}
    end
  end

  defp psalmody(day, :compline) do
    {psalms, reading} = @compline[day.weekday]
    {psalms, reading, nil}
  end

  defp opening(alleluia?) do
    %{
      type: :versicle,
      lines: [
        {"V", "O God, come to my assistance."},
        {"R", "O Lord, make haste to help me."},
        {nil, Prayers.text(:glory_be) <> if(alleluia?, do: " Alleluia.", else: "")}
      ]
    }
  end

  defp examen(:compline) do
    [
      %{
        type: :rubric,
        text: "Look back over the day in silence, and ask pardon for what was amiss in it."
      }
    ]
  end

  defp examen(_hour), do: []

  defp psalm(citation) do
    type = if String.starts_with?(citation, "Ps "), do: :psalm, else: :canticle
    %{type: type, citation: citation, doxology: Prayers.text(:glory_be)}
  end

  defp closing(:lauds, _day) do
    [
      %{
        type: :gospel_canticle,
        title: "Canticle of Zechariah",
        latin: "Benedictus",
        citation: "Luke 1:68-79",
        doxology: Prayers.text(:glory_be)
      },
      %{
        type: :rubric,
        text: "Pray for the Church, for the world, for the poor and for the day's work."
      },
      prayer(:our_father),
      prayer(:direct_our_actions),
      blessing()
    ]
  end

  defp closing(:vespers, _day) do
    [
      %{
        type: :gospel_canticle,
        title: "Canticle of Mary",
        latin: "Magnificat",
        citation: "Luke 1:46-55",
        doxology: Prayers.text(:glory_be)
      },
      %{
        type: :rubric,
        text: "Pray for the Church, for the world, for the sick and for the dead."
      },
      prayer(:our_father),
      prayer(:pour_forth),
      blessing()
    ]
  end

  defp closing(:compline, day) do
    marian = if day.season == :easter, do: :regina_caeli, else: :salve_regina

    [
      %{
        type: :versicle,
        lines: [
          {"V", "Into thy hands, O Lord, I commend my spirit."},
          {"R", "Thou hast redeemed us, O Lord, God of truth."}
        ]
      },
      %{
        type: :gospel_canticle,
        title: "Canticle of Simeon",
        latin: "Nunc dimittis",
        citation: "Luke 2:29-32",
        doxology: Prayers.text(:glory_be)
      },
      prayer(:visit_this_house),
      %{
        type: :versicle,
        lines: [{nil, "May the almighty Lord grant us a quiet night and a perfect end. Amen."}]
      },
      prayer(marian)
    ]
  end

  defp blessing do
    %{
      type: :versicle,
      lines: [
        {nil,
         "May the Lord bless us, keep us from all evil, and bring us to life everlasting. Amen."}
      ]
    }
  end

  defp prayer(key), do: %{type: :prayer, title: Prayers.title(key), text: Prayers.text(key)}
end
