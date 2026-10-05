defmodule Web.Rides.AppleHealth.Export do
  @moduledoc """
  Reads Apple Health's own export: the file the Health app makes from
  *your picture → Export All Health Data*, as the `export.zip` it shares or
  the `export.xml` inside it.

  That file is everything the phone knows about a body — every heartbeat
  sample, every night's sleep, every weigh-in, the GPS route of every
  workout — and it is routinely hundreds of megabytes. Two rules follow.

  **It is read in one pass and never held.** A zip is piped out of `unzip`
  and an XML file is streamed off disk; either way the reader sees one line
  at a time (Apple writes one element per line) and keeps two things from
  it: each `<Workout>` element, and each heart-rate `<Record>` that falls
  inside a window it was told to care about. Nothing is unpacked to disk,
  and memory holds the samples of the matched workouts and no more.

  **Only what the Activities pages show is taken.** `read/2` is given the
  rides on file and returns the workouts that started within the pairing
  window of one of them — its heart rate (average, peak, lowest, and the
  series), its active energy, when it ran and what it was. A workout that
  matches no ride is counted and dropped. Everything else in the file is
  never looked at: not the sleep, not the weight, and not the
  `workout-routes/`, which are whole GPS tracks that start at the front
  door. The map is Komoot's.

  The format is not a published schema, so it is read leniently: attributes
  are found by name wherever they sit in a tag, a workout takes its heart
  rate and energy from its `<WorkoutStatistics>` children (iOS 16 and
  later) or failing that from its own attributes and the samples themselves
  (earlier), and energy in kilojoules is converted.

  **Energy the workout does not carry is added up from the watch.** Not
  every app writes a workout's energy into it — Komoot's watch app has been
  seen to leave it out — but the watch logs active energy all day in samples
  of its own. For a workout with no energy on it, the samples that fall
  inside it are summed. Only those from the device that measured its heart
  rate: the phone keeps an estimate of its own for the same minutes, and
  adding both would count the outing twice.
  """

  alias Web.Rides.AppleHealth

  @heart_rate "HKQuantityTypeIdentifierHeartRate"
  @active_energy "HKQuantityTypeIdentifierActiveEnergyBurned"

  # Apple's lines are a few hundred bytes. Something with a "line" this long
  # is not that file, and reading on would mean holding it all in memory.
  @max_line 1_000_000

  @unix_epoch :calendar.datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}})

  @type ride :: %{started_at: DateTime.t(), duration_s: integer | nil}

  @doc """
  Reads the export at `path` against `rides` (anything with `started_at` and
  `duration_s`), pairing by `window_s` seconds between a ride's start and a
  workout's.

  Returns `{:ok, summary}`:

      %{workouts: [attrs],        # Web.Rides.Workout attributes, matched ones only
        in_export: integer,       # every workout the file holds
        heart_samples: integer}   # heart-rate samples kept for the matched ones

  or `{:error, reason}` — `:not_an_export` for a file that isn't one,
  `:no_export_in_zip` for a zip without the XML, `{:unzip, status}` when the
  archive cannot be read.
  """
  @spec read(Path.t(), [ride], pos_integer) :: {:ok, map} | {:error, term}
  def read(path, rides, window_s \\ 600) do
    starts = rides |> Enum.map(&DateTime.to_unix(&1.started_at)) |> Enum.sort()

    # Where a heartbeat is worth keeping: from the pairing window before a
    # ride starts to the same after it ends.
    windows =
      rides
      |> Enum.map(fn ride ->
        from = DateTime.to_unix(ride.started_at) - window_s
        {from, from + 2 * window_s + (ride.duration_s || 0)}
      end)
      |> Enum.sort()

    state = %{
      workouts: [],
      open: nil,
      samples: [],
      burns: [],
      in_export: 0,
      days: days(windows),
      windows: windows,
      seen_health_data: false
    }

    with {:ok, lines} <- lines(path) do
      state = Enum.reduce(lines, state, &line/2)

      if state.seen_health_data do
        matched = Enum.filter(state.workouts, &near?(&1.start, starts, window_s))
        samples = Enum.sort(state.samples)
        workouts = Enum.map(matched, &attrs(&1, samples, state.burns))

        {:ok,
         %{
           workouts: workouts,
           in_export: state.in_export,
           heart_samples: workouts |> Enum.map(&div(length(&1.hr_trace), 2)) |> Enum.sum()
         }}
      else
        {:error, :not_an_export}
      end
    end
  catch
    {:export, reason} -> {:error, reason}
  end

  # --- One line at a time ------------------------------------------------------

  defp line(line, state) do
    case :binary.match(line, "<") do
      {at, 1} -> element(binary_part(line, at + 1, byte_size(line) - at - 1), state)
      :nomatch -> state
    end
  end

  defp element("Record type=\"" <> @heart_rate <> "\"" <> rest, state), do: heartbeat(rest, state)
  defp element("Record type=\"" <> @active_energy <> "\"" <> rest, state), do: burn(rest, state)

  defp element("Workout " <> rest, state) do
    workout = %{
      type: attr(rest, "workoutActivityType"),
      start: time(attr(rest, "startDate")),
      finish: time(attr(rest, "endDate")),
      duration_s: duration(attr(rest, "duration"), attr(rest, "durationUnit")),
      energy: energy(attr(rest, "totalEnergyBurned"), attr(rest, "totalEnergyBurnedUnit")),
      avg: nil,
      max: nil,
      min: nil
    }

    state = %{state | in_export: state.in_export + 1}

    # A workout with nothing inside it closes on its own line.
    if String.ends_with?(String.trim_trailing(rest), "/>"),
      do: close(%{state | open: workout}),
      else: %{state | open: workout}
  end

  defp element("WorkoutStatistics " <> rest, %{open: %{} = workout} = state) do
    workout =
      case attr(rest, "type") do
        @heart_rate ->
          %{
            workout
            | avg: number(attr(rest, "average")),
              max: number(attr(rest, "maximum")),
              min: number(attr(rest, "minimum"))
          }

        @active_energy ->
          %{workout | energy: energy(attr(rest, "sum"), attr(rest, "unit")) || workout.energy}

        _other ->
          workout
      end

    %{state | open: workout}
  end

  defp element("/Workout>" <> _rest, state), do: close(state)
  defp element("HealthData" <> _rest, state), do: %{state | seen_health_data: true}
  defp element(_other, state), do: state

  # A workout without a readable start cannot be paired with anything.
  defp close(%{open: %{start: start} = workout} = state) when is_integer(start),
    do: %{state | open: nil, workouts: [workout | state.workouts]}

  defp close(state), do: %{state | open: nil}

  defp heartbeat(rest, state) do
    with at when is_integer(at) <- wanted(rest, state),
         bpm when is_number(bpm) <- number(attr(rest, "value")) do
      %{state | samples: [{at, bpm, attr(rest, "sourceName")} | state.samples]}
    else
      _ -> state
    end
  end

  # A stretch of active energy, as the watch logs it all day: so many
  # kilocalories between two instants, and which device said so.
  defp burn(rest, state) do
    with from when is_integer(from) <- wanted(rest, state),
         kcal when is_number(kcal) <- energy(attr(rest, "value"), attr(rest, "unit")) do
      to = time(attr(rest, "endDate")) || from
      %{state | burns: [{from, to, kcal, attr(rest, "sourceName")} | state.burns]}
    else
      _ -> state
    end
  end

  # When the record began, if that is inside a window worth keeping. The day
  # is checked as text before the time is parsed at all: a file holds millions
  # of records, and all but a few thousand are on days with no ride near them.
  defp wanted(rest, state) do
    with stamp when is_binary(stamp) <- attr(rest, "startDate"),
         true <- MapSet.member?(state.days, binary_part(stamp, 0, min(10, byte_size(stamp)))),
         at when is_integer(at) <- time(stamp),
         true <- Enum.any?(state.windows, fn {from, to} -> at >= from and at <= to end) do
      at
    else
      _ -> nil
    end
  end

  # --- What a matched workout becomes -------------------------------------------

  defp attrs(workout, samples, burns) do
    finish = workout.finish || workout.start + (workout.duration_s || 0)

    beats =
      Enum.filter(samples, fn {at, _bpm, _source} -> at >= workout.start and at <= finish end)

    during = for {at, bpm, _source} <- beats, do: {at - workout.start, bpm}
    rates = Enum.map(during, &elem(&1, 1))

    %{
      # The export carries no id for a workout. What it was and when it
      # started is one, and stays one from export to export.
      hk_id: "apple:#{workout.type}:#{workout.start}",
      activity: activity(workout.type),
      started_at: DateTime.from_unix!(workout.start),
      ended_at: DateTime.from_unix!(finish),
      active_kcal: rounded(workout.energy || burned(burns, workout.start, finish, beats)),
      avg_hr: rounded(workout.avg || mean(rates)),
      max_hr: rounded(workout.max || Enum.max(rates, fn -> nil end)),
      min_hr: rounded(workout.min || Enum.min(rates, fn -> nil end)),
      hr_trace: AppleHealth.trace_of(during)
    }
  end

  # The energy samples that fall inside the workout, from one device only: the
  # one that measured the heart rate, or with no heart rate to go by, the only
  # device that logged energy at all. Two devices and nothing to choose
  # between them by is nil, rather than a sum that might be double.
  defp burned(burns, start, finish, beats) do
    inside =
      Enum.filter(burns, fn {from, to, _kcal, _source} ->
        middle = div(from + to, 2)
        middle >= start and middle <= finish
      end)

    device =
      case {most_common(Enum.map(beats, &elem(&1, 2))), Enum.uniq(Enum.map(inside, &elem(&1, 3)))} do
        {nil, [only]} -> only
        {watch, _sources} -> watch
      end

    case for({_from, _to, kcal, source} <- inside, source == device, do: kcal) do
      [] -> nil
      _amounts when is_nil(device) -> nil
      amounts -> Enum.sum(amounts)
    end
  end

  defp most_common([]), do: nil

  defp most_common(sources) do
    sources |> Enum.frequencies() |> Enum.max_by(&elem(&1, 1)) |> elem(0)
  end

  # "HKWorkoutActivityTypeTraditionalStrengthTraining" → "Traditional Strength Training"
  defp activity("HKWorkoutActivityType" <> name) do
    name |> String.replace(~r/(?<=[a-z])(?=[A-Z])/, " ") |> String.trim()
  end

  defp activity(other), do: other

  defp near?(start, starts, window_s),
    do: Enum.any?(starts, &(abs(&1 - start) <= window_s))

  # Every calendar day a window touches, a day either side to spare, as the
  # text a timestamp begins with. The export writes local time with an offset
  # and the windows are UTC; the spare days cover any offset there is.
  defp days(windows) do
    for {from, to} <- windows,
        day <- Date.range(unix_date(from - 86_400), unix_date(to + 86_400)),
        into: MapSet.new(),
        do: Date.to_iso8601(day)
  end

  defp unix_date(unix), do: unix |> DateTime.from_unix!() |> DateTime.to_date()

  # --- Attributes ----------------------------------------------------------------

  # The value of `name="…"` wherever it sits in the tag. Matched with the
  # space before it, so `startDate` is never found inside `creationDate`.
  defp attr(tag, name) do
    needle = " " <> name <> "=\""

    case :binary.match(" " <> tag, needle) do
      {at, length} ->
        from = at + length - 1
        rest = binary_part(tag, from, byte_size(tag) - from)

        case :binary.match(rest, "\"") do
          {stop, 1} -> binary_part(rest, 0, stop)
          :nomatch -> nil
        end

      :nomatch ->
        nil
    end
  end

  # "2026-09-20 07:01:02 -0700" as Unix seconds. Read by position rather than
  # parsed: this runs once per heartbeat kept and twice per workout.
  defp time(
         <<y::binary-size(4), "-", mo::binary-size(2), "-", d::binary-size(2), " ",
           h::binary-size(2), ":", mi::binary-size(2), ":", s::binary-size(2), " ",
           sign::binary-size(1), oh::binary-size(2), om::binary-size(2), _rest::binary>>
       ) do
    with [y, mo, d, h, mi, s, oh, om] <- integers([y, mo, d, h, mi, s, oh, om]),
         true <- :calendar.valid_date(y, mo, d) and h < 24 and mi < 60 and s < 61 do
      offset = (oh * 3600 + om * 60) * if(sign == "-", do: -1, else: 1)

      :calendar.datetime_to_gregorian_seconds({{y, mo, d}, {h, mi, min(s, 59)}}) - @unix_epoch -
        offset
    else
      _ -> nil
    end
  end

  # Anything else Apple or a re-export might write.
  defp time(value) when is_binary(value) do
    case AppleHealth.parse_time(value) do
      %DateTime{} = at -> DateTime.to_unix(at)
      nil -> nil
    end
  end

  defp time(_value), do: nil

  defp integers(parts) do
    Enum.reduce_while(parts, [], fn part, acc ->
      case Integer.parse(part) do
        {integer, ""} -> {:cont, [integer | acc]}
        _ -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      reversed -> Enum.reverse(reversed)
    end
  end

  defp number(nil), do: nil

  defp number(text) do
    case Float.parse(text) do
      {value, _rest} -> value
      :error -> nil
    end
  end

  defp duration(value, unit) do
    case {number(value), unit} do
      {nil, _} -> nil
      {amount, "min"} -> round(amount * 60)
      {amount, "hr"} -> round(amount * 3600)
      {amount, "s"} -> round(amount)
      {amount, _} -> round(amount * 60)
    end
  end

  defp energy(value, unit) do
    case {number(value), unit && String.downcase(unit)} do
      {nil, _} -> nil
      {amount, kj} when kj in ["kj", "kilojoules"] -> amount * 0.239006
      {amount, _kcal} -> amount
    end
  end

  defp mean([]), do: nil
  defp mean(values), do: Enum.sum(values) / length(values)

  defp rounded(nil), do: nil
  defp rounded(value), do: round(value)

  # --- Getting at the lines --------------------------------------------------------

  # A zip is recognised by how it starts, not by what it is called: the
  # phone's share sheet does not always keep the name.
  defp lines(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 4)) do
      {:ok, <<"PK", _::binary>>} -> zipped(path)
      {:ok, head} when is_binary(head) -> {:ok, path |> File.stream!(65_536) |> split_lines()}
      {:ok, :eof} -> {:error, :not_an_export}
      {:error, reason} -> {:error, reason}
    end
  end

  # `unzip -p` writes one member to its output, which is read as it comes.
  # The XML is never written to disk: unpacked it can run to gigabytes.
  defp zipped(path) do
    with unzip when is_binary(unzip) <- System.find_executable("unzip"),
         {:ok, member} <- member(unzip, path) do
      {:ok, unzip |> piped(["-p", path, member]) |> split_lines()}
    else
      nil -> {:error, :unzip_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  # `export.xml`, under whatever folder the phone's language put it in. Not
  # `export_cda.xml`, the clinical-document twin that sits beside it.
  defp member(unzip, path) do
    case System.cmd(unzip, ["-Z1", path], stderr_to_stdout: true) do
      {listing, 0} ->
        names = String.split(listing, "\n", trim: true)

        case Enum.find(names, &(String.downcase(Path.basename(&1)) == "export.xml")) ||
               Enum.find(names, &(&1 =~ ~r/\.xml$/i and not (&1 =~ ~r/cda/i))) do
          nil -> {:error, :no_export_in_zip}
          # A member name is matched as a pattern by unzip; these are its wildcards.
          name -> {:ok, String.replace(name, ~r/([\[\]*?\\])/, "\\\\\\1")}
        end

      {_output, status} ->
        {:error, {:unzip, status}}
    end
  end

  defp piped(executable, args) do
    Stream.resource(
      fn -> Port.open({:spawn_executable, executable}, [:binary, :exit_status, args: args]) end,
      fn port ->
        receive do
          {^port, {:data, data}} -> {[data], port}
          {^port, {:exit_status, 0}} -> {:halt, port}
          {^port, {:exit_status, status}} -> throw({:export, {:unzip, status}})
        after
          120_000 -> throw({:export, :unzip_stalled})
        end
      end,
      fn port -> if Port.info(port), do: Port.close(port) end
    )
  end

  # Chunks in, whole lines out, with whatever is left of the last line carried
  # into the next chunk.
  defp split_lines(chunks) do
    Stream.transform(
      chunks,
      fn -> "" end,
      fn chunk, carry ->
        {lines, [rest]} = (carry <> chunk) |> String.split("\n") |> Enum.split(-1)
        if byte_size(rest) > @max_line, do: throw({:export, :not_an_export})
        {lines, rest}
      end,
      fn carry -> {[carry], ""} end,
      fn _carry -> :ok end
    )
  end
end
