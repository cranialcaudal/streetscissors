defmodule Web.RateLimit do
  @moduledoc """
  A small fixed-window rate limiter backed by ETS.

  This site had none, which mattered in three specific ways: `POST
  /admin/login` accepted unlimited password guesses; newsletter subscribe sent
  a real email per request from the site's own sender identity (an easy way to
  burn sender reputation); and `check_spelling` relayed arbitrary text to
  api.languagetool.org from every page.

  Deliberately dependency-free — one node, one ETS table, counters that expire
  by window. `Hammer` would be the answer for a clustered deployment; this is
  not one.

  Windows are fixed rather than sliding, so a caller can in the worst case get
  `2 × limit` across a window boundary. That is fine for the abuse this guards
  against and keeps the whole thing to one atomic operation per check.
  """

  use GenServer

  @table :web_rate_limit
  # Sweep expired buckets so the table cannot grow without bound.
  @sweep_every :timer.minutes(5)

  # ── Public API ────────────────────────────────────────────────────

  @doc """
  Counts a hit against `key` and reports whether it is allowed.

  Returns `{:ok, remaining}` or `{:error, :rate_limited, seconds_until_reset}`.

      Web.RateLimit.hit("login:1.2.3.4", limit: 5, window: :timer.minutes(15))
  """
  @spec hit(String.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, :rate_limited, non_neg_integer()}
  def hit(key, opts) do
    limit = Keyword.fetch!(opts, :limit)
    window = Keyword.fetch!(opts, :window)
    now = System.system_time(:millisecond)
    bucket = div(now, window)
    resets_at = (bucket + 1) * window

    # One atomic increment; the {key, bucket} pair means a new window starts a
    # fresh counter without anyone having to reset the old one.
    count = :ets.update_counter(@table, {key, bucket}, {2, 1}, {{key, bucket}, 0, resets_at})

    if count > limit do
      {:error, :rate_limited, max(div(resets_at - now, 1000), 1)}
    else
      {:ok, limit - count}
    end
  rescue
    # If the table is missing (limiter not started, e.g. in a bare unit test)
    # fail open rather than take the site down over a counter.
    ArgumentError -> {:ok, 0}
  end

  @doc """
  True when `key` is within its limit. Thin wrapper over `hit/2` for call sites
  that do not need the remaining count.
  """
  @spec allow?(String.t(), keyword()) :: boolean()
  def allow?(key, opts) do
    match?({:ok, _}, hit(key, opts))
  end

  @doc "Clears all counters. Test support; a no-op if the limiter is not running."
  def reset_all do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  # ── GenServer ─────────────────────────────────────────────────────

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    # :public so callers increment directly without a GenServer round-trip —
    # this runs on every guarded request.
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.system_time(:millisecond)
    # {{key, bucket}, count, resets_at} — drop anything whose window has passed.
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_every)
end
