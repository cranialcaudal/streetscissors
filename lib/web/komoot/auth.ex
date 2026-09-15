defmodule Web.Komoot.Auth do
  @moduledoc """
  Holds the Komoot API token between syncs.

  Logging in is the one call that can cost the account: it is the endpoint
  that locks out under repeated failures, which is why `Web.Komoot.Client`
  never retries it. The token it hands back keeps working for far longer
  than the hour between syncs, so authenticating on every pass bought
  nothing and spent 24 logins a day against an unofficial API.

  The login itself runs in the **caller**, not in this process — this one
  only remembers the result. That keeps the HTTP call inside whatever
  process the test stub is bound to, and means a slow login can never block
  a read of the cache.
  """

  use GenServer

  alias Web.Komoot.Client

  # Komoot publishes no token lifetime. A day is well inside the observed
  # one, and guessing short only costs an extra login — `invalidate/0`
  # clears the cache the moment a call comes back unauthorized, so a token
  # that dies early is corrected on the spot rather than waited out.
  @ttl :timer.hours(24)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @doc """
  The cached token, logging in with the configured credentials on a miss.

  Returns `{:error, :not_configured}` when no credentials are set, and
  otherwise whatever `Client.login/2` returned.
  """
  @spec fetch() :: {:ok, Client.auth()} | {:error, term}
  def fetch do
    case GenServer.call(__MODULE__, :get) do
      {:ok, auth} ->
        {:ok, auth}

      :miss ->
        config = Application.get_env(:web, :komoot) || []

        with {:ok, auth} <- login(config[:email], config[:password]) do
          :ok = GenServer.call(__MODULE__, {:put, auth})
          {:ok, auth}
        end
    end
  end

  @doc "Drops the cached token so the next `fetch/0` logs in again."
  @spec invalidate() :: :ok
  def invalidate, do: GenServer.call(__MODULE__, :clear)

  defp login(email, password) when is_binary(email) and is_binary(password) do
    Client.login(email, password)
  end

  defp login(_email, _password), do: {:error, :not_configured}

  # ── GenServer ─────────────────────────────────────────────────────

  @impl true
  def init(:ok), do: {:ok, nil}

  @impl true
  def handle_call(:get, _from, {auth, expires_at} = state) do
    if System.monotonic_time(:millisecond) < expires_at do
      {:reply, {:ok, auth}, state}
    else
      {:reply, :miss, nil}
    end
  end

  def handle_call(:get, _from, nil), do: {:reply, :miss, nil}

  def handle_call({:put, auth}, _from, _state) do
    {:reply, :ok, {auth, System.monotonic_time(:millisecond) + @ttl}}
  end

  def handle_call(:clear, _from, _state), do: {:reply, :ok, nil}
end
