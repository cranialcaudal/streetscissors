defmodule Web.Monitor.Probe do
  @moduledoc """
  The checks that reach outside the application: the certificate, the proxy in
  front of it, where the domain points, how full the disk is, and whether the
  units that should be running are.

  Each returns the same map `Web.SystemStatus` uses, so the overview lists
  them alongside its own. They differ from those in cost — a handshake, a DNS
  query, a child process — which is why `Web.Monitor` runs them on a schedule
  and the overview only reads what the last pass found.

  **What each state means.** `:fail` is a fault someone has to act on, and is
  what `Web.Monitor` writes to the author about. `:warn` is either an early
  sign (a certificate that should have renewed by now) or a check that could
  not be made at all — no route to a resolver, say. A lookup that could not be
  made is never a `:fail`: a wifi blip must not be reported as the site being
  down.

  Every probe takes its outside world as options, so the suite never opens a
  socket: `fetch:` for the certificate, `get:` for the proxy, `resolve:` and
  `whoami:` for DNS, `df:` for the disk, `active?:` for the units.
  """

  @connect_timeout 5_000

  # Caddy renews a ninety-day certificate with thirty days left. Three weeks
  # left means renewal has been failing for over a week; two means it needs a
  # person.
  @cert_warn_days 21
  @cert_fail_days 14

  @disk_warn_percent 10
  @disk_fail_percent 5

  # Asked directly, so /etc/hosts and the router's own resolver have no say.
  @resolvers [{{1, 1, 1, 1}, 53}, {{8, 8, 8, 8}, 53}]
  # OpenDNS answers this name with the address the question came from.
  @whoami_name ~c"myip.opendns.com"
  @whoami_resolvers [{{208, 67, 222, 222}, 53}, {{208, 67, 220, 220}, 53}]

  # --- Certificate -----------------------------------------------------------

  @doc """
  The certificate the proxy serves for the site's own name: trusted, and not
  about to run out.
  """
  def certificate(opts \\ []) do
    fetch = Keyword.get(opts, :fetch, &peer_certificate_expiry/1)
    now = Keyword.get(opts, :now, DateTime.utc_now())

    case fetch.(host()) do
      {:ok, %DateTime{} = expires} ->
        days = DateTime.diff(expires, now, :day)

        cond do
          days < @cert_fail_days ->
            check(:certificate, "Certificate", :fail, "#{left(days)} — renewal is failing")

          days < @cert_warn_days ->
            check(
              :certificate,
              "Certificate",
              :warn,
              "#{left(days)} — should have renewed by now"
            )

          true ->
            check(:certificate, "Certificate", :ok, left(days))
        end

      {:error, reason} ->
        check(
          :certificate,
          "Certificate",
          :fail,
          "not served or not trusted (#{explain(reason)})"
        )
    end
  end

  defp left(days) when days < 0, do: "expired #{-days} #{plural(-days, "day")} ago"
  defp left(days), do: "#{days} #{plural(days, "day")} left"

  @doc """
  Connects to the site's name on 443, verifies the chain and the hostname the
  way a browser would, and returns when the certificate runs out.
  """
  def peer_certificate_expiry(host) do
    name = String.to_charlist(host)

    opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: name,
      customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
    ]

    with {:ok, socket} <- :ssl.connect(name, 443, opts, @connect_timeout) do
      result = :ssl.peercert(socket)
      :ssl.close(socket)

      with {:ok, der} <- result do
        {:ok, not_after(der)}
      end
    end
  rescue
    error -> {:error, error}
  end

  # {:OTPCertificate, {:OTPTBSCertificate, _, _, _, _, {:Validity, _, not_after}, …}, _, _}
  defp not_after(der) do
    {:Validity, _not_before, not_after} =
      der |> :public_key.pkix_decode_cert(:otp) |> elem(1) |> elem(5)

    not_after
    |> :pubkey_cert.time_str_2_gregorian_sec()
    |> :calendar.gregorian_seconds_to_datetime()
    |> NaiveDateTime.from_erl!()
    |> DateTime.from_naive!("Etc/UTC")
  end

  # --- The proxy -------------------------------------------------------------

  @doc """
  The site answered through the proxy: `GET /health` on its public name,
  over TLS. This is the path a visitor takes from the proxy inward, so it
  fails when Caddy is down, when it cannot reach the application, or when the
  application cannot reach its database.
  """
  def front_door(opts \\ []) do
    get = Keyword.get(opts, :get, &get_health/1)
    url = "https://#{host()}/health"

    case get.(url) do
      {:ok, 200} -> check(:front_door, "Proxy", :ok, "answers over HTTPS")
      {:ok, status} -> check(:front_door, "Proxy", :fail, "/health answered #{status}")
      {:error, reason} -> check(:front_door, "Proxy", :fail, "no answer (#{explain(reason)})")
    end
  end

  defp get_health(url) do
    case Req.get(url, retry: false, receive_timeout: @connect_timeout, redirect: false) do
      {:ok, %{status: status}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  end

  # --- DNS -------------------------------------------------------------------

  @doc """
  The domain's public A record against the address this machine is reached at.

  A home connection's address is lent, not owned, and can change after a modem
  swap or a long outage. When it does, the site is unreachable from everywhere
  but this house — where `/etc/hosts` and the local network keep it working,
  so nothing here looks wrong. Both answers come from public resolvers asked
  directly, for that reason.
  """
  def dns(opts \\ []) do
    resolve = Keyword.get(opts, :resolve, &resolve_a/1)
    whoami = Keyword.get(opts, :whoami, &public_address/0)

    with {:ok, [_ | _] = records} <- resolve.(host()),
         {:ok, address} <- whoami.() do
      if address in records do
        check(:dns, "DNS", :ok, "points here (#{address})")
      else
        check(
          :dns,
          "DNS",
          :fail,
          "#{host()} points at #{Enum.join(records, ", ")} but this machine is at #{address} — " <>
            "set the A record to #{address}"
        )
      end
    else
      {:ok, []} -> check(:dns, "DNS", :fail, "#{host()} has no A record")
      _ -> check(:dns, "DNS", :warn, "could not be looked up")
    end
  end

  defp resolve_a(host), do: lookup(String.to_charlist(host), @resolvers)

  defp public_address do
    case lookup(@whoami_name, @whoami_resolvers) do
      {:ok, [address | _]} -> {:ok, address}
      _ -> :error
    end
  end

  # :inet_res.lookup/5 returns [] both for "no such record" and for "nobody
  # answered", so the two are told apart with resolve/5.
  defp lookup(name, nameservers) do
    case :inet_res.resolve(name, :in, :a, nameservers: nameservers, timeout: 3_000) do
      {:ok, message} ->
        addresses =
          for record <- :inet_dns.msg(message, :anlist),
              :inet_dns.rr(record, :type) == :a,
              do: record |> :inet_dns.rr(:data) |> :inet.ntoa() |> List.to_string()

        {:ok, addresses}

      {:error, {:nxdomain, _}} ->
        {:ok, []}

      {:error, :nxdomain} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Disk ------------------------------------------------------------------

  @doc "Free space on the volume the database lives on."
  def disk(opts \\ []) do
    df = Keyword.get(opts, :df, &free_space/1)

    case df.(data_dir()) do
      {:ok, %{free_percent: percent, free_bytes: bytes}} ->
        detail = "#{percent}% free (#{gigabytes(bytes)} GB)"

        cond do
          percent < @disk_fail_percent -> check(:disk, "Disk", :fail, detail <> " — nearly full")
          percent < @disk_warn_percent -> check(:disk, "Disk", :warn, detail)
          true -> check(:disk, "Disk", :ok, detail)
        end

      _ ->
        check(:disk, "Disk", :warn, "could not be measured")
    end
  end

  # POSIX output: filesystem, 1024-blocks, used, available, capacity, mount.
  defp free_space(path) do
    with {out, 0} <- System.cmd("df", ["-Pk", path], stderr_to_stdout: true),
         [_header, line | _] <- String.split(out, "\n", trim: true),
         [_fs, total, _used, available | _] <- String.split(line),
         {total, ""} when total > 0 <- Integer.parse(total),
         {available, ""} <- Integer.parse(available) do
      {:ok, %{free_percent: div(available * 100, total), free_bytes: available * 1024}}
    else
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp gigabytes(bytes), do: div(bytes, 1024 * 1024 * 1024)

  defp data_dir do
    case Web.Repo.config()[:database] do
      path when is_binary(path) -> Path.dirname(Path.expand(path))
      _ -> File.cwd!()
    end
  end

  # --- Units -----------------------------------------------------------------

  @doc """
  The systemd user units named in `:monitor_units`, each asked whether it is
  active. `nil` when none are named.

  The proxy answering is not proof its unit is running. A Caddy started by
  hand once outlived the unit that was meant to supervise it and served for
  five days while the unit failed 73,000 restarts behind it; the site was up
  the whole time, and one reboot from not being.
  """
  def units(opts \\ []) do
    active? = Keyword.get(opts, :active?, &unit_active?/1)

    case Application.get_env(:web, :monitor_units, []) do
      [] ->
        nil

      units ->
        case Enum.reject(units, active?) do
          [] ->
            check(:units, "Services", :ok, "#{length(units)} running under systemd")

          down ->
            check(:units, "Services", :fail, "not running: #{Enum.join(down, ", ")}")
        end
    end
  end

  defp unit_active?(unit) do
    match?({_, 0}, System.cmd("systemctl", ["--user", "is-active", "--quiet", unit]))
  rescue
    # No systemctl here at all.
    _ -> false
  end

  # --- Shared ----------------------------------------------------------------

  defp host, do: WebWeb.Endpoint.config(:url)[:host]

  defp check(key, label, state, detail) do
    %{key: key, label: label, state: state, detail: detail, at: nil}
  end

  defp plural(1, word), do: word
  defp plural(_, word), do: word <> "s"

  defp explain({:tls_alert, {alert, _text}}), do: alert |> to_string() |> String.replace("_", " ")
  defp explain(%{reason: reason}), do: explain(reason)
  defp explain(reason) when is_atom(reason), do: to_string(reason)
  defp explain(reason) when is_binary(reason), do: reason
  defp explain(reason), do: inspect(reason)
end
