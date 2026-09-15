defmodule Web.RateLimitTest do
  use ExUnit.Case, async: false

  alias Web.RateLimit

  setup do
    RateLimit.reset_all()
    :ok
  end

  test "allows up to the limit, then refuses" do
    opts = [limit: 3, window: :timer.minutes(5)]

    assert {:ok, 2} = RateLimit.hit("k", opts)
    assert {:ok, 1} = RateLimit.hit("k", opts)
    assert {:ok, 0} = RateLimit.hit("k", opts)
    assert {:error, :rate_limited, retry_after} = RateLimit.hit("k", opts)
    assert retry_after > 0
  end

  test "counts each key separately, so one visitor cannot lock out another" do
    opts = [limit: 1, window: :timer.minutes(5)]

    assert {:ok, _} = RateLimit.hit("ip-a", opts)
    assert {:error, :rate_limited, _} = RateLimit.hit("ip-a", opts)
    assert {:ok, _} = RateLimit.hit("ip-b", opts)
  end

  test "a new window starts a fresh count" do
    # A 1ms window rolls over between calls without any sleeping.
    opts = [limit: 1, window: 1]

    assert {:ok, _} = RateLimit.hit("rollover", opts)
    Process.sleep(3)
    assert {:ok, _} = RateLimit.hit("rollover", opts)
  end

  test "allow?/2 mirrors hit/2" do
    opts = [limit: 1, window: :timer.minutes(5)]

    assert RateLimit.allow?("a?", opts)
    refute RateLimit.allow?("a?", opts)
  end

  # The fail-open path in hit/2 (rescue ArgumentError -> {:ok, 0}) is
  # deliberately not exercised here: proving it means deleting the named table,
  # and an ETS table is owned by the process that created it, so a test cannot
  # put it back — every later test in the run would then fail on a missing
  # table. It exists so an unstarted limiter degrades to "allowed" instead of
  # 500-ing a public page.
end
