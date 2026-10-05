defmodule Web.Rides.HealthImportTest do
  use Web.DataCase

  import Web.RidesFixtures

  alias Web.Rides
  alias Web.Rides.HealthImport

  @export """
  <?xml version="1.0" encoding="UTF-8"?>
  <HealthData locale="en_US">
   <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="A Watch" unit="count/min" startDate="2026-07-08 11:10:00 -0700" endDate="2026-07-08 11:10:00 -0700" value="131"/>
   <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="A Watch" unit="count/min" startDate="2026-07-08 11:40:00 -0700" endDate="2026-07-08 11:40:00 -0700" value="155"/>
   <Workout workoutActivityType="HKWorkoutActivityTypeCycling" duration="120" durationUnit="min" startDate="2026-07-08 11:00:20 -0700" endDate="2026-07-08 13:00:00 -0700">
    <WorkoutStatistics type="HKQuantityTypeIdentifierHeartRate" average="142" minimum="90" maximum="171" unit="count/min"/>
    <WorkoutStatistics type="HKQuantityTypeIdentifierActiveEnergyBurned" sum="612" unit="Cal"/>
   </Workout>
   <Workout workoutActivityType="HKWorkoutActivityTypeSwimming" duration="30" durationUnit="min" startDate="2026-07-01 06:00:00 -0700" endDate="2026-07-01 06:30:00 -0700"/>
  </HealthData>
  """

  setup do
    inbox = Path.join(System.tmp_dir!(), "health-inbox-#{System.unique_integer([:positive])}")
    Application.put_env(:web, :health_inbox_path, inbox)

    on_exit(fn ->
      File.rm_rf!(inbox)
      Application.delete_env(:web, :health_inbox_path)
    end)

    HealthImport.subscribe()
    {:ok, inbox: inbox}
  end

  # An export as the upload writer leaves it: in the inbox.
  defp uploaded!(contents) do
    path = HealthImport.reserve!()
    File.write!(path, contents)
    path
  end

  # The import runs in a supervised task, on the test's shared connection.
  # Wait for its record to stop saying "running" before looking at anything.
  defp import!(path) do
    :ok = HealthImport.start(path)
    await()
  end

  defp await do
    assert_receive :health_import, 5_000

    case HealthImport.last() do
      %{status: :running} -> await()
      done -> done
    end
  end

  describe "reserve!/0" do
    test "makes a file in an inbox only this user can read", %{inbox: inbox} do
      path = HealthImport.reserve!()

      assert Path.dirname(path) == inbox
      assert File.read!(path) == ""
      assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
      assert Bitwise.band(File.stat!(inbox).mode, 0o777) == 0o700
      assert HealthImport.reserve!() != path
    end

    # Everything under uploads/ is handed out by the proxy to anyone who
    # knows its name. This file must never be there.
    test "the inbox is beside the uploads root, never under it" do
      Application.delete_env(:web, :health_inbox_path)
      uploads = Path.expand(Web.Uploads.root())

      refute String.starts_with?(HealthImport.inbox(), uploads <> "/")
      assert Path.dirname(HealthImport.inbox()) == Path.dirname(uploads)
    end

    # An import cut short by a restart never reached the line that deletes
    # its file. The site empties the inbox when it boots.
    test "clear_inbox/0 removes whatever was left behind", %{inbox: inbox} do
      HealthImport.reserve!()
      HealthImport.reserve!()

      assert HealthImport.clear_inbox() == :ok
      assert File.ls!(inbox) == []
    end

    test "clear_inbox/0 does not mind an inbox that was never made" do
      assert HealthImport.clear_inbox() == :ok
    end
  end

  describe "an import" do
    test "stores the workout that matches a ride, and says what it found" do
      ride = ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z], duration_s: 7200})
      staged = uploaded!(@export)

      assert %{status: :ok, in_export: 2, matched: 1, heart_samples: 2, at: %DateTime{}} =
               import!(staged)

      assert %{avg_hr: 142, max_hr: 171, min_hr: 90, active_kcal: 612} =
               Rides.get_ride(ride.id).health

      # The swim matched nothing, and nothing of it was kept.
      assert Rides.count_workouts() == 1
    end

    test "deletes the export when it is done", %{inbox: inbox} do
      ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})
      staged = uploaded!(@export)

      import!(staged)

      refute File.exists?(staged)
      assert File.ls!(inbox) == []
    end

    @tag :capture_log
    test "deletes it when it could not be read, too, and says why", %{inbox: inbox} do
      staged = uploaded!("<rss><channel/></rss>\n")

      assert %{status: :failed, reason: reason} = import!(staged)
      assert reason =~ "not an Apple Health export"
      assert File.ls!(inbox) == []
    end

    test "is the same on a second run: nothing is stored twice" do
      ride = ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z], duration_s: 7200})

      import!(uploaded!(@export))
      import!(uploaded!(@export))

      assert Rides.count_workouts() == 1
      assert Rides.get_ride(ride.id).health.avg_hr == 142
    end
  end

  describe "the record of it" do
    test "is nil before there has ever been one" do
      assert HealthImport.last() == nil
      refute HealthImport.running?()
    end

    # The import is whichever process holds the module's name.
    test "one that is running refuses a second, and deletes the file it will not read" do
      Process.register(self(), HealthImport)
      staged = uploaded!(@export)

      assert HealthImport.running?()
      assert HealthImport.start(staged) == {:error, :running}
      refute File.exists?(staged)
      assert HealthImport.last() == nil
    end

    # The task died with the release it was running in. What it wrote must
    # not block imports for ever, nor claim to be still reading.
    test "one left saying it is running, with nothing running, is read as a failure" do
      Web.SiteSettings.put_setting(
        "health_import",
        Jason.encode!(%{"status" => "running", "at" => DateTime.to_iso8601(DateTime.utc_now())})
      )

      refute HealthImport.running?()

      assert %{status: :failed, reason: "it was interrupted before it finished"} =
               HealthImport.last()

      ride_fixture(%{started_at: ~U[2026-07-08 18:00:00Z]})
      assert %{status: :ok, matched: 1} = import!(uploaded!(@export))
    end
  end
end
