defmodule Web.Monitor.ProbeTest do
  # Every probe takes its outside world as an option, so nothing here opens a
  # socket, asks a resolver or runs a command.
  use ExUnit.Case, async: true

  alias Web.Monitor.Probe

  @now ~U[2030-03-02 12:00:00Z]

  defp expiring_in(days), do: fn _host -> {:ok, DateTime.add(@now, days, :day)} end

  describe "certificate/1" do
    test "is fine with a month in hand" do
      assert %{key: :certificate, state: :ok, detail: "33 days left"} =
               Probe.certificate(fetch: expiring_in(33), now: @now)
    end

    # Caddy renews with thirty days left. Under three weeks, it has been
    # trying and failing for over a week.
    test "warns once renewal is overdue, and fails when it is urgent" do
      assert %{state: :warn, detail: "20 days left — should have renewed by now"} =
               Probe.certificate(fetch: expiring_in(20), now: @now)

      assert %{state: :fail, detail: "13 days left — renewal is failing"} =
               Probe.certificate(fetch: expiring_in(13), now: @now)

      assert %{state: :fail, detail: "1 day left" <> _} =
               Probe.certificate(fetch: expiring_in(1), now: @now)
    end

    test "says so when it has already run out" do
      assert %{state: :fail, detail: "expired 2 days ago" <> _} =
               Probe.certificate(fetch: expiring_in(-2), now: @now)
    end

    test "an untrusted or unserved certificate fails, with the reason" do
      alert = {:tls_alert, {:certificate_expired, ~c"TLS client: ..."}}

      assert %{state: :fail, detail: "not served or not trusted (certificate expired)"} =
               Probe.certificate(fetch: fn _ -> {:error, alert} end, now: @now)

      assert %{state: :fail, detail: "not served or not trusted (econnrefused)"} =
               Probe.certificate(fetch: fn _ -> {:error, :econnrefused} end, now: @now)
    end
  end

  describe "front_door/1" do
    test "asks /health on the site's own name" do
      test = self()

      assert %{key: :front_door, state: :ok} =
               Probe.front_door(
                 get: fn url ->
                   send(test, {:asked, url})
                   {:ok, 200}
                 end
               )

      assert_received {:asked, "https://" <> rest}
      assert String.ends_with?(rest, "/health")
    end

    test "fails on any other answer, and on none" do
      assert %{state: :fail, detail: "/health answered 502"} =
               Probe.front_door(get: fn _ -> {:ok, 502} end)

      assert %{state: :fail, detail: "no answer (econnrefused)"} =
               Probe.front_door(get: fn _ -> {:error, %{reason: :econnrefused}} end)
    end
  end

  describe "dns/1" do
    test "is fine when the record is this machine's address" do
      assert %{key: :dns, state: :ok, detail: "points here (192.0.2.10)"} =
               Probe.dns(
                 resolve: fn _ -> {:ok, ["192.0.2.10"]} end,
                 whoami: fn -> {:ok, "192.0.2.10"} end
               )
    end

    # The provider handed the house a new address. Both are named, because the
    # fix is typing the second one into the registrar's panel.
    test "fails when the record points somewhere else, naming both" do
      check =
        Probe.dns(
          resolve: fn _ -> {:ok, ["192.0.2.10"]} end,
          whoami: fn -> {:ok, "198.51.100.7"} end
        )

      assert check.state == :fail
      assert check.detail =~ "points at 192.0.2.10"
      assert check.detail =~ "set the A record to 198.51.100.7"
    end

    test "fails when the domain has no record at all" do
      assert %{state: :fail, detail: detail} =
               Probe.dns(resolve: fn _ -> {:ok, []} end, whoami: fn -> {:ok, "192.0.2.10"} end)

      assert detail =~ "has no A record"
    end

    # No route to a resolver is this machine's wifi, not the site being down.
    test "a lookup that could not be made is a warning, never a failure" do
      assert %{state: :warn, detail: "could not be looked up"} =
               Probe.dns(resolve: fn _ -> {:error, :timeout} end, whoami: fn -> :error end)

      assert %{state: :warn} =
               Probe.dns(resolve: fn _ -> {:ok, ["192.0.2.10"]} end, whoami: fn -> :error end)
    end
  end

  describe "disk/1" do
    defp free(percent, gb) do
      fn _path -> {:ok, %{free_percent: percent, free_bytes: gb * 1024 * 1024 * 1024}} end
    end

    test "reports what is free, and escalates as it runs out" do
      assert %{key: :disk, state: :ok, detail: "26% free (252 GB)"} =
               Probe.disk(df: free(26, 252))

      assert %{state: :warn, detail: "9% free (85 GB)"} = Probe.disk(df: free(9, 85))

      assert %{state: :fail, detail: "4% free (38 GB) — nearly full"} =
               Probe.disk(df: free(4, 38))
    end

    test "is a warning when it cannot be measured" do
      assert %{state: :warn, detail: "could not be measured"} = Probe.disk(df: fn _ -> :error end)
    end

    test "really measures the volume the database is on" do
      assert %{state: state, detail: detail} = Probe.disk()
      assert state in [:ok, :warn, :fail]
      assert detail =~ ~r/^\d+% free \(\d+ GB\)/
    end
  end

  describe "units/1" do
    setup do
      on_exit(fn -> Application.delete_env(:web, :monitor_units) end)
    end

    test "is not a check at all when no units are named" do
      Application.put_env(:web, :monitor_units, [])
      assert Probe.units(active?: fn _ -> true end) == nil
    end

    test "names the unit that is not running" do
      Application.put_env(:web, :monitor_units, ["proxy.service", "other.service"])

      assert %{key: :units, state: :ok, detail: "2 running under systemd"} =
               Probe.units(active?: fn _ -> true end)

      assert %{state: :fail, detail: "not running: proxy.service"} =
               Probe.units(active?: &(&1 != "proxy.service"))
    end
  end
end
