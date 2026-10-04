defmodule Web.Fitness.VaultTest do
  use ExUnit.Case, async: false

  alias Web.Fitness.Vault

  # The regimen page is public. get_day/1 must hand back the exercises and
  # nothing else — no schedule, no locations, no coaching notes.
  setup do
    tmp = Path.join(System.tmp_dir!(), "vault_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, "weekly"))
    File.mkdir_p!(Path.join(tmp, "modules"))

    File.write!(Path.join([tmp, "weekly", "tuesday.md"]), """
    ---
    title: Tuesday — Upper Body Routine
    description: Bias toward throwing arm health.
    tab: Tuesday
    modules: upper-body-power
    ---

    **Where:** Riverside Rec Center, after the bike commute in. Leave the house by **5:45 AM**.
    **Time:** ~80 min total

    The bike in is your warm-up and Zone 2 cardio.

    ## Picking your weights

    Treat every number below as a starting point.
    """)

    File.write!(Path.join([tmp, "modules", "upper-body-power.md"]), """
    ## Block 1 — Necessary (~60 min)

    The throwing-arm work. This part is non-negotiable.

    ### Warm-up — shoulder prep (~7 min)
    *You're warm from the ride, but your shoulders aren't.*

    - [ ] **[[band-pull-aparts|Band pull-aparts]]** — 2 × 20 (light band)
        - How-to: Hold the band at shoulder height and squeeze the shoulder blades.
        - Video: https://www.youtube.com/watch?v=WqdNDTTe-9g
    - [x] **[[pull-ups|Pull-ups]]** — 3 × 6–8
        - Rest: 90 sec

    > **🟢 GREEN — feels normal.**
    > Run the session exactly as written below.
    """)

    prev = Application.get_env(:web, :fitness_path)
    Application.put_env(:web, :fitness_path, tmp)

    on_exit(fn ->
      # Restore exactly what was there (config/test.exs points it at the
      # fixture vault): a lingering :fitness_path pointing at this (deleted)
      # tmp dir makes every later test that reads the vault fail, depending on
      # seed order.
      if prev,
        do: Application.put_env(:web, :fitness_path, prev),
        else: Application.delete_env(:web, :fitness_path)

      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  test "renders the exercises and their block headings" do
    assert {:ok, html} = Vault.get_day("tuesday")

    assert html =~ "Band pull-aparts"
    assert html =~ "2 × 20 (light band)"
    assert html =~ "Pull-ups"
    assert html =~ "Warm-up"

    # A parent block survives on the strength of its sub-sections.
    assert html =~ "Block 1"

    # Checkbox state survives the filter.
    assert html =~ ~s(<input type="checkbox">)
    assert html =~ ~s(<input type="checkbox" checked>)

    # Wiki links still resolve, so an exercise remains one tap from its how-to.
    assert html =~ "/fitness/wiki/band-pull-aparts"
  end

  test "drops schedule, location and coaching prose" do
    assert {:ok, html} = Vault.get_day("tuesday")

    refute html =~ "Riverside Rec Center"
    refute html =~ "5:45 AM"
    refute html =~ "bike commute"
    refute html =~ "Zone 2 cardio"
    refute html =~ "shoulders aren't"
    refute html =~ "GREEN"
    refute html =~ "starting point"
  end

  # "Picking your weights" is a heading over pure prose — with the prose gone
  # it would otherwise sit on the page labelling nothing.
  test "drops headings whose section has no exercises left" do
    assert {:ok, html} = Vault.get_day("tuesday")
    refute html =~ "Picking your weights"
  end

  test "drops the indented how-to, video and rest lines" do
    assert {:ok, html} = Vault.get_day("tuesday")

    refute html =~ "How-to:"
    refute html =~ "youtube.com"
    refute html =~ "Rest: 90 sec"
  end

  # Admin editing must still see the whole file, prose included.
  test "get_day_raw/1 is unfiltered" do
    assert {:ok, _meta, body} = Vault.get_day_raw("tuesday")
    assert body =~ "Riverside Rec Center"
    assert body =~ "5:45 AM"
  end

  describe "rotating day options" do
    setup %{tmp: tmp} do
      File.write!(Path.join([tmp, "modules", "swim.md"]), """
      ### Office Swim
      - [ ] **Open-water endurance**: 45 minutes continuous.
      """)

      File.write!(Path.join([tmp, "modules", "run.md"]), """
      ### Fartlek Run
      - [ ] **Fartlek block**: surges by feel.
      """)

      File.write!(Path.join([tmp, "modules", "extra.md"]), """
      ### Extra Strength
      - [ ] **Split squats**: 3 x 8.
      """)

      File.write!(Path.join([tmp, "weekly", "friday.md"]), """
      ---
      title: Friday — Swim or Run
      tab: Friday
      option_1: swim|Office Swim — Rec Pool
      option_2: run|Remote Fartlek Run
      ---

      **Where:** Downtown on office weeks.
      """)

      :ok
    end

    test "parses option_N into ordered options with labels" do
      assert {:ok, day} = Vault.get_day_with_options("friday", ~D[2026-01-01])

      assert Enum.map(day.options, & &1.label) == [
               "Office Swim — Rec Pool",
               "Remote Fartlek Run"
             ]

      assert Enum.map(day.options, & &1.key) == ["option_1", "option_2"]
    end

    test "each option is filtered independently, and the day's prose is still stripped" do
      assert {:ok, day} = Vault.get_day_with_options("friday", ~D[2026-01-01])
      [swim, run] = day.options

      assert swim.html =~ "Open-water endurance"
      refute swim.html =~ "Fartlek block"
      assert run.html =~ "Fartlek block"
      refute run.html =~ "Open-water endurance"
      refute day.html =~ "Downtown on office weeks"
    end

    test "exactly one option is active, and it follows the ISO week" do
      assert {:ok, wk1} = Vault.get_day_with_options("friday", ~D[2026-01-01])
      assert Enum.count(wk1.options, & &1.active?) == 1
      assert Enum.find(wk1.options, & &1.active?).key == "option_1"

      assert {:ok, wk2} = Vault.get_day_with_options("friday", ~D[2026-01-08])
      assert Enum.find(wk2.options, & &1.active?).key == "option_2"
    end

    test "an option can compose several modules", %{tmp: tmp} do
      File.write!(Path.join([tmp, "weekly", "saturday.md"]), """
      ---
      title: Saturday
      tab: Saturday
      option_1: run,extra|Week 1 — Run plus strength
      ---
      """)

      assert {:ok, day} = Vault.get_day_with_options("saturday", ~D[2026-01-01])
      [only] = day.options

      assert only.modules == ["run", "extra"]
      assert only.html =~ "Fartlek block"
      assert only.html =~ "Split squats"
    end

    test "a day with no options returns an empty list rather than nil" do
      assert {:ok, day} = Vault.get_day_with_options("tuesday", ~D[2026-01-01])
      assert day.options == []
      assert day.html =~ "Band pull-aparts"
    end

    test "an option whose modules are all missing is skipped, not rendered blank", %{tmp: tmp} do
      File.write!(Path.join([tmp, "weekly", "sunday.md"]), """
      ---
      title: Sunday
      tab: Sunday
      option_1: swim|Real
      option_2: does-not-exist|Phantom
      ---
      """)

      assert {:ok, day} = Vault.get_day_with_options("sunday", ~D[2026-01-01])
      assert Enum.map(day.options, & &1.label) == ["Real"]
    end
  end

  describe "update_day/2" do
    test "preserves frontmatter keys the edit form does not know about" do
      # It used to rebuild from title/description/tab alone, silently deleting
      # modules: — and would now delete option_N: with it.
      {:ok, meta_before, _body} = Vault.get_day_raw("tuesday")
      assert meta_before["modules"] == "upper-body-power"

      Vault.update_day("tuesday", %{
        "title" => "Tuesday — Renamed",
        "description" => "New description",
        "tab" => "Tuesday",
        "content" => "**Where:** Somewhere else."
      })

      {:ok, meta_after, body} = Vault.get_day_raw("tuesday")

      assert meta_after["modules"] == "upper-body-power"
      assert meta_after["title"] == "Tuesday — Renamed"
      assert body =~ "Somewhere else"
    end
  end

  # The regimen is joined up by name across three folders, and a name that
  # does not match fails without a sound.
  describe "audit/0" do
    test "finds the module a day names that is not there", %{tmp: tmp} do
      # The setup's tuesday lists upper-body-power; whether it exists is up
      # to the test.
      File.rm(Path.join([tmp, "modules", "upper-body-power.md"]))

      assert {"tuesday", "upper-body-power"} in Vault.audit().missing_modules
    end

    test "finds the module no day names, counting rotating options as use", %{tmp: tmp} do
      File.write!(Path.join([tmp, "weekly", "friday.md"]), """
      ---
      title: Friday
      tab: Friday
      option_1: swim-set, cooldown|Pool Swim
      option_2: tempo-run
      ---
      """)

      for module <- ~w(swim-set cooldown tempo-run forgotten) do
        File.write!(Path.join([tmp, "modules", module <> ".md"]), "- [ ] Something\n")
      end

      audit = Vault.audit()

      assert "forgotten" in audit.unused_modules
      refute Enum.any?(~w(swim-set cooldown tempo-run), &(&1 in audit.unused_modules))
      refute Enum.any?(audit.missing_modules, &(elem(&1, 0) == "friday"))
    end

    test "finds the day file the page's fixed order will never show", %{tmp: tmp} do
      File.write!(Path.join([tmp, "weekly", "someday.md"]), "---\ntitle: Someday\n---\n")

      assert Vault.audit().unlisted_days == ["someday"]
    end

    test "exercise_slugs/0 is every wiki entry, whatever group it is filed under", %{tmp: tmp} do
      File.mkdir_p!(Path.join([tmp, "exercise-wiki", "upper"]))
      File.mkdir_p!(Path.join([tmp, "exercise-wiki", "legs"]))
      File.write!(Path.join([tmp, "exercise-wiki", "upper", "push-ups.md"]), "Push.\n")
      File.write!(Path.join([tmp, "exercise-wiki", "legs", "squats.md"]), "Squat.\n")

      assert Vault.exercise_slugs() == MapSet.new(["push-ups", "squats"])
    end
  end
end
