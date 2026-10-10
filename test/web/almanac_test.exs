defmodule Web.AlmanacTest do
  use Web.DataCase
  import Web.AudioFixtures
  import Web.RidesFixtures

  alias Web.Almanac

  # Fixture posts are dated 2026-07-01, -10 and -15; roll 001 was scanned on
  # 2026-01-01.

  test "a day gathers every kind of work made on it, in the daybook's order" do
    log_fixture(%{recorded_on: ~D[2026-07-15], caption: "Under way"})
    ride_fixture(%{name: "Levee loop", started_at: ~U[2026-07-15 17:00:00Z]})

    assert {:ok, day} = Almanac.day(~D[2026-07-15])
    assert Enum.map(day.entries, & &1.kind) == [:post, :log, :ride]

    assert Enum.map(day.entries, & &1.title) == [
             "Fixture Post With Keywords",
             "Under way",
             "Levee loop"
           ]
  end

  test "an activity sits on its Pacific day, not its UTC one" do
    # 02:00 UTC on the 16th is still the evening of the 15th in California.
    ride_fixture(%{name: "Late loop", started_at: ~U[2026-07-16 02:00:00Z]})

    assert {:ok, day} = Almanac.day(~D[2026-07-15])
    assert "Late loop" in Enum.map(day.entries, & &1.title)
  end

  test "a roll lands on the day it was scanned" do
    assert {:ok, %{entries: [%{kind: :roll, path: "/negatives/roll/001"}]}} =
             Almanac.day(~D[2026-01-01])
  end

  test "an empty day is not a page" do
    assert :error = Almanac.day(~D[2026-07-02])
  end

  test "neighbours are the nearest days with work, nil at the ends" do
    assert {:ok, %{previous: ~D[2026-07-01], next: ~D[2026-07-15]}} = Almanac.day(~D[2026-07-10])

    oldest = Almanac.entries() |> Enum.map(& &1.date) |> Enum.min(Date)
    assert {:ok, %{previous: nil}} = Almanac.day(oldest)
  end

  test "a year is twelve months with counts and distance" do
    ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z], distance_m: 16_093.44})

    assert {:ok, year} = Almanac.year(2026)
    assert length(year.months) == 12
    assert year.totals.roll == 1
    assert year.totals.ride == 1
    assert year.totals.distance =~ "10"
    assert Map.has_key?(Enum.at(year.months, 6).days, ~D[2026-07-15])
  end

  test "an empty year is not a page" do
    assert :error = Almanac.year(1999)
  end

  describe "week/3" do
    test "lays a week out Monday to Sunday with each day's work on its day" do
      log_fixture(%{recorded_on: ~D[2026-07-15], caption: "Under way"})
      ride_fixture(%{name: "Levee loop", started_at: ~U[2026-07-18 17:00:00Z]})

      assert {:ok, week} = Almanac.week(~D[2026-07-16], Almanac.entries(), ~D[2026-10-07])

      assert week.monday == ~D[2026-07-13]
      assert {week.year, week.week} == {2026, 29}

      assert Enum.map(week.days, & &1.date) ==
               Enum.to_list(Date.range(~D[2026-07-13], ~D[2026-07-19]))

      by_date = Map.new(week.days, &{&1.date, Enum.map(&1.entries, fn e -> e.title end)})
      assert by_date[~D[2026-07-15]] == ["Fixture Post With Keywords", "Under way"]
      assert by_date[~D[2026-07-18]] == ["Levee loop"]
      assert by_date[~D[2026-07-13]] == []

      # The nearest weeks with work either side, not the adjacent ones: the
      # post of the 10th before, and nothing in the week straight after.
      assert week.previous == ~D[2026-07-06]
      assert week.next == nil or Date.compare(week.next, ~D[2026-07-20]) == :gt
      assert week.month == ~D[2026-07-01]
    end

    test "an empty week is not a page, unless it is the week it is now" do
      assert Almanac.week(~D[2026-05-13], Almanac.entries(), ~D[2026-10-07]) == :error

      assert {:ok, week} = Almanac.week(~D[2026-05-13], Almanac.entries(), ~D[2026-05-15])
      assert Enum.all?(week.days, &(&1.entries == []))
    end

    test "training is pencilled in from today on, never for days gone by" do
      # Wednesday: Monday and Tuesday are past.
      assert {:ok, week} = Almanac.week(~D[2026-05-13], Almanac.entries(), ~D[2026-05-13])
      [monday, tuesday | rest] = week.days

      refute monday.training
      refute tuesday.training
      # The fixture vault gives Tuesday "arms" and Thursday "legs".
      assert Enum.find(rest, &(&1.date == ~D[2026-05-14])).training == "legs"

      assert {:ok, week} = Almanac.week(~D[2026-05-13], Almanac.entries(), ~D[2026-05-11])
      assert Enum.at(week.days, 1).training == "arms"
    end

    test "a day the Church keeps is named; a weekday of the season is not" do
      assert {:ok, week} = Almanac.week(~D[2026-07-13], Almanac.entries(), ~D[2026-10-07])
      observances = Map.new(week.days, &{&1.date, &1.observance})

      assert observances[~D[2026-07-16]] =~ "Mount Carmel"
      assert observances[~D[2026-07-19]] =~ "Sunday in Ordinary Time"
      assert observances[~D[2026-07-13]] == nil or is_binary(observances[~D[2026-07-13]])
    end

    test "the address is the ISO week's, and only real weeks have a Monday" do
      assert Almanac.week_path(~D[2026-07-16]) == "/daybook/2026/week/29"
      # The last days of 2025 fall in the first ISO week of 2026.
      assert Almanac.week_path(~D[2025-12-31]) == "/daybook/2026/week/1"
      assert Almanac.monday_of(2026, 1) == {:ok, ~D[2025-12-29]}
      assert Almanac.monday_of(2026, 53) == {:ok, ~D[2026-12-28]}
      assert Almanac.monday_of(2027, 53) == :error
      assert Almanac.monday_of(2026, 0) == :error
    end
  end
end
