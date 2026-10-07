defmodule Web.Liturgy.Rosary do
  @moduledoc """
  The mysteries of the Rosary, the day each set is prayed, and the passage of
  scripture each one rests on (read from the hosted Bible).

  The days are the customary ones: Joyful on Monday and Saturday, Sorrowful on
  Tuesday and Friday, Glorious on Wednesday and Sunday, Luminous on Thursday.

  Scripture does not narrate the Assumption or the Coronation of Mary. The
  passages given with those two are ones traditionally read beside them, and
  the page says so.
  """

  alias Web.Liturgy.Prayers

  @ordinals ~w(First Second Third Fourth Fifth)

  @notes %{
    "The Assumption of Mary" =>
      "Scripture does not narrate the Assumption. This passage, Mary's own canticle, is one traditionally read with the mystery.",
    "The Coronation of Mary" =>
      "Scripture does not narrate the Coronation. This vision from the Apocalypse is the passage traditionally read with the mystery."
  }

  @sets %{
    joyful:
      {"The Joyful Mysteries",
       [
         {"The Annunciation", "Luke 1:26-38"},
         {"The Visitation", "Luke 1:39-45"},
         {"The Nativity", "Luke 2:1-14"},
         {"The Presentation in the Temple", "Luke 2:22-35"},
         {"The Finding in the Temple", "Luke 2:41-52"}
       ]},
    luminous:
      {"The Luminous Mysteries",
       [
         {"The Baptism in the Jordan", "Matthew 3:13-17"},
         {"The Wedding at Cana", "John 2:1-11"},
         {"The Proclamation of the Kingdom", "Mark 1:14-15"},
         {"The Transfiguration", "Luke 9:28-36"},
         {"The Institution of the Eucharist", "Luke 22:14-20"}
       ]},
    sorrowful:
      {"The Sorrowful Mysteries",
       [
         {"The Agony in the Garden", "Luke 22:39-46"},
         {"The Scourging at the Pillar", "John 19:1"},
         {"The Crowning with Thorns", "Matthew 27:27-31"},
         {"The Carrying of the Cross", "Luke 23:26-32"},
         {"The Crucifixion", "Luke 23:33-46"}
       ]},
    glorious:
      {"The Glorious Mysteries",
       [
         {"The Resurrection", "Matthew 28:1-10"},
         {"The Ascension", "Acts 1:6-11"},
         {"The Descent of the Holy Spirit", "Acts 2:1-4"},
         {"The Assumption of Mary", "Luke 1:46-50"},
         {"The Coronation of Mary", "Revelation 11:19; 12:1"}
       ]}
  }

  @by_weekday %{
    1 => :joyful,
    2 => :sorrowful,
    3 => :glorious,
    4 => :luminous,
    5 => :sorrowful,
    6 => :joyful,
    7 => :glorious
  }

  @doc "The set prayed on `date`: `%{key, title, mysteries: [%{title, citation}]}`."
  def for_date(%Date{} = date), do: set(@by_weekday[Date.day_of_week(date)])

  def set(key) when is_map_key(@sets, key) do
    {title, mysteries} = @sets[key]

    %{
      key: key,
      title: title,
      mysteries:
        for {title, citation} <- mysteries do
          %{title: title, citation: citation, note: @notes[title]}
        end
    }
  end

  @doc """
  The Rosary bead by bead, for praying it one step at a time:
  `[%{bead, title, text | mystery}]`. `bead` is `:crucifix`, `:large` (an Our
  Father), `:small` (a Hail Mary), `:chain` (said between beads), `:mystery`
  (the announcement, which carries the mystery instead of a text) or `:medal`.
  """
  def steps(%{mysteries: mysteries}) do
    hail_marys = fn count ->
      for n <- 1..count do
        %{bead: :small, title: "Hail Mary, #{n} of #{count}", text: Prayers.text(:hail_mary)}
      end
    end

    our_father = %{bead: :large, title: "Our Father", text: Prayers.text(:our_father)}
    glory_be = %{bead: :chain, title: "Glory Be", text: Prayers.text(:glory_be)}

    opening =
      [
        %{
          bead: :crucifix,
          title: "The Sign of the Cross",
          text: Prayers.text(:sign_of_the_cross)
        },
        %{bead: :crucifix, title: "The Apostles' Creed", text: Prayers.text(:apostles_creed)},
        our_father
      ] ++ hail_marys.(3) ++ [glory_be]

    decades =
      for {mystery, ordinal} <- Enum.zip(mysteries, @ordinals) do
        [
          %{bead: :mystery, title: "The #{ordinal} Mystery: #{mystery.title}", mystery: mystery},
          our_father
        ] ++
          hail_marys.(10) ++
          [glory_be, %{bead: :chain, title: "The Fatima Prayer", text: Prayers.text(:fatima)}]
      end

    closing = [%{bead: :medal, title: "Hail, Holy Queen", text: Prayers.text(:salve_regina)}]

    opening ++ List.flatten(decades) ++ closing
  end

  def keys, do: [:joyful, :luminous, :sorrowful, :glorious]
end
