defmodule Web.Darkroom.Session do
  @moduledoc """
  One editor's LightCraft: a `lightcraft-cli mcp` held open over stdio for as
  long as the editor is, so a slider moved is a new picture in about 65 ms
  (the first, which reads the print, about 300 ms) rather than a program
  started each time, which takes a quarter of a second before it does anything.

  The protocol is MCP's JSON-RPC, one message to a line. Every edit goes
  through its `run_command` tool with the same commands `Web.Darkroom.commands/1`
  gives the print, then `app.export` writes a JPEG.

  **Only the newest preview is made.** A slider being dragged asks far faster
  than pictures are made, so before each render the mailbox is emptied of
  waiting requests and only the last is drawn. Each finished picture goes to
  the owner as `{:darkroom_preview, n, file}`, a failure as
  `{:darkroom_error, n, text}`.

  The pictures are written to a folder of the session's own (0700, under the
  system tmp dir), named by a random token; `WebWeb.DarkroomController` serves
  them by that token to the admin alone. The session monitors its owner and
  ends with it, taking the program and the folder along.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Web.Darkroom

  @timeout 30_000

  @doc """
  Opens LightCraft on `path` for the calling process. `{:ok, pid, info}` with
  the token its pictures are served by and the engine's slider schema, or
  `{:error, text}`.
  """
  def start(path) do
    owner = self()

    case DynamicSupervisor.start_child(Web.Darkroom.Sessions, {__MODULE__, {path, owner}}) do
      {:ok, pid} -> {:ok, pid, GenServer.call(pid, :info)}
      {:error, {:shutdown, reason}} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  def start_link({path, owner}), do: GenServer.start_link(__MODULE__, {path, owner})

  @doc """
  The dust LightCraft finds on the picture (`spot.findDust`: small dark spots
  on smooth ground), as spots for a recipe, without healing them yet.
  """
  def find_dust(pid, sensitivity), do: GenServer.call(pid, {:find_dust, sensitivity}, @timeout)

  @doc "Asks for picture `n` of `recipe`; it arrives as a message."
  def preview(pid, recipe, n), do: GenServer.cast(pid, {:preview, recipe, n})

  def stop(pid), do: GenServer.stop(pid, :normal)

  @doc "The folder a session's pictures are in, by its token."
  def dir(token) when is_binary(token) do
    if Regex.match?(~r/\A[a-f0-9]{32}\z/, token),
      do: {:ok, Path.join(scratch(), token)},
      else: :error
  end

  def dir(_), do: :error

  # This machine is the server and the workbench: the suite and a development
  # server each keep their own folder, so neither clears the live site's.
  defp scratch do
    Path.join(
      System.tmp_dir!(),
      Application.get_env(:web, :darkroom_scratch, "streetscissors-darkroom")
    )
  end

  @doc "Removes the folders sessions left when the site last stopped. Run at boot."
  def clear_scratch do
    File.rm_rf(scratch())
    :ok
  end

  # ── The server ────────────────────────────────────────────────────────

  @impl true
  def init({path, owner}) do
    Process.flag(:trap_exit, true)
    token = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    {:ok, dir} = dir(token)
    root = Path.dirname(dir)
    File.mkdir_p!(root)
    File.chmod!(root, 0o700)
    File.mkdir_p!(dir)
    File.chmod!(dir, 0o700)

    state = %{
      owner: owner,
      token: token,
      dir: dir,
      port: nil,
      schema: [],
      shown: [],
      size: Darkroom.dimensions(path)
    }

    case open(state, path) do
      {:ok, state} ->
        Process.monitor(owner)
        {:ok, state}

      {:error, reason, state} ->
        close(state)
        {:stop, {:shutdown, reason}}
    end
  end

  defp open(state, path) do
    case System.find_executable(Darkroom.bin()) do
      nil ->
        {:error, "lightcraft-cli is not installed, or not on the server's PATH", state}

      exe ->
        port =
          Port.open({:spawn_executable, exe}, [
            :binary,
            :exit_status,
            :use_stdio,
            {:line, 4_194_304},
            args: ["mcp", "--compact", path]
          ])

        state = %{state | port: port}

        with {:ok, _} <- rpc(state, "initialize", handshake()),
             :ok <- tell(state, "notifications/initialized"),
             {:ok, text} <- command(state, "develop.controls", %{}),
             {:ok, schema} when is_list(schema) <- Jason.decode(text),
             {:ok, _} <- command(state, "app.export", export_params(state, "before.jpg")) do
          {:ok, %{state | schema: schema}}
        else
          {:error, reason} -> {:error, to_string(reason), state}
          _ -> {:error, "lightcraft-cli gave no slider schema", state}
        end
    end
  end

  defp handshake do
    %{
      "protocolVersion" => "2025-06-18",
      "capabilities" => %{},
      "clientInfo" => %{"name" => "streetscissors", "version" => "1"}
    }
  end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply, %{token: state.token, schema: state.schema, before: "before.jpg"}, state}
  end

  def handle_call({:find_dust, sensitivity}, _from, state) do
    reply =
      with {:ok, _} <- command(state, "develop.reset", %{}),
           {:ok, text} <-
             command(state, "spot.findDust", %{"sensitivity" => sensitivity, "add" => false}),
           {:ok, %{"spots" => spots}} <- Jason.decode(text) do
        {:ok, Darkroom.clean_spots(spots)}
      else
        {:error, reason} -> {:error, reason}
        _ -> {:error, "LightCraft gave no spots"}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:preview, recipe, n}, state) do
    {recipe, n} = newest(recipe, n)
    file = "p-#{n}.jpg"
    steps = Darkroom.commands(recipe, state.size) ++ [{"app.export", export_params(state, file)}]

    result =
      Enum.reduce_while(steps, :ok, fn {name, params}, :ok ->
        case command(state, name, params) do
          {:ok, _} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      :ok ->
        send(state.owner, {:darkroom_preview, n, file})
        {:noreply, forget_old(state, file)}

      {:error, reason} ->
        send(state.owner, {:darkroom_error, n, reason})
        if Port.info(state.port), do: {:noreply, state}, else: {:stop, :normal, state}
    end
  end

  # The requests that came in while the last picture was being made: only the
  # newest is worth drawing.
  defp newest(recipe, n) do
    receive do
      {:"$gen_cast", {:preview, recipe, n}} -> newest(recipe, n)
    after
      0 -> {recipe, n}
    end
  end

  # The page may still be loading the picture before this one; older ones go.
  defp forget_old(state, file) do
    {keep, drop} = Enum.split([file | state.shown], 2)
    Enum.each(drop, &File.rm(Path.join(state.dir, &1)))
    %{state | shown: keep}
  end

  defp export_params(state, file) do
    {"app.export", params} = Darkroom.preview_export(Path.join(state.dir, file))
    params
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:stop, :normal, state}

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    send(state.owner, {:darkroom_error, 0, "lightcraft-cli stopped (exit #{status})"})
    {:stop, :normal, %{state | port: nil}}
  end

  # A line nobody was waiting for (a notification).
  def handle_info({port, {:data, _}}, %{port: port} = state), do: {:noreply, state}
  def handle_info({:EXIT, _port, _reason}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state), do: close(state)

  defp close(state) do
    if state.port && Port.info(state.port) do
      os_pid = Port.info(state.port, :os_pid)
      Port.close(state.port)
      with {:os_pid, pid} <- os_pid, do: System.cmd("kill", ["#{pid}"], stderr_to_stdout: true)
    end

    File.rm_rf(state.dir)
    :ok
  end

  # ── JSON-RPC over the port ────────────────────────────────────────────

  defp command(state, name, params) do
    arguments = %{"command" => name, "params" => params}

    case rpc(state, "tools/call", %{"name" => "run_command", "arguments" => arguments}) do
      {:ok, %{"result" => %{"isError" => true, "content" => [%{"text" => text} | _]}}} ->
        {:error, text}

      {:ok, %{"result" => %{"content" => [%{"text" => text} | _]}}} ->
        {:ok, text}

      {:ok, %{"error" => %{"message" => message}}} ->
        {:error, "#{name}: #{message}"}

      {:ok, _} ->
        {:error, "#{name}: no answer"}

      error ->
        error
    end
  end

  defp tell(%{port: port}, method) do
    Port.command(port, [Jason.encode!(%{"jsonrpc" => "2.0", "method" => method}), "\n"])
    :ok
  end

  defp rpc(%{port: port}, method, params) do
    id = System.unique_integer([:positive, :monotonic])
    message = %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}
    Port.command(port, [Jason.encode!(message), "\n"])
    await(port, id, "")
  end

  defp await(port, id, partial) do
    receive do
      {^port, {:data, {:noeol, chunk}}} ->
        await(port, id, partial <> chunk)

      {^port, {:data, {:eol, chunk}}} ->
        case Jason.decode(partial <> chunk) do
          {:ok, %{"id" => ^id} = reply} -> {:ok, reply}
          _ -> await(port, id, "")
        end

      {^port, {:exit_status, status}} ->
        send(self(), {port, {:exit_status, status}})
        {:error, "lightcraft-cli stopped (exit #{status})"}
    after
      @timeout -> {:error, "lightcraft-cli did not answer"}
    end
  end
end
