defmodule Web.Rides.AppleHealth.ExportTest do
  use ExUnit.Case, async: true

  alias Web.Rides.AppleHealth.Export

  # A ride on file: 20 September 2026, 07:00 to 08:00 Pacific.
  @ride %{started_at: ~U[2026-09-20 14:00:00Z], duration_s: 3600}

  # An export in the shape the Health app writes: a DTD, one element to a
  # line, records before workouts, timestamps in local time with an offset.
  # Every value is invented.
  defp export(body) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE HealthData [
    <!ELEMENT HealthData (ExportDate,Me,(Record|Workout|ActivitySummary)*)>
    <!ATTLIST Workout
      workoutActivityType   CDATA #REQUIRED
      startDate             CDATA #REQUIRED
    >
    ]>
    <HealthData locale="en_US">
     <ExportDate value="2026-10-04 21:10:11 -0700"/>
     <Me HKCharacteristicTypeIdentifierDateOfBirth="1990-01-01" HKCharacteristicTypeIdentifierBiologicalSex="HKBiologicalSexNotSet"/>
    #{body}
    </HealthData>
    """
  end

  defp heartbeat(time, bpm) do
    ~s( <Record type="HKQuantityTypeIdentifierHeartRate" sourceName="A Watch" sourceVersion="11.0" ) <>
      ~s(device="&lt;&lt;HKDevice: 0x1&gt;, name:Apple Watch&gt;" unit="count/min" ) <>
      ~s(creationDate="2026-09-20 09:00:00 -0700" startDate="#{time}" endDate="#{time}" value="#{bpm}">\n) <>
      ~s(  <MetadataEntry key="HKMetadataKeyHeartRateMotionContext" value="2"/>\n </Record>)
  end

  # The ride's own workout, as iOS 16 and later write one: its figures in
  # WorkoutStatistics children, and a route file the site must never open.
  @cycling """
   <Workout workoutActivityType="HKWorkoutActivityTypeCycling" duration="60.5" durationUnit="min" sourceName="Komoot" sourceVersion="2026.38" creationDate="2026-09-20 08:01:00 -0700" startDate="2026-09-20 07:00:20 -0700" endDate="2026-09-20 08:00:50 -0700">
    <MetadataEntry key="HKIndoorWorkout" value="0"/>
    <WorkoutEvent type="HKWorkoutEventTypePause" date="2026-09-20 07:30:00 -0700"/>
    <WorkoutStatistics type="HKQuantityTypeIdentifierHeartRate" startDate="2026-09-20 07:00:20 -0700" endDate="2026-09-20 08:00:50 -0700" average="141.6" minimum="88" maximum="171" unit="count/min"/>
    <WorkoutStatistics type="HKQuantityTypeIdentifierActiveEnergyBurned" startDate="2026-09-20 07:00:20 -0700" endDate="2026-09-20 08:00:50 -0700" sum="612.4" unit="Cal"/>
    <WorkoutStatistics type="HKQuantityTypeIdentifierBasalEnergyBurned" startDate="2026-09-20 07:00:20 -0700" endDate="2026-09-20 08:00:50 -0700" sum="95.1" unit="Cal"/>
    <WorkoutStatistics type="HKQuantityTypeIdentifierDistanceCycling" startDate="2026-09-20 07:00:20 -0700" endDate="2026-09-20 08:00:50 -0700" sum="17.2" unit="mi"/>
    <WorkoutRoute sourceName="A Watch" sourceVersion="11.0" creationDate="2026-09-20 08:01:00 -0700" startDate="2026-09-20 07:00:20 -0700" endDate="2026-09-20 08:00:50 -0700">
     <FileReference path="/workout-routes/route_2026-09-20_8.00am.gpx"/>
    </WorkoutRoute>
   </Workout>
  """

  # Nothing to do with any ride: a swim three days earlier.
  @swim """
   <Workout workoutActivityType="HKWorkoutActivityTypeSwimming" duration="30" durationUnit="min" sourceName="A Watch" startDate="2026-09-17 06:00:00 -0700" endDate="2026-09-17 06:30:00 -0700">
    <WorkoutStatistics type="HKQuantityTypeIdentifierHeartRate" startDate="2026-09-17 06:00:00 -0700" endDate="2026-09-17 06:30:00 -0700" average="120" minimum="90" maximum="150" unit="count/min"/>
   </Workout>
  """

  defp write!(name, contents) do
    dir = Path.join(System.tmp_dir!(), "health-export-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    path = Path.join(dir, name)
    File.write!(path, contents)
    path
  end

  defp zip!(members) do
    dir = Path.join(System.tmp_dir!(), "health-zip-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    path = Path.join(dir, "export.zip")

    {:ok, _} =
      :zip.create(
        String.to_charlist(path),
        for({name, contents} <- members, do: {String.to_charlist(name), contents})
      )

    path
  end

  describe "a workout that matches a ride" do
    setup do
      beats = [
        # The evening before, and an hour after: not this ride's.
        heartbeat("2026-09-19 22:00:00 -0700", 61),
        heartbeat("2026-09-20 07:00:20 -0700", 96),
        heartbeat("2026-09-20 07:10:20 -0700", 131),
        heartbeat("2026-09-20 07:30:20 -0700", 150),
        heartbeat("2026-09-20 08:00:20 -0700", 171),
        heartbeat("2026-09-20 09:30:00 -0700", 72)
      ]

      path = write!("export.xml", export(Enum.join(beats, "\n") <> "\n" <> @cycling <> @swim))
      {:ok, path: path}
    end

    test "is read with its heart rate, its energy and its times", %{path: path} do
      assert {:ok, %{workouts: [workout]}} = Export.read(path, [@ride])

      assert workout.activity == "Cycling"
      assert workout.started_at == ~U[2026-09-20 14:00:20Z]
      assert workout.ended_at == ~U[2026-09-20 15:00:50Z]
      assert workout.avg_hr == 142
      assert workout.max_hr == 171
      assert workout.min_hr == 88
      # Active energy, not the active and resting together.
      assert workout.active_kcal == 612
    end

    test "carries the heart rate over the ride, and only over the ride", %{path: path} do
      {:ok, %{workouts: [workout], heart_samples: kept}} = Export.read(path, [@ride])

      # Offsets from the workout's own start. The beats of the evening before
      # and of an hour after are not in it.
      assert workout.hr_trace == [0, 96, 600, 131, 1800, 150, 3600, 171]
      assert kept == 4
    end

    test "is the same workout from one export to the next", %{path: path} do
      {:ok, %{workouts: [first]}} = Export.read(path, [@ride])
      {:ok, %{workouts: [second]}} = Export.read(path, [@ride])

      assert first.hk_id == second.hk_id
      assert first.hk_id =~ "HKWorkoutActivityTypeCycling"
    end

    test "every workout in the file is counted, and only the matched one is kept",
         %{path: path} do
      assert {:ok, %{in_export: 2, workouts: [%{activity: "Cycling"}]}} =
               Export.read(path, [@ride])
    end

    # The whole point of matching: what the site is not shown, it does not keep.
    test "with no ride near it, nothing is kept at all", %{path: path} do
      elsewhere = %{started_at: ~U[2026-08-01 14:00:00Z], duration_s: 3600}

      assert {:ok, %{workouts: [], in_export: 2, heart_samples: 0}} =
               Export.read(path, [elsewhere])

      assert {:ok, %{workouts: [], in_export: 2}} = Export.read(path, [])
    end

    test "the pairing window is the caller's", %{path: path} do
      # The workout started twenty seconds after the ride.
      assert {:ok, %{workouts: [_]}} = Export.read(path, [@ride], 30)
      assert {:ok, %{workouts: []}} = Export.read(path, [@ride], 10)
    end
  end

  describe "older exports" do
    # Before iOS 16 a workout carried its energy as an attribute and its heart
    # rate nowhere but in the samples.
    test "take energy from the workout's own attributes and heart rate from the samples" do
      workout = """
       <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="60" durationUnit="min" totalDistance="6.1" totalDistanceUnit="mi" totalEnergyBurned="540" totalEnergyBurnedUnit="kcal" sourceName="A Watch" startDate="2026-09-20 07:00:00 -0700" endDate="2026-09-20 08:00:00 -0700"/>
      """

      beats =
        Enum.join(
          [
            heartbeat("2026-09-20 07:00:00 -0700", 100),
            heartbeat("2026-09-20 07:30:00 -0700", 160),
            heartbeat("2026-09-20 08:00:00 -0700", 130)
          ],
          "\n"
        )

      path = write!("export.xml", export(beats <> "\n" <> workout))
      assert {:ok, %{workouts: [run]}} = Export.read(path, [@ride])

      assert run.activity == "Running"
      assert run.active_kcal == 540
      assert run.avg_hr == 130
      assert run.max_hr == 160
      assert run.min_hr == 100
    end

    test "energy in kilojoules is converted" do
      workout = """
       <Workout workoutActivityType="HKWorkoutActivityTypeCycling" duration="60" durationUnit="min" totalEnergyBurned="2000" totalEnergyBurnedUnit="kJ" startDate="2026-09-20 07:00:00 -0700" endDate="2026-09-20 08:00:00 -0700"/>
      """

      path = write!("export.xml", export(workout))
      assert {:ok, %{workouts: [%{active_kcal: 478}]}} = Export.read(path, [@ride])
    end

    test "a workout with no heart rate anywhere is kept with none" do
      workout = """
       <Workout workoutActivityType="HKWorkoutActivityTypeHiking" duration="60" durationUnit="min" startDate="2026-09-20 07:00:00 -0700" endDate="2026-09-20 08:00:00 -0700"/>
      """

      path = write!("export.xml", export(workout))

      assert {:ok, %{workouts: [%{avg_hr: nil, max_hr: nil, active_kcal: nil, hr_trace: []}]}} =
               Export.read(path, [@ride])
    end
  end

  # Komoot's watch app has been seen to leave a workout's energy out. The
  # watch still logs active energy all day, so it is added up from that.
  describe "a workout that carries no energy of its own" do
    defp energy(from, to, kcal, source \\ "A Watch", unit \\ "Cal") do
      ~s( <Record type="HKQuantityTypeIdentifierActiveEnergyBurned" sourceName="#{source}" unit="#{unit}" ) <>
        ~s(creationDate="#{to}" startDate="#{from}" endDate="#{to}" value="#{kcal}"/>)
    end

    @bare """
     <Workout workoutActivityType="HKWorkoutActivityTypeCycling" duration="60" durationUnit="min" sourceName="Komoot" startDate="2026-09-20 07:00:00 -0700" endDate="2026-09-20 08:00:00 -0700">
      <WorkoutStatistics type="HKQuantityTypeIdentifierHeartRate" startDate="2026-09-20 07:00:00 -0700" endDate="2026-09-20 08:00:00 -0700" average="140" minimum="90" maximum="170" unit="count/min"/>
     </Workout>
    """

    defp read_with(records) do
      path = write!("export.xml", export(Enum.join(records, "\n") <> "\n" <> @bare))
      {:ok, %{workouts: [workout]}} = Export.read(path, [@ride])
      workout
    end

    test "gets it from the watch's samples inside the workout, and only inside" do
      workout =
        read_with([
          heartbeat("2026-09-20 07:10:00 -0700", 130),
          # Before it began, and after it ended.
          energy("2026-09-20 06:40:00 -0700", "2026-09-20 06:50:00 -0700", 40.0),
          energy("2026-09-20 07:00:00 -0700", "2026-09-20 07:20:00 -0700", 210.4),
          energy("2026-09-20 07:20:00 -0700", "2026-09-20 07:59:00 -0700", 390.2),
          energy("2026-09-20 08:05:00 -0700", "2026-09-20 08:15:00 -0700", 25.0)
        ])

      assert workout.active_kcal == 601
    end

    # The phone estimates the same minutes. Counting both would be double.
    test "counts one device: the one that measured the heart rate" do
      workout =
        read_with([
          heartbeat("2026-09-20 07:10:00 -0700", 130),
          heartbeat("2026-09-20 07:40:00 -0700", 150),
          energy("2026-09-20 07:00:00 -0700", "2026-09-20 07:59:00 -0700", 600.0, "A Watch"),
          energy("2026-09-20 07:00:00 -0700", "2026-09-20 07:59:00 -0700", 480.0, "A Phone")
        ])

      assert workout.active_kcal == 600
    end

    test "with no heart rate to go by, uses the only device there is, and none if there are two" do
      one = read_with([energy("2026-09-20 07:00:00 -0700", "2026-09-20 07:59:00 -0700", 300.0)])
      assert one.active_kcal == 300

      two =
        read_with([
          energy("2026-09-20 07:00:00 -0700", "2026-09-20 07:59:00 -0700", 300.0, "A Watch"),
          energy("2026-09-20 07:00:00 -0700", "2026-09-20 07:59:00 -0700", 250.0, "A Phone")
        ])

      assert two.active_kcal == nil
    end

    test "reads kilojoules, and leaves the figure out when the watch logged nothing" do
      kilojoules =
        read_with([
          energy(
            "2026-09-20 07:00:00 -0700",
            "2026-09-20 07:59:00 -0700",
            2000.0,
            "A Watch",
            "kJ"
          )
        ])

      assert kilojoules.active_kcal == 478
      assert read_with([]).active_kcal == nil
    end

    # A workout that says what it burned is believed over the sum.
    test "is not second-guessed when it does carry energy" do
      path =
        write!(
          "export.xml",
          export(
            energy("2026-09-20 07:00:20 -0700", "2026-09-20 08:00:00 -0700", 999.0) <>
              "\n" <> @cycling
          )
        )

      assert {:ok, %{workouts: [%{active_kcal: 612}]}} = Export.read(path, [@ride])
    end
  end

  test "names read as words: a type's capitals become spaces" do
    workout = """
     <Workout workoutActivityType="HKWorkoutActivityTypeTraditionalStrengthTraining" duration="60" durationUnit="min" startDate="2026-09-20 07:00:00 -0700" endDate="2026-09-20 08:00:00 -0700"/>
    """

    path = write!("export.xml", export(workout))

    assert {:ok, %{workouts: [%{activity: "Traditional Strength Training"}]}} =
             Export.read(path, [@ride])
  end

  # The zip is what the phone actually shares. It also holds the GPS route of
  # every workout, which the reader never opens.
  describe "the zip the Health app shares" do
    test "is read without being unpacked" do
      path =
        zip!([
          {"apple_health_export/export.xml", export(@cycling)},
          {"apple_health_export/export_cda.xml", "<ClinicalDocument/>"},
          {"apple_health_export/workout-routes/route_2026-09-20_8.00am.gpx", "<gpx>home</gpx>"}
        ])

      assert {:ok, %{workouts: [%{activity: "Cycling", avg_hr: 142}], in_export: 1}} =
               Export.read(path, [@ride])

      # Nothing was written beside it: the XML went through a pipe.
      assert File.ls!(Path.dirname(path)) == ["export.zip"]
    end

    test "is found by its contents, whatever the phone called it" do
      zipped = zip!([{"apple_health_export/export.xml", export(@cycling)}])
      renamed = Path.join(Path.dirname(zipped), "Health Data (2)")
      File.rename!(zipped, renamed)

      assert {:ok, %{workouts: [_]}} = Export.read(renamed, [@ride])
    end

    test "is read under whatever folder the phone's language gave it" do
      path = zip!([{"apple_health_export [de]/Export.xml", export(@cycling)}])
      assert {:ok, %{workouts: [_]}} = Export.read(path, [@ride])
    end

    test "with no export in it is said to have none" do
      path = zip!([{"holiday/photo.jpg", "jpeg"}])
      assert Export.read(path, [@ride]) == {:error, :no_export_in_zip}
    end

    test "that is torn is an error, not a crash" do
      path = zip!([{"apple_health_export/export.xml", export(@cycling)}])
      File.write!(path, binary_part(File.read!(path), 0, 60))

      assert {:error, _reason} = Export.read(path, [@ride])
    end
  end

  describe "a file that is not an export" do
    test "is refused: some other XML" do
      path = write!("feed.xml", ~s(<?xml version="1.0"?>\n<rss><channel/></rss>\n))
      assert Export.read(path, [@ride]) == {:error, :not_an_export}
    end

    test "is refused: an empty file, and a file that is not there" do
      assert Export.read(write!("export.xml", ""), [@ride]) == {:error, :not_an_export}
      assert {:error, :enoent} = Export.read("/nowhere/export.xml", [@ride])
    end

    # Apple writes one element to a line. Megabytes without a newline is some
    # other file, and reading on would mean holding all of it.
    test "is refused before it is swallowed: one endless line" do
      path = write!("export.xml", "<HealthData>" <> String.duplicate("x", 3_000_000))
      assert Export.read(path, [@ride]) == {:error, :not_an_export}
    end
  end

  test "a workout whose times cannot be read is counted and passed over" do
    workout = """
     <Workout workoutActivityType="HKWorkoutActivityTypeCycling" startDate="last Tuesday" endDate="2026-09-20 08:00:00 -0700"/>
    """

    path = write!("export.xml", export(workout <> @cycling))
    assert {:ok, %{in_export: 2, workouts: [%{activity: "Cycling"}]}} = Export.read(path, [@ride])
  end
end
