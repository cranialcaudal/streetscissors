defmodule Web.AlmanacTest do
  use Web.DataCase
  import Web.AudioFixtures
  import Web.RidesFixtures

  alias Web.Almanac

  # Fixture posts are dated 2026-07-01, -10 and -15; roll 001 was scanned on
  # 2026-01-01.

  test "a day gathers every kind of work made on it, in the almanac's order" do
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
end
