defmodule Web.Liturgy.LectionaryTest do
  use ExUnit.Case, async: true

  alias Web.Bible
  alias Web.Liturgy.{Hours, Lectionary, Rosary}

  defp citations(date, kind) do
    [mass | _] = Lectionary.for_date(date).masses
    for r <- mass.readings, r.kind == kind, do: r.citation
  end

  test "a day the file holds is answered directly" do
    assert %{from: nil, masses: [%{name: nil, readings: readings}]} =
             Lectionary.for_date(~D[2026-10-06])

    assert Enum.map(readings, & &1.label) == [
             "First Reading",
             "Responsorial Psalm",
             "Alleluia",
             "Gospel"
           ]

    assert citations(~D[2026-10-06], "gospel") == ["Luke 10:38-42"]
  end

  test "Christmas has its four Masses" do
    assert %{masses: masses} = Lectionary.for_date(~D[2026-12-25])
    assert Enum.map(masses, & &1.name) == ["Vigil Mass", "Night Mass", "Dawn Mass", "Day Mass"]
  end

  test "a date past the file borrows the same liturgical day" do
    past = Date.add(Lectionary.covered_until(), 400)
    assert Date.compare(~D[2029-10-09], past) == :gt

    # Tuesday of the 27th week, Year I: borrowed from 2025 or 2027, not from Year II.
    assert %{from: %Date{} = from, masses: [_ | _]} = Lectionary.for_date(~D[2029-10-09])
    assert rem(from.year, 2) == 1
    assert citations(~D[2029-10-09], "gospel") == citations(from, "gospel")

    # A Sunday keeps its cycle: 2029 is Year A, like 2026.
    assert %{from: %Date{year: 2026}} = Lectionary.for_date(~D[2029-03-04])
  end

  test "a memorial keeps the weekday unless it has readings of its own" do
    # Our Lady of Sorrows has a proper Gospel; Saint Francis of Assisi does not.
    assert ["John 19:25-27" <> _ | _] = citations(~D[2028-09-15], "gospel")
    assert %{from: from} = Lectionary.for_date(~D[2028-10-04])
    assert from != nil
  end

  test "all but a handful of days in the years ahead are found" do
    days = Date.range(~D[2027-11-01], ~D[2030-12-31])
    missing = Enum.count(days, &(Lectionary.for_date(&1).masses == []))
    assert missing / Enum.count(days) < 0.02
  end

  test "every psalm, canticle and reading of the Hours is in the hosted Bible" do
    for hour <- Hours.hours(), offset <- 0..27 do
      date = Date.add(~D[2026-10-04], offset)

      for %{citation: citation} <- Hours.office(hour, date).parts do
        assert {:ok, %{verses: [_ | _]}} = Bible.passage(citation), "#{hour} #{date}: #{citation}"
      end
    end
  end

  test "the Hours follow the psalter" do
    # Tuesday, Week III.
    assert Hours.psalms(:lauds, ~D[2026-10-06]) == ["Ps 85", "Isa 26:1-4, 7-9, 12", "Ps 67"]
    assert Hours.psalms(:vespers, ~D[2026-10-06]) == ["Ps 125", "Ps 131", "Rev 4:11; 5:9, 10, 12"]
    assert Hours.psalms(:compline, ~D[2026-10-06]) == ["Ps 143:1-11"]
    # Saturday evening belongs to Sunday, here Sunday of Week IV.
    assert Hours.psalms(:vespers, ~D[2026-10-10]) == ["Ps 122", "Ps 130", "Phil 2:6-11"]
    # A solemnity takes Sunday Week I at Lauds.
    assert Hours.psalms(:lauds, ~D[2026-10-15]) == ["Ps 63:2-9", "Dan 3:57-88, 56", "Ps 149"]
    # In Lent the Sunday evening canticle is from Peter, and the Alleluia is dropped.
    assert List.last(Hours.psalms(:vespers, ~D[2027-02-14])) == "1 Pet 2:21-24"
    [%{lines: lines} | _] = Hours.office(:lauds, ~D[2027-02-15]).parts
    refute Enum.any?(lines, fn {_, text} -> text =~ "Alleluia" end)
  end

  test "every mystery of the Rosary is in the hosted Bible" do
    for key <- Rosary.keys(), %{citation: citation} <- Rosary.set(key).mysteries do
      assert {:ok, _} = Bible.passage(citation), citation
    end

    steps = Rosary.steps(Rosary.set(:glorious))
    assert length(steps) == 78
    assert Enum.count(steps, &(&1.bead == :small)) == 53
    assert Enum.count(steps, &(&1.bead == :large)) == 6

    assert Rosary.set(:glorious).mysteries |> Enum.at(3) |> Map.fetch!(:note) =~
             "does not narrate"

    assert Rosary.for_date(~D[2026-10-06]).key == :sorrowful
    assert Rosary.for_date(~D[2026-10-08]).key == :luminous
  end
end
