defmodule Web.ClockTest do
  use ExUnit.Case, async: true

  alias Web.Clock

  test "winter dates use UTC-8" do
    assert Clock.local_today(~U[2026-01-15 07:59:00Z]) == ~D[2026-01-14]
    assert Clock.local_today(~U[2026-01-15 08:00:00Z]) == ~D[2026-01-15]
    assert Clock.local_today(~U[2026-12-15 07:30:00Z]) == ~D[2026-12-14]
  end

  test "summer dates use UTC-7" do
    assert Clock.local_today(~U[2026-07-15 06:59:00Z]) == ~D[2026-07-14]
    assert Clock.local_today(~U[2026-07-15 07:00:00Z]) == ~D[2026-07-15]
  end

  test "DST begins at 10:00 UTC on the second Sunday of March" do
    # 2026: second Sunday of March is the 8th. Before the switch, PST.
    assert Clock.local_today(~U[2026-03-08 07:30:00Z]) == ~D[2026-03-07]
    # The day after the switch, PDT.
    assert Clock.local_today(~U[2026-03-09 07:30:00Z]) == ~D[2026-03-09]
  end

  test "DST ends at 09:00 UTC on the first Sunday of November" do
    # 2026: first Sunday of November is the 1st. The day before, PDT.
    assert Clock.local_today(~U[2026-10-31 07:30:00Z]) == ~D[2026-10-31]
    # The day after the switch, PST.
    assert Clock.local_today(~U[2026-11-02 07:30:00Z]) == ~D[2026-11-01]
  end

  describe "local_day_start_utc/1" do
    # Analytics used a hardcoded -8 for this, which put "today" an hour off
    # for the ~8 months of the year that are PDT.
    test "winter midnight is 08:00 UTC" do
      assert Clock.local_day_start_utc(~U[2026-01-15 20:00:00Z]) == ~N[2026-01-15 08:00:00]
    end

    test "summer midnight is 07:00 UTC" do
      assert Clock.local_day_start_utc(~U[2026-07-15 20:00:00Z]) == ~N[2026-07-15 07:00:00]
    end

    test "just after local midnight still belongs to the new day" do
      assert Clock.local_day_start_utc(~U[2026-07-15 07:01:00Z]) == ~N[2026-07-15 07:00:00]
    end

    test "just before local midnight still belongs to the old day" do
      assert Clock.local_day_start_utc(~U[2026-07-15 06:59:00Z]) == ~N[2026-07-14 07:00:00]
    end

    # On the transition days the offset at local midnight is not the offset
    # in effect later that afternoon, which is the case a naive conversion
    # gets wrong.
    test "spring-forward day starts at PST midnight, not PDT" do
      assert Clock.local_day_start_utc(~U[2026-03-08 20:00:00Z]) == ~N[2026-03-08 08:00:00]
    end

    test "fall-back day starts at PDT midnight, not PST" do
      assert Clock.local_day_start_utc(~U[2026-11-01 20:00:00Z]) == ~N[2026-11-01 07:00:00]
    end
  end

  test "today_slug maps the Pacific-local weekday" do
    # 2026-08-03 is a Monday
    assert Clock.today_slug(~U[2026-08-03 12:00:00Z]) == "monday"
    # 05:00 UTC on the 3rd is still Sunday the 2nd in PDT
    assert Clock.today_slug(~U[2026-08-03 05:00:00Z]) == "sunday"
  end
end
