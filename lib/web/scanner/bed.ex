defmodule Web.Scanner.Bed do
  @moduledoc """
  The flatbed: one process that owns the scanner, because there is one sheet
  of glass.

  A scan takes from ten seconds to several minutes. Run inside a LiveView
  callback it froze the page for that long, and a `scanimage` that hung froze
  it for good. So the scan is a `Port` this process holds: the caller is
  answered at once, progress arrives as messages, a reload of the page finds
  the scan still running, and a scan that outlives its timeout is killed.

  One scan at a time — a second request is refused with `:busy` rather than
  queued, since what is on the glass is whatever the person at the scanner
  put there for the first one.

  A scan is written beside its target as `.partial` and renamed only when
  `scanimage` exits 0, so a failed or killed scan never leaves a truncated
  TIFF sitting in a roll folder looking like a strip. A job that carries
  `resample: {from, to}` (dpi) is brought to that resolution before the
  rename, and a scan that can't be is a failed scan.

  Subscribers on `"scanner"` receive:

    * `{:scanner, :devices, devices}` — a fresh device listing
    * `{:scanner, :started, job}` — `job` is `%{kind: ..., target: ...}`
    * `{:scanner, :progress, percent}`
    * `{:scanner, :done, job}`
    * `{:scanner, :failed, job, reason}`
  """

  use GenServer
  require Logger

  alias Web.Negatives
  alias Web.Scanner.Driver

  @topic "scanner"

  # A frame at print resolution is the slow one; anything past this has hung.
  @scan_timeout_ms :timer.minutes(15)
  @list_timeout_ms 20_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  def subscribe, do: Phoenix.PubSub.subscribe(Web.PubSub, @topic)

  @doc """
  What the bed knows right now: `%{devices: [...] | nil, listing?: boolean,
  job: %{kind, target, percent} | nil}`. `devices` is nil until the first
  listing has come back.
  """
  def status(server \\ __MODULE__), do: GenServer.call(server, :status)

  @doc "Lists the SANE devices again. The answer arrives as a `:devices` message."
  def refresh(server \\ __MODULE__), do: GenServer.cast(server, :refresh)

  @doc """
  Starts a scan: `args` for `scanimage` (from `Web.Scanner.Driver`, built
  around the path `partial/1` gives for `job.target`), described by `job`.
  `:ok`, or `{:error, :busy}` while another scan is running.
  """
  def scan(server \\ __MODULE__, job, args) when is_map(job) and is_list(args) do
    GenServer.call(server, {:scan, job, args})
  end

  @doc "Where a scan for `target` is written until it finishes."
  def partial(target), do: target <> ".partial"

  # --- Server ---

  @impl true
  def init(opts) do
    state = %{
      devices: nil,
      listing: nil,
      job: nil,
      scan_timeout: Keyword.get(opts, :scan_timeout, @scan_timeout_ms)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    job = state.job && Map.take(state.job, [:kind, :target, :percent, :meta])
    {:reply, %{devices: state.devices, listing?: state.listing != nil, job: job}, state}
  end

  def handle_call({:scan, _job, _args}, _from, %{job: %{}} = state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call({:scan, job, args}, _from, state) do
    partial = partial(job.target)
    File.mkdir_p!(Path.dirname(job.target))
    File.rm(partial)

    case open(Driver.scanimage_bin(), args) do
      {:ok, port} ->
        timer = Process.send_after(self(), {:timeout, port}, state.scan_timeout)

        job =
          Map.merge(job, %{port: port, partial: partial, timer: timer, percent: 0, output: ""})

        broadcast({:scanner, :started, public(job)})
        {:reply, :ok, %{state | job: job}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast(:refresh, %{listing: nil} = state) do
    task =
      Task.Supervisor.async_nolink(Web.TaskSupervisor, fn ->
        case System.cmd(Driver.scanimage_bin(), Driver.list_args(), stderr_to_stdout: true) do
          {output, 0} -> Driver.parse_devices(output)
          {_output, _status} -> []
        end
      end)

    timer = Process.send_after(self(), {:list_timeout, task.ref}, @list_timeout_ms)
    {:noreply, %{state | listing: %{task: task, timer: timer}}}
  end

  # A listing is already on its way; its answer serves this request too.
  def handle_cast(:refresh, state), do: {:noreply, state}

  @impl true
  def handle_info({ref, devices}, %{listing: %{task: %{ref: ref}}} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, listed(state, devices)}
  end

  # No scanimage on this machine, or it crashed: that is "no devices".
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{listing: %{task: %{ref: ref}}} = state) do
    {:noreply, listed(state, [])}
  end

  def handle_info({:list_timeout, ref}, %{listing: %{task: %{ref: ref} = task}} = state) do
    Task.Supervisor.terminate_child(Web.TaskSupervisor, task.pid)
    Process.demonitor(ref, [:flush])
    Logger.warning("[scanner] listing devices took over #{@list_timeout_ms} ms; gave up")
    {:noreply, listed(state, state.devices || [])}
  end

  def handle_info({port, {:data, chunk}}, %{job: %{port: port} = job} = state) do
    job = %{job | output: keep_tail(job.output <> chunk)}

    job =
      case Driver.progress(chunk) do
        percent when is_integer(percent) and percent != job.percent ->
          broadcast({:scanner, :progress, percent})
          %{job | percent: percent}

        _ ->
          job
      end

    {:noreply, %{state | job: job}}
  end

  def handle_info({port, {:exit_status, status}}, %{job: %{port: port} = job} = state) do
    Process.cancel_timer(job.timer)

    cond do
      status != 0 ->
        fail(job, "scanimage exited #{status}: #{tail(job.output)}")

      not File.regular?(job.partial) or File.stat!(job.partial).size == 0 ->
        fail(job, "scanimage reported success but wrote nothing")

      true ->
        case resample(job) do
          :ok ->
            File.rename!(job.partial, job.target)
            broadcast({:scanner, :done, public(job)})

          {:error, reason} ->
            fail(job, reason)
        end
    end

    {:noreply, %{state | job: nil}}
  end

  def handle_info({:timeout, port}, %{job: %{port: port} = job} = state) do
    kill(port)
    fail(job, "the scan ran past its time limit and was stopped")
    {:noreply, %{state | job: nil}}
  end

  # A port or timer from a scan already given up on.
  def handle_info(_message, state), do: {:noreply, state}

  # A strip is a few megabytes, so this is done here rather than handed off:
  # the bed stays busy until the file is the one the roll expects.
  defp resample(%{resample: {from, to} = change, partial: partial}) when from != to do
    case System.cmd(Negatives.magick_bin(), Driver.resample_args(partial, change),
           stderr_to_stdout: true
         ) do
      {_output, 0} -> :ok
      {output, _status} -> {:error, "couldn't bring the scan to #{to} dpi: #{tail(output)}"}
    end
  rescue
    error -> {:error, "couldn't bring the scan to #{to} dpi: #{Exception.message(error)}"}
  end

  defp resample(_job), do: :ok

  defp listed(state, devices) do
    if state.listing, do: Process.cancel_timer(state.listing.timer)
    broadcast({:scanner, :devices, devices})
    %{state | devices: devices, listing: nil}
  end

  defp open(bin, args) do
    case System.find_executable(bin) do
      nil ->
        {:error, "scanimage is not installed (looked for #{bin})"}

      executable ->
        {:ok,
         Port.open({:spawn_executable, executable}, [
           :binary,
           :exit_status,
           :stderr_to_stdout,
           :hide,
           args: args
         ])}
    end
  end

  defp fail(job, reason) do
    File.rm(job.partial)
    Logger.warning("[scanner] #{job.kind} scan failed: #{reason}")
    broadcast({:scanner, :failed, public(job), reason})
  end

  # Closing a port only closes its pipes; scanimage would go on driving the
  # lamp carriage. The OS process has to be told.
  defp kill(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> System.cmd("kill", ["-TERM", "#{pid}"], stderr_to_stdout: true)
      _ -> :ok
    end

    if Port.info(port), do: Port.close(port)
  end

  defp public(job), do: Map.drop(job, [:port, :partial, :timer, :output, :percent])

  defp keep_tail(output) when byte_size(output) > 4_000,
    do: binary_part(output, byte_size(output) - 4_000, 4_000)

  defp keep_tail(output), do: output

  # scanimage redraws its progress line with carriage returns; the last
  # thing that isn't one of those is the reason it stopped.
  defp tail(output) do
    output
    |> String.split(["\n", "\r"], trim: true)
    |> Enum.reject(&String.starts_with?(&1, "Progress:"))
    |> Enum.take(-3)
    |> Enum.join(" — ")
    |> case do
      "" -> "no output"
      text -> text
    end
  end

  defp broadcast(message), do: Phoenix.PubSub.broadcast(Web.PubSub, @topic, message)
end
