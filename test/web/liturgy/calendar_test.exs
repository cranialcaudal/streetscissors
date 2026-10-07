defmodule Web.Liturgy.CalendarTest do
  use ExUnit.Case, async: true

  alias Web.Liturgy.{Calendar, Fast}

  defp day(iso, opts \\ []), do: iso |> Date.from_iso8601!() |> Calendar.day(opts)
  defp title(iso, opts \\ []), do: day(iso, opts).celebration.title

  test "Easter" do
    assert Calendar.easter(2024) == ~D[2024-03-31]
    assert Calendar.easter(2026) == ~D[2026-04-05]
    assert Calendar.easter(2027) == ~D[2027-03-28]
    assert Calendar.easter(2038) == ~D[2038-04-25]
  end

  test "an ordinary weekday, with its optional memorials" do
    day = day("2026-10-06")
    assert day.celebration.title == "Tuesday of the Twenty-seventh Week in Ordinary Time"
    assert day.colour == :green
    assert day.psalter_week == 3
    assert day.sunday_cycle == "A"
    assert day.weekday_cycle == "II"
    assert "Saint Bruno, priest" in Enum.map(day.optional, & &1.title)
  end

  test "the seasons turn on the right days" do
    assert title("2026-11-29") == "First Sunday of Advent"
    assert day("2026-11-29").sunday_cycle == "B"
    assert day("2026-12-13").colour == :rose
    assert title("2026-12-25") == "The Nativity of the Lord"
    assert title("2026-12-27") == "The Holy Family of Jesus, Mary and Joseph"
    assert title("2027-01-01") == "Mary, the Holy Mother of God"
    assert title("2027-01-03") == "The Epiphany of the Lord"
    assert title("2027-01-10") == "The Baptism of the Lord"
    assert title("2027-01-11") == "Monday of the First Week in Ordinary Time"
    assert title("2027-02-10") == "Ash Wednesday"
    assert day("2027-02-11").psalter_week == 4
    assert title("2027-03-21") == "Palm Sunday of the Passion of the Lord"
    assert title("2027-03-28") == "Easter Sunday of the Resurrection of the Lord"
    assert title("2027-05-09") == "The Ascension of the Lord"
    assert title("2027-05-16") == "Pentecost Sunday"
    assert title("2027-05-17") == "The Blessed Virgin Mary, Mother of the Church"
    assert title("2027-05-23") == "The Most Holy Trinity"
    assert title("2026-11-22") == "Our Lord Jesus Christ, King of the Universe"
    assert day("2026-11-22").week == 34
  end

  test "Epiphany on January 8 puts the Baptism on the Monday" do
    assert title("2023-01-08") == "The Epiphany of the Lord"
    assert title("2023-01-09") == "The Baptism of the Lord"
    assert title("2023-01-10") == "Tuesday of the First Week in Ordinary Time"
  end

  test "the psalter starts again with each season" do
    assert day("2026-11-29").psalter_week == 1
    assert day("2027-01-11").psalter_week == 1
    assert day("2027-02-14").psalter_week == 1
    assert day("2027-03-28").psalter_week == 1
    # Holy Week is the sixth week of Lent: Week II.
    assert day("2027-03-22").psalter_week == 2
  end

  describe "Carmel's own days" do
    test "its three solemnities and its feasts" do
      assert %{rank: :solemnity, proper: true} = day("2026-07-16").celebration
      assert title("2026-07-16") =~ "Mount Carmel"
      assert %{rank: :solemnity} = day("2026-10-15").celebration
      assert title("2026-10-15") =~ "Saint Teresa of Jesus, our Mother"
      assert %{rank: :solemnity} = day("2026-12-14").celebration
      assert %{rank: :feast} = day("2026-10-01").celebration
      assert title("2026-07-20") == "Our Father Saint Elijah, prophet"
      assert title("2026-11-14") == "All Saints of the Order"
    end

    test "the same days in the general calendar are what they are everywhere" do
      assert %{rank: :memorial} = day("2026-10-15", calendar: :usa).celebration

      assert title("2026-07-16", calendar: :usa) ==
               "Thursday of the Fifteenth Week in Ordinary Time"
    end

    test "a saint moved out of the way is on his new day only" do
      titles = fn iso -> Enum.map(day(iso).optional, & &1.title) end
      assert "Saint Henry" in titles.("2026-07-10")
      refute "Saint Henry" in titles.("2026-07-13")
      assert title("2026-07-13") =~ "of the Andes"
    end

    test "a solemnity gives way to a Sunday of Advent and is kept the next day" do
      # December 14, 2025 is the Third Sunday of Advent.
      assert title("2025-12-14") == "Third Sunday of Advent"
      assert title("2025-12-15") =~ "Saint John of the Cross"
    end

    test "the commemoration of the Order's dead moves off a Sunday" do
      assert title("2026-11-15") == "Thirty-third Sunday in Ordinary Time"
      assert title("2026-11-16") == "Commemoration of All the Faithful Departed of the Order"
    end
  end

  describe "what gives way" do
    test "solemnities in Holy Week and on Sundays of Advent are transferred" do
      # 2024: Saint Joseph stays, the Annunciation falls in Holy Week.
      assert title("2024-03-19") =~ "Saint Joseph"
      assert title("2024-03-25") == "Monday of Holy Week"
      assert title("2024-04-08") == "The Annunciation of the Lord"
      assert title("2024-12-08") == "Second Sunday of Advent"
      assert title("2024-12-09") =~ "Immaculate Conception"
      # 2035: March 19 is the Monday of Holy Week, so Saint Joseph is the Saturday before.
      assert Calendar.easter(2035) == ~D[2035-03-25]
      assert title("2035-03-17") =~ "Saint Joseph"
    end

    test "a memorial in Lent is a commemoration, and a feast loses to a Sunday" do
      day = day("2027-03-08")
      assert day.celebration.title == "Monday of the Fourth Week of Lent"
      assert "Saint John of God, religious" in Enum.map(day.optional, & &1.title)
      # Saint Lawrence, a feast, on a Sunday in 2025.
      assert title("2025-08-10") == "Nineteenth Sunday in Ordinary Time"
      # The Transfiguration, a feast of the Lord, wins its Sunday in 2028.
      assert title("2028-08-06") == "The Transfiguration of the Lord"
    end
  end

  test "the days of the dead are commemorations, not feasts" do
    assert %{rank: :commemoration, colour: :violet} = day("2026-11-02").celebration
    assert title("2026-11-02") =~ "All the Faithful Departed"
    assert %{rank: :commemoration} = day("2026-11-16").celebration
    # All Souls ranks with the solemnities but does not lift the fast.
    assert %{carmelite: %{fast: true}} = Fast.for_day(day("2026-11-02"))
  end

  describe "the fast" do
    test "the Rule's season runs from the Exaltation of the Cross to Easter, Sundays excepted" do
      fast = fn iso -> iso |> day() |> Fast.for_day() end

      assert %{carmelite: %{season: false, fast: false}} = fast.("2026-09-13")
      assert %{carmelite: %{season: true, fast: true}} = fast.("2026-09-15")
      assert %{carmelite: %{season: true, fast: true}} = fast.("2026-10-06")
      assert %{carmelite: %{season: true, fast: false}} = fast.("2026-10-11")
      # Saint Teresa: a solemnity in Carmel.
      assert %{carmelite: %{season: true, fast: false}} = fast.("2026-10-15")
      assert %{carmelite: %{fast: false}} = fast.("2026-12-25")
      assert %{carmelite: %{fast: true}} = fast.("2027-03-27")
      assert %{carmelite: %{season: false}} = fast.("2027-03-28")
      assert %{carmelite: %{season: false}} = fast.("2027-06-01")
    end

    test "the Church's days" do
      church = fn iso -> (iso |> day() |> Fast.for_day()).church end

      assert %{title: "Fast and abstinence"} = church.("2027-02-10")
      assert %{title: "Fast and abstinence"} = church.("2027-03-26")
      assert %{title: "Abstinence"} = church.("2027-02-19")
      assert %{title: "Friday penance"} = church.("2026-10-09")
      assert church.("2026-10-06") == nil
      # Christmas Day 2026 is a Friday and a solemnity.
      assert church.("2026-12-25") == nil
    end
  end
end
