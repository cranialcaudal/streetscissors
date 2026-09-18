defmodule Web.Media.Transcoder do
  @moduledoc """
  A serial queue of ffmpeg jobs, one captain's log at a time.

  Concurrency is deliberately one. There are twelve cores to encode on, but
  this laptop is also the web server, and a single `nice`-d job leaves the
  site responsive in a way that two concurrent 720p encodes would not.

  The GenServer owns the ffmpeg port directly rather than handing it to a
  task: a port is asynchronous, so the process stays responsive to new work
  while an encode runs, and `-progress pipe:1` arrives as ordinary messages
  it can throttle and rebroadcast. The short steps — poster, waveform — are
  run synchronously, because half a second of blocking on a queue that is
  serial anyway buys nothing to avoid.

  ## Durability without a job table

  Oban is available here and would do the queueing, but it is a poor fit for
  this particular job on two counts. Its workers would sit for minutes in a
  receive loop shepherding a port, which is the code below either way; and its
  retries are actively wrong here, because the common failure is a source file
  ffmpeg cannot read, and re-encoding that twenty times just burns the laptop.

  So durability comes from the row instead. Every input the encode needs —
  `source_path`, the trim, the poster timestamp — is a column, and on boot
  every log still sitting at `pending` or `processing` is queued again. A
  restart mid-encode resumes rather than stranding an entry, and a retry is
  the admin pressing a button once.

  ## Progress

  Subscribers on `"log:<id>"` receive:

    * `{:transcode_progress, id, percent}` — at most once a second
    * `{:transcode_done, id, :ready | :failed}`
  """

  use GenServer
  require Logger

  alias Web.Audio
  alias Web.Media
  alias Web.Media.FFmpeg
  alias Web.Uploads

  @broadcast_interval_ms 1_000

  # --- Public API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Queues a log for transcoding. Returns immediately."
  def enqueue(server \\ __MODULE__, log_id) when is_integer(log_id) do
    GenServer.cast(server, {:enqueue, log_id})
  end

  @doc "What the queue is doing right now — `%{current: id | nil, queued: [id]}`."
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @doc "Blocks until the queue has drained. For tests and for the console."
  def await_idle(server \\ __MODULE__, timeout \\ 120_000) do
    GenServer.call(server, :await_idle, timeout)
  end

  @doc "Subscribe to one log's transcode progress."
  def subscribe(log_id), do: Phoenix.PubSub.subscribe(Web.PubSub, topic(log_id))

  def topic(log_id), do: "log:#{log_id}"

  # --- Server ---

  @impl true
  def init(opts) do
    state = %{
      queue: :queue.new(),
      current: nil,
      waiting: []
    }

    if Keyword.get(opts, :requeue_on_boot, requeue_on_boot?()) do
      {:ok, state, {:continue, :requeue}}
    else
      {:ok, state}
    end
  end

  defp requeue_on_boot?, do: Application.get_env(:web, :transcoder_requeue_on_boot, true)

  @impl true
  def handle_continue(:requeue, state) do
    {:noreply, requeue_unfinished(state)}
  end

  @doc false
  def requeue_unfinished(state) do
    case Audio.list_unfinished_logs() do
      [] ->
        state

      logs ->
        Logger.info("[transcoder] resuming #{length(logs)} unfinished log(s) after boot")
        Enum.reduce(logs, state, fn log, acc -> push(acc, log.id) end)
    end
  rescue
    # A boot where the database is not reachable should not take the
    # supervision tree down with it; the next enqueue still works.
    error ->
      Logger.warning("[transcoder] could not requeue on boot: #{Exception.message(error)}")
      state
  end

  @impl true
  def handle_cast({:enqueue, log_id}, state) do
    {:noreply, push(state, log_id)}
  end

  @impl true
  def handle_call(:status, _from, state) do
    reply = %{
      current: state.current && state.current.log_id,
      queued: :queue.to_list(state.queue)
    }

    {:reply, reply, state}
  end

  def handle_call(:await_idle, from, state) do
    if idle?(state) do
      {:reply, :ok, state}
    else
      {:noreply, %{state | waiting: [from | state.waiting]}}
    end
  end

  @impl true
  def handle_info({port, {:data, chunk}}, %{current: %{port: port}} = state) do
    {:noreply, %{state | current: absorb(state.current, chunk)}}
  end

  def handle_info({port, {:exit_status, status}}, %{current: %{port: port}} = state) do
    {:noreply, state |> finish(status) |> run_next()}
  end

  # A port from a job we already gave up on, or noise from elsewhere.
  def handle_info(_message, state), do: {:noreply, state}

  # --- Queue mechanics ---

  defp push(state, log_id) do
    if state.current && state.current.log_id == log_id do
      state
    else
      %{state | queue: :queue.in(log_id, state.queue)} |> run_next()
    end
  end

  defp run_next(%{current: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, log_id}, rest} ->
        case start_job(log_id) do
          {:ok, job} ->
            %{state | queue: rest, current: job}

          :skip ->
            run_next(%{state | queue: rest})
        end

      {:empty, _} ->
        notify_idle(%{state | current: nil})
    end
  end

  defp run_next(state), do: state

  defp idle?(state), do: is_nil(state.current) and :queue.is_empty(state.queue)

  defp notify_idle(state) do
    Enum.each(state.waiting, &GenServer.reply(&1, :ok))
    %{state | waiting: []}
  end

  # --- One job ---

  defp start_job(log_id) do
    with %Web.Audio.Log{} = log <- Audio.get_log(log_id),
         {:ok, log} <- Audio.mark_processing(log),
         {:ok, source} <- source_for(log),
         {:ok, probe} <- FFmpeg.probe(source) do
      media_dir = Uploads.new_media_dir(log.slug)
      Uploads.create_entry_dir!(media_dir)

      # What this entry *actually* becomes, decided once from the source
      # rather than taken on trust from the form. A clip uploaded as video
      # whose file carries no video track is an audio entry, and the row is
      # corrected to say so when it finishes — otherwise `media_url/1` would
      # point at a master playlist that was never written.
      kind = if log.kind == "video" and probe.has_video?, do: "video", else: "audio"

      args = args_for(kind, log, source, media_dir, probe)
      {executable, argv} = FFmpeg.command(args)

      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          :hide,
          args: argv
        ])

      {:ok,
       %{
         log_id: log.id,
         log: log,
         kind: kind,
         port: port,
         source: source,
         media_dir: media_dir,
         probe: probe,
         expected: expected_seconds(log, probe),
         buffer: "",
         output: "",
         last_percent: -1,
         # Monotonic time starts at an arbitrary point and is usually
         # *negative* at VM start, so this cannot be zero: `now - 0` would
         # then be less than the interval for the whole run and no progress
         # would ever be sent. Start one interval in the past, which also
         # makes the first tick immediate.
         last_broadcast: System.monotonic_time(:millisecond) - @broadcast_interval_ms
       }}
    else
      nil ->
        # The log was deleted between enqueue and dequeue.
        :skip

      {:error, reason} ->
        fail(log_id, reason)
        :skip
    end
  rescue
    error ->
      fail(log_id, Exception.message(error))
      :skip
  end

  defp source_for(%{source_path: path}) when is_binary(path) do
    if File.regular?(path), do: {:ok, path}, else: {:error, "source file is gone: #{path}"}
  end

  defp source_for(_log), do: {:error, "log has no source to transcode"}

  defp args_for(kind, log, source, media_dir, probe) do
    dir = Uploads.entry_dir!(media_dir)

    opts = [
      trim_start: ms_to_s(log.trim_start_ms),
      trim_duration: ms_to_s(log.trim_duration_ms)
    ]

    case kind do
      "video" ->
        FFmpeg.ladder_args(
          source,
          dir,
          opts ++ [rungs: FFmpeg.rungs(probe.height), audio?: probe.has_audio?]
        )

      _ ->
        FFmpeg.audio_args(source, dir, opts)
    end
  end

  defp ms_to_s(nil), do: nil
  defp ms_to_s(ms) when is_integer(ms), do: ms / 1000

  # How long the *output* will be, which is what progress is measured against:
  # a trimmed encode reports out_time from zero, not from the trim point.
  defp expected_seconds(log, probe) do
    cond do
      is_integer(log.trim_duration_ms) -> log.trim_duration_ms / 1000
      is_number(probe.duration) -> probe.duration - (ms_to_s(log.trim_start_ms) || 0)
      true -> nil
    end
  end

  # --- Progress ---

  defp absorb(job, chunk) do
    job = %{job | output: keep_tail(job.output <> chunk)}
    {lines, rest} = split_lines(job.buffer <> chunk)
    job = %{job | buffer: rest}

    Enum.reduce(lines, job, &progress_line/2)
  end

  defp split_lines(buffer) do
    case String.split(buffer, "\n") do
      [] -> {[], ""}
      parts -> {Enum.drop(parts, -1), List.last(parts)}
    end
  end

  defp progress_line("out_time_us=" <> value, job), do: maybe_broadcast(job, value)
  defp progress_line(_line, job), do: job

  defp maybe_broadcast(%{expected: expected} = job, value)
       when is_number(expected) and expected > 0 do
    with {microseconds, _} <- Integer.parse(String.trim(value)) do
      percent =
        (microseconds / 1_000_000 / expected * 100)
        |> min(99.0)
        |> max(0.0)
        |> round()

      now = System.monotonic_time(:millisecond)

      if percent != job.last_percent and now - job.last_broadcast >= @broadcast_interval_ms do
        broadcast(job.log_id, {:transcode_progress, job.log_id, percent})
        %{job | last_percent: percent, last_broadcast: now}
      else
        job
      end
    else
      _ -> job
    end
  end

  defp maybe_broadcast(job, _value), do: job

  # ffmpeg's own diagnostics are the only useful thing in a failure message,
  # and only the end of them — so the buffer is bounded rather than unbounded.
  defp keep_tail(output) when byte_size(output) > 8_000,
    do: binary_part(output, byte_size(output) - 8_000, 8_000)

  defp keep_tail(output), do: output

  # --- Completion ---

  defp finish(%{current: job} = state, 0) do
    case complete(job) do
      {:ok, _log} ->
        Uploads.discard_staged(job.source)
        broadcast(job.log_id, {:transcode_done, job.log_id, :ready})

      {:error, reason} ->
        Uploads.destroy_entry(job.media_dir)
        fail(job.log_id, reason)
    end

    %{state | current: nil}
  end

  defp finish(%{current: job} = state, status) do
    Uploads.destroy_entry(job.media_dir)
    fail(job.log_id, "ffmpeg exited #{status}\n#{FFmpeg.tail(job.output)}")
    %{state | current: nil}
  end

  defp complete(job) do
    dir = Uploads.entry_dir!(job.media_dir)

    with :ok <- verify_output(job, dir),
         {:ok, poster} <- make_poster(job, dir),
         {:ok, log} <- Audio.get_log(job.log_id) |> mark_ready(job, poster, dir) do
      {:ok, log}
    end
  end

  defp verify_output(job, dir) do
    expected =
      if job.kind == "video",
        do: Media.master_playlist(),
        else: Media.audio_rendition()

    if File.regular?(Path.join(dir, expected)),
      do: :ok,
      else: {:error, "ffmpeg reported success but wrote no #{expected}"}
  end

  # A video shows a frame of itself; audio shows its own waveform, which is
  # the only picture a recording of a voice can honestly offer.
  defp make_poster(%{kind: "video"} = job, dir) do
    output = Path.join(dir, Media.poster())
    input = Path.join(dir, Media.variant_playlist(0))
    at = poster_timestamp(job)

    case FFmpeg.run(FFmpeg.poster_args(input, output, at)) do
      :ok ->
        {:ok, File.regular?(output)}

      # A poster is worth having, not worth failing an encode over.
      {:error, reason} ->
        Logger.warning("[transcoder] poster failed: #{reason}")
        {:ok, false}
    end
  end

  defp make_poster(_job, dir) do
    output = Path.join(dir, Media.poster())
    input = Path.join(dir, Media.audio_rendition())

    case FFmpeg.run(FFmpeg.waveform_args(input, output)) do
      :ok ->
        {:ok, File.regular?(output)}

      {:error, reason} ->
        Logger.warning("[transcoder] waveform failed: #{reason}")
        {:ok, false}
    end
  end

  defp poster_timestamp(%{log: %{poster_at_ms: ms}}) when is_integer(ms), do: ms / 1000

  # Ten percent in: far enough past a fade or a lens finding focus to show
  # something, early enough to still be the opening shot.
  defp poster_timestamp(%{expected: expected}) when is_number(expected), do: expected * 0.1
  defp poster_timestamp(_job), do: 0

  defp mark_ready(nil, _job, _poster, _dir), do: {:error, "log vanished mid-transcode"}

  defp mark_ready(log, job, poster?, dir) do
    # Measured off what was actually written rather than what was asked for: a
    # trim lands on a keyframe boundary, a source can be shorter than its
    # header claims, and the top rung is smaller than the source it came from.
    output = probe_output(job, dir)

    attrs =
      %{
        kind: job.kind,
        media_dir: job.media_dir,
        source_path: nil,
        size_bytes: directory_size(dir),
        duration: duration_of(output, job)
      }
      |> put_poster(job.media_dir, poster?)
      |> put_dimensions(output, job.probe)

    Audio.mark_ready(log, attrs)
  end

  defp put_poster(attrs, media_dir, true),
    do: Map.put(attrs, :poster_path, Uploads.entry_web_path(media_dir, Media.poster()))

  defp put_poster(attrs, _media_dir, false), do: attrs

  # The rendition's own size, falling back to the source's only if the output
  # could not be probed — an audio entry has no dimensions either way.
  defp put_dimensions(attrs, %{width: w, height: h}, _source)
       when is_integer(w) and is_integer(h),
       do: Map.merge(attrs, %{width: w, height: h})

  defp put_dimensions(attrs, _output, %{width: w, height: h})
       when is_integer(w) and is_integer(h),
       do: Map.merge(attrs, %{width: w, height: h})

  defp put_dimensions(attrs, _output, _source), do: attrs

  defp probe_output(job, dir) do
    target =
      if job.kind == "video",
        do: Media.variant_playlist(0),
        else: Media.audio_rendition()

    case FFmpeg.probe(Path.join(dir, target)) do
      {:ok, probe} -> probe
      _ -> %{}
    end
  end

  defp duration_of(%{duration: seconds}, _job) when is_number(seconds), do: round(seconds)
  defp duration_of(_output, %{expected: expected}) when is_number(expected), do: round(expected)
  defp duration_of(_output, _job), do: nil

  defp directory_size(dir) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.reduce(0, fn path, total ->
      case File.stat(path) do
        {:ok, %{type: :regular, size: size}} -> total + size
        _ -> total
      end
    end)
  end

  defp fail(log_id, reason) do
    reason = if is_binary(reason), do: reason, else: inspect(reason)
    Logger.error("[transcoder] log #{log_id} failed: #{reason}")

    case Audio.get_log(log_id) do
      nil -> :ok
      log -> Audio.mark_failed(log, reason)
    end

    broadcast(log_id, {:transcode_done, log_id, :failed})
  end

  defp broadcast(log_id, message) do
    Phoenix.PubSub.broadcast(Web.PubSub, topic(log_id), message)
  end
end
