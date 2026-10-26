defmodule Web.Rides.PowerTest do
  use WebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Web.RidesFixtures

  alias Web.Rides.Power

  setup do
    File.rm(Power.path())

    on_exit(fn ->
      File.rm(Power.path())
      System.delete_env("STUB_RSCRIPT_RIDE")
      System.delete_env("STUB_RSCRIPT_FAIL")
    end)

    :ok
  end

  test "R's estimates are read for each ride, and a ride it did not estimate has none" do
    ride = ride_fixture(%{name: "River loop"})
    other = ride_fixture(%{name: "Run", komoot_id: "777", sport: "jogging"})
    System.put_env("STUB_RSCRIPT_RIDE", to_string(ride.id))

    assert {:ok, 1} = Power.run()
    assert %{"avg_w" => 182.4, "work_kj" => 1243.6, "basis" => "profile"} = Power.for_ride(ride)
    assert Power.for_ride(other) == nil
    assert Power.model()["not_counted"] == ["wind", "drafting"]
  end

  test "a failed run says why and keeps the estimates it had" do
    ride = ride_fixture()
    System.put_env("STUB_RSCRIPT_RIDE", to_string(ride.id))
    {:ok, _} = Power.run()

    System.put_env("STUB_RSCRIPT_FAIL", "1")
    assert {:error, {:rscript, 1, said}} = Power.run()
    assert said =~ "could not open the database"
    assert Power.for_ride(ride)["avg_w"] == 182.4
  end

  test "with no estimates at all nothing is shown" do
    assert Power.for_ride(ride_fixture()) == nil
  end

  test "a ride's page shows its estimated power, marked as an estimate", %{conn: conn} do
    ride = ride_fixture(%{name: "River loop"})
    {:ok, view, _html} = live(conn, ~p"/fitness/rides/#{ride.id}")
    refute has_element?(view, ".activity-power")

    System.put_env("STUB_RSCRIPT_RIDE", to_string(ride.id))
    {:ok, _} = Power.run()
    {:ok, view, _html} = live(conn, ~p"/fitness/rides/#{ride.id}")

    assert has_element?(view, ".activity-power", "Power, estimated")
    assert has_element?(view, ".activity-power .activity-figure-value", "≈ 180 W")
    assert has_element?(view, ".activity-power .activity-figure-value", "≈ 1,240 kJ")
    assert has_element?(view, ".activity-power", "No power meter")
  end

  # The R script's own check of its arithmetic, when R is here to run it.
  if System.find_executable("Rscript") do
    @tag :external
    test "the model's arithmetic holds" do
      script = Path.expand("analysis/ride_power.R")
      assert {said, 0} = System.cmd("Rscript", [script, "--self-test"], stderr_to_stdout: true)
      assert said =~ "flat, 9 m/s, 72 kg"
      refute said =~ "expected"
    end
  end
end
