defmodule Web.Fitness.WeekTest do
  # Not async: load/0 reads the fixture vault, and Web.Fitness.VaultTest points
  # :fitness_path at a temp dir while it runs. Checks against the author's real
  # week.md live in the gitignored test/private/.
  use ExUnit.Case, async: false

  alias Web.Fitness.Week

  @fixture """
  ---
  title: The Week
  sleep: 21:00-05:30
  window: 05:00-22:00
  ---

  ## Monday
  - 09:00-17:30 work Work
  - 06:30-07:10 strength Heavy Bag
  - 07:15-08:15 laps Swim
  - not a block
  - 10:00-09:00 run Backwards

  ## Tuesday
  - 06:00-07:15 bike Ride In
  """

  describe "parse/1" do
    test "reads sleep and window as minutes past midnight" do
      week = Week.parse(@fixture)

      assert week.sleep == {21 * 60, 5 * 60 + 30}
      assert week.window == {5 * 60, 22 * 60}
    end

    test "without a window, the timed view spans the waking day" do
      week = @fixture |> String.replace("window: 05:00-22:00\n", "") |> Week.parse()
      assert week.window == {5 * 60 + 30, 21 * 60}
    end

    test "groups blocks under their day, sorted by start" do
      [monday, tuesday] = Week.parse(@fixture).days

      assert monday.slug == "monday"
      assert Enum.map(monday.blocks, & &1.label) == ["Heavy Bag", "Swim", "Work"]
      assert [%{start: 360, stop: 435, kind: :bike, label: "Ride In"}] = tuesday.blocks
    end

    test "an unknown kind becomes :other rather than dropping the block" do
      [monday | _] = Week.parse(@fixture).days
      assert Enum.find(monday.blocks, &(&1.label == "Swim")).kind == :other
    end

    test "skips lines that aren't blocks and blocks that end before they start" do
      [monday | _] = Week.parse(@fixture).days

      refute Enum.any?(monday.blocks, &(&1.label == "Backwards"))
      assert length(monday.blocks) == 3
    end

    test "formats spans as 12-hour clock times" do
      assert Week.span(%{start: 435, stop: 1050}) == "7:15–5:30"
      assert Week.clock(720) == "12:00"
    end
  end

  describe "load/0" do
    test "reads week.md from the vault" do
      assert {:ok, week} = Week.load()

      assert Enum.map(week.days, & &1.slug) ==
               ~w[sunday monday tuesday wednesday thursday friday saturday]

      assert Week.sleep_minutes(week) == 8 * 60

      tuesday = Enum.find(week.days, &(&1.slug == "tuesday"))
      assert %{start: 405, stop: 450, kind: :bike} = hd(tuesday.blocks)
    end

    test "is :error when the vault has no week.md" do
      tmp = Path.join(System.tmp_dir!(), "week_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      prev = Application.get_env(:web, :fitness_path)
      Application.put_env(:web, :fitness_path, tmp)

      try do
        assert Week.load() == :error
      after
        Application.put_env(:web, :fitness_path, prev)
        File.rm_rf!(tmp)
      end
    end
  end
end
