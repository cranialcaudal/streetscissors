defmodule Web.Monitor do
  @moduledoc """
  The machine checking itself, and writing to its author when something has
  failed that fails quietly.

  A site hosted in a house has faults no visitor reports. A certificate stops
  renewing and nothing changes for weeks. The proxy's supervisor dies while a
  stray copy keeps serving. The provider hands the house a new address and the
  domain goes on pointing at the old one. Each of these has already happened
  here, or nearly, and each was found by accident.

  Every fifteen minutes `run/1` makes the outside-facing checks
  (`Web.Monitor.Probe`), reads the ones the overview already makes
  (`Web.SystemStatus.local_checks/0`: the snapshots, the content's versions,
  Komoot, the mail queue), and compares what is failing now with what was
  failing last time.

  **What is written, and when.** Only a `:fail` is ever mailed; a `:warn` is
  for the overview. A check has to fail on two passes running before a word is
  sent, so one dropped packet at the wrong moment is not an alarm. After that
  it is mentioned once, again each day it stays broken, and once more when it
  clears — and a failure that cleared before anyone was told is dropped
  without a word. One message carries everything a pass has to say.

  **What this cannot see.** It runs on the machine it watches, so it is silent
  about exactly the faults that silence it: the power is out, the machine is
  off, the house has no internet. That is what the check from outside is for
  (`.github/workflows/uptime.yml`, asking `/health`). And it cannot tell
  whether a stranger can reach the site, only whether the things that have to
  be true for that are true.

  The state lives in one `site_settings` row (`monitor_state`): when the last
  pass ran, what the probes found, and what is currently failing since when.
  `last/0` is what the overview shows, so opening the admin never makes a
  network call.
  """

  require Logger

  alias Web.Monitor.Probe
  alias Web.Notify
  alias Web.SiteSettings
  alias Web.SystemStatus

  @setting "monitor_state"
  @probes [:certificate, :front_door, :dns, :disk, :units]
  @states %{"ok" => :ok, "warn" => :warn, "fail" => :fail, "off" => :off}

  # A failure is mailed on its second pass running, then once a day.
  @passes_before_alert 2
  @remind_after_hours 24

  @doc """
  Makes one pass: probes, compares with the last pass, stores, and writes to
  the author if there is anything to say. Returns the probes' checks.
  """
  def run(now \\ DateTime.utc_now()) do
    probed = probe()
    watched = SystemStatus.local_checks() ++ probed

    failing_now = for %{state: :fail} = check <- watched, into: %{}, do: {key(check), check}
    {failing, events} = transitions(state()["failing"] || %{}, failing_now, watched, now)

    store(now, probed, failing)
    announce(events)
    probed
  end

  @doc """
  Entry point for the scheduler. Never raises — a monitor that crashes its
  own supervisor is worse than none.
  """
  def run_scheduled do
    run()
    :ok
  rescue
    error ->
      Logger.error("monitor crashed: #{Exception.message(error)}")
      :ok
  end

  @doc "Runs the configured probes now and returns their checks, storing nothing."
  def probe do
    :web
    |> Application.get_env(:monitor_probes, @probes)
    |> Enum.map(&apply(Probe, &1, []))
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  What the last pass found: `%{at: DateTime | nil, checks: [check]}`, each
  check stamped with the time of the pass. Empty before the first one.
  """
  def last do
    stored = state()

    with at when is_binary(at) <- stored["at"],
         {:ok, at, _offset} <- DateTime.from_iso8601(at) do
      checks =
        for %{"key" => key, "label" => label, "state" => state, "detail" => detail} <-
              stored["checks"] || [],
            probe = Enum.find(@probes, &(to_string(&1) == key)) do
          %{
            key: probe,
            label: label,
            state: Map.get(@states, state, :warn),
            detail: detail,
            at: at
          }
        end

      %{at: at, checks: checks}
    else
      _ -> %{at: nil, checks: []}
    end
  end

  # --- Transitions -----------------------------------------------------------

  # `previous` and the returned map are both keyed by check key, each value
  # %{"since", "passes", "alerted_at", "label"}. Events are what this pass has
  # to say: {:failing | :still | :cleared, label, detail}.
  defp transitions(previous, failing_now, watched, now) do
    {failing, raised} =
      Enum.map_reduce(failing_now, [], fn {key, check}, events ->
        entry = advance(previous[key], check, now)

        cond do
          is_nil(entry["alerted_at"]) and entry["passes"] >= @passes_before_alert ->
            {{key, alerted(entry, now)}, [{:failing, check.label, check.detail} | events]}

          due_reminder?(entry, now) ->
            {{key, alerted(entry, now)}, [{:still, check.label, check.detail} | events]}

          true ->
            {{key, entry}, events}
        end
      end)

    cleared =
      for {key, %{"alerted_at" => at} = entry} <- previous,
          not is_nil(at),
          not Map.has_key?(failing_now, key) do
        {:cleared, entry["label"], detail_now(watched, key)}
      end

    {Map.new(failing), Enum.reverse(raised) ++ cleared}
  end

  defp advance(nil, check, now) do
    %{
      "since" => DateTime.to_iso8601(now),
      "passes" => 1,
      "alerted_at" => nil,
      "label" => check.label
    }
  end

  defp advance(entry, check, _now) do
    entry |> Map.update("passes", 1, &(&1 + 1)) |> Map.put("label", check.label)
  end

  defp alerted(entry, now), do: Map.put(entry, "alerted_at", DateTime.to_iso8601(now))

  defp due_reminder?(%{"alerted_at" => at}, now) when is_binary(at) do
    case DateTime.from_iso8601(at) do
      {:ok, alerted_at, _} -> DateTime.diff(now, alerted_at, :hour) >= @remind_after_hours
      _ -> true
    end
  end

  defp due_reminder?(_entry, _now), do: false

  defp detail_now(watched, key) do
    case Enum.find(watched, &(key(&1) == key)) do
      %{detail: detail} -> detail
      nil -> "no longer checked"
    end
  end

  defp key(%{key: key}), do: to_string(key)

  # --- Writing to the author -------------------------------------------------

  defp announce([]), do: :ok

  defp announce(events) do
    case Notify.deliver(subject(events), body(events)) do
      {:ok, _job} -> Logger.warning("monitor: wrote to the author: #{subject(events)}")
      :no_address -> Logger.warning("monitor: #{subject(events)} (no address to write to)")
      {:error, reason} -> Logger.error("monitor: could not queue mail: #{inspect(reason)}")
    end
  end

  defp subject(events) do
    case Enum.split_with(events, &(elem(&1, 0) == :cleared)) do
      {_cleared, [{_, label, _}]} -> "streetscissors: #{String.downcase(label)} needs you"
      {_cleared, [_ | _] = broken} -> "streetscissors: #{length(broken)} things need you"
      {[{_, label, _}], []} -> "streetscissors: #{String.downcase(label)} is working again"
      {cleared, []} -> "streetscissors: #{length(cleared)} things are working again"
    end
  end

  defp body(events) do
    lines =
      Enum.map_join(events, "\n\n", fn
        {:failing, label, detail} -> "FAILING — #{label}: #{detail}"
        {:still, label, detail} -> "STILL FAILING — #{label}: #{detail}"
        {:cleared, label, detail} -> "CLEARED — #{label}: #{detail}"
      end)

    """
    The machine checked itself and has this to report.

    #{lines}

    The rest is on the overview:
    #{WebWeb.Endpoint.url()}/admin/dashboard
    """
  end

  # --- Storage ---------------------------------------------------------------

  defp state do
    with json when is_binary(json) <- SiteSettings.get_setting(@setting),
         {:ok, %{} = state} <- Jason.decode(json) do
      state
    else
      _ -> %{}
    end
  end

  defp store(now, probed, failing) do
    checks =
      for check <- probed do
        %{
          "key" => to_string(check.key),
          "label" => check.label,
          "state" => to_string(check.state),
          "detail" => check.detail
        }
      end

    SiteSettings.put_setting(
      @setting,
      Jason.encode!(%{"at" => DateTime.to_iso8601(now), "checks" => checks, "failing" => failing})
    )
  end
end
