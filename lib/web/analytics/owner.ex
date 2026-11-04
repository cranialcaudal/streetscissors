defmodule Web.Analytics.Owner do
  @moduledoc """
  Recognises the author's own visits so they are left out of the figures.

  A personal site's author is its heaviest reader. A list of addresses
  (`EXCLUDED_IPS`) cannot do this alone: a residential address is reassigned
  when the line or provider changes, and a phone behind iCloud Private Relay
  leaves from rotating addresses. The author is therefore recognised by hashes
  gathered three ways, with `EXCLUDED_IPS` kept as a manual override:

    * **Marker cookie** (`WebWeb.OwnerMark`): set on every request made with an
      admin session and renewed on every request after, so a browser that has
      logged in once stops counting on any network, logged in or out. This is
      the only layer that survives a new address.
    * **Access log** (`candidates/1`): a request *answered* on an `/admin/*`
      path was made by the author, because an unauthenticated one is
      redirected. This is the only layer that reaches back over old addresses,
      and the only one that **proposes rather than decides**: it proves the
      address was the author's when the request was made, not that every visit
      from it was.
    * **The home address** (`note_wan/1`): resolved every fifteen minutes by the
      monitor's DNS probe, so the home network is covered even from a browser
      that has never logged in.

  Only hashes are stored, as in `analytics_hits`. The set lives in one
  `site_settings` row and is held in `:persistent_term`, so the `:browser`
  pipeline reads nothing from the database per request (one read per boot,
  through `Web.Warm`).

  It is deliberately **not** a derived table: the nightly analytics pass may
  rebuild or prune caches, and a rebuild must never start counting the author
  again.
  """
  import Ecto.Query, warn: false

  alias Web.Analytics
  alias Web.Analytics.{AccessLog, Hit}
  alias Web.Repo
  alias Web.SiteSettings

  require Logger

  @setting "owner_hashes"
  @dismissed "owner_not_mine"
  @key {__MODULE__, :hashes}

  # A /live/* longpoll carrying an admin page as its referer is good evidence,
  # but anyone can ask for that URL once (they are refused, and the refusal is
  # still logged), so it counts only when it keeps happening.
  @weak_threshold 3

  @doc "The owner's hashes. Read from `:persistent_term`, loaded once per boot."
  def hashes do
    case :persistent_term.get(@key, nil) do
      nil -> reload()
      %MapSet{} = set -> set
    end
  end

  @doc "Whether a hash is the owner's."
  def mine?(hash) when is_binary(hash), do: MapSet.member?(hashes(), hash)
  def mine?(_), do: false

  @doc """
  Whether an address is the owner's, by its hash.

  The hash is only computed when there is something to compare it against, so
  a site with no owner hashes recorded pays nothing per request.
  """
  def mine_ip?(ip) when is_binary(ip) do
    set = hashes()
    MapSet.size(set) > 0 and MapSet.member?(set, Analytics.hash_ip(ip))
  end

  def mine_ip?(_), do: false

  @doc "The owner's hashes as a list, for a query that has to name them."
  def hash_list, do: MapSet.to_list(hashes())

  @doc "Reads the set from the database into `:persistent_term`. Returns it."
  def reload do
    set = stored() |> Map.keys() |> MapSet.new()
    :persistent_term.put(@key, set)
    set
  end

  @doc "Everything known about each hash, newest first."
  def list do
    stored()
    |> Enum.map(fn {hash, meta} ->
      %{
        hash: hash,
        badge: String.slice(hash, 0, 6),
        since: meta["since"],
        source: meta["source"] || "manual",
        note: meta["note"]
      }
    end)
    |> Enum.sort_by(& &1.since, :desc)
  end

  @doc """
  Records one or more hashes as the owner's. Returns how many were new.

  A hash already recorded keeps the date and source it was first seen with: a
  nightly log scan should not keep rewriting the day the author was recognised.
  """
  def add(hash, opts \\ [])

  def add(hash, opts) when is_binary(hash), do: add([hash], opts)

  def add(hashes, opts) when is_list(hashes) do
    source = Keyword.get(opts, :source, "manual")
    note = Keyword.get(opts, :note)
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    current = stored()

    fresh =
      hashes
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.reject(&Map.has_key?(current, &1))

    if fresh == [] do
      {:ok, 0}
    else
      added =
        for h <- fresh,
            into: %{},
            do: {h, drop_nils(%{"since" => now, "source" => source, "note" => note})}

      SiteSettings.put_setting(@setting, Jason.encode!(Map.merge(current, added)))
      reload()
      {:ok, length(fresh)}
    end
  end

  @doc "Forgets that a hash was the owner's, so it counts again."
  def remove(hash) when is_binary(hash) do
    SiteSettings.put_setting(@setting, Jason.encode!(Map.delete(stored(), hash)))
    reload()
    :ok
  end

  @doc "Records the house's current public address, by hash. Never raises."
  def note_wan(ip) when is_binary(ip) do
    add(Analytics.hash_ip(ip), source: "wan")
    :ok
  rescue
    error ->
      Logger.warning("could not note the house's address: #{inspect(error)}")
      :ok
  end

  def note_wan(_), do: :ok

  @doc """
  What the access logs say about who the author is, as
  `%{hash => evidence}`.

  Answered `/admin/*` requests are the evidence. `/admin/login` is **not**: it
  is a public page, answered for anyone who asks.

  Each entry carries *when* the admin was answered and *what browser* asked,
  because that is the part that decides nothing on its own. An answered admin
  request proves the address was the author's **at that moment**. It does not
  prove that every visit recorded from it was: a residential address is
  reassigned, and a household has more than one person in it, so later views
  from other devices may be someone else's.

  So this proposes, and `add/2` is called by someone who has looked.
  """
  def scan_access_logs(opts \\ []) do
    {strong, weak} = AccessLog.reduce_lines({%{}, %{}}, &sift/2, opts)

    weak
    |> Enum.filter(fn {_ip, evidence} -> evidence.requests >= @weak_threshold end)
    |> Map.new()
    |> Map.merge(strong, fn _ip, a, b -> merge_evidence(a, b) end)
    |> Map.new(fn {ip, evidence} ->
      {Analytics.hash_ip(ip), Map.put(evidence, :ip, ip)}
    end)
  end

  @doc """
  The log's candidates that are neither recorded nor already set aside, each
  beside what the database holds for it, so the decision is made by someone
  who can see both.

  A candidate whose visits look nothing like the session that identified it —
  a different browser, on dates that do not overlap — is the interesting one,
  and `devices` and `span` against `admin_agents` and `admin_last` are what
  show it.
  """
  def candidates(opts \\ []) do
    set_aside = dismissed()

    found =
      scan_access_logs(opts)
      |> Enum.reject(fn {hash, _} -> mine?(hash) or MapSet.member?(set_aside, hash) end)
      |> Map.new()

    figures = figures_for(Map.keys(found))

    found
    |> Enum.map(fn {hash, evidence} ->
      %{
        hash: hash,
        badge: String.slice(hash, 0, 6),
        admin_requests: evidence.requests,
        admin_first: stamp(evidence.first),
        admin_last: stamp(evidence.last),
        admin_agents: Enum.map(evidence.agents, &Analytics.friendly_device/1) |> Enum.uniq(),
        # Every key is present whether or not the database has anything for
        # this hash. A candidate with no visits left is ordinary: the author may have
        # deleted them already, or the address may be new — and a caller
        # should not have to guess which keys a row came with.
        hits: 0,
        days: 0,
        pages: 0,
        devices: [],
        first_seen: nil,
        last_seen: nil
      }
      |> Map.merge(Map.get(figures, hash, %{}))
    end)
    |> Enum.sort_by(& &1.hits, :desc)
  end

  @doc """
  Sets a hash aside: the log says it was the author's, and the author says the visits are not.

  Without this the nightly scan would keep proposing the same address every
  night for as long as the log remembers it.
  """
  def dismiss(hash) when is_binary(hash) do
    SiteSettings.put_setting(@dismissed, Jason.encode!(Enum.uniq([hash | dismissed_list()])))
    :ok
  end

  @doc "Takes a hash out of the set-aside list, so it is proposed again."
  def undismiss(hash) when is_binary(hash) do
    SiteSettings.put_setting(@dismissed, Jason.encode!(List.delete(dismissed_list(), hash)))
    :ok
  end

  @doc "The hashes the log attributes to the author that the author has rejected."
  def dismissed, do: MapSet.new(dismissed_list())

  @doc """
  The owner's addresses that `EXCLUDED_IPS` names outright, by hash.

  Only the exact entries: a wildcard or a CIDR describes a range, and a range
  cannot be hashed. Those keep working as they always did, in
  `WebWeb.Visitor.excluded?/1`.
  """
  def hashes_from_excluded_ips do
    (System.get_env("EXCLUDED_IPS") || "")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&plain_address?/1)
    |> Enum.map(&Analytics.hash_ip/1)
  end

  @doc """
  Takes in what needs no judgement and proposes the rest.

  Two things are recorded without asking, because neither can hide anybody:

    * the addresses listed in `EXCLUDED_IPS`;
    * a log candidate with **no visits recorded against it at all**: there is
      nothing to take out of the figures, so the only effect is on later
      visits, which would be the author's. Asking about these would bury the
      candidates that matter.

  What is left is an address that was the author's once and has reading recorded
  against it. That is the only case where being wrong costs something — a real
  reader's history disappears from the page — so it is returned to be looked
  at rather than acted on.
  """
  def refresh(opts \\ []) do
    {:ok, from_env} = add(hashes_from_excluded_ips(), source: "excluded-ips")

    {harmless, real} = Enum.split_with(candidates(opts), &(&1.hits == 0))

    {:ok, auto} = add(Enum.map(harmless, & &1.hash), source: "admin-log")

    {:ok, %{added: from_env + auto, candidates: length(real)}}
  end

  # --- the log rule ----------------------------------------------------------

  defp sift(line, {strong, weak} = acc) do
    # Cheap test first: the whole log is ~260,000 objects, and only a few
    # hundred lines mention the admin at all. The referer carries it
    # percent-encoded (%2Fadmin%2F), so match the bare word.
    if String.contains?(line, "admin") do
      case AccessLog.decode(line) do
        %{"request" => %{"uri" => uri, "client_ip" => ip}, "status" => status} = entry
        when is_binary(uri) and is_binary(ip) and is_integer(status) ->
          classify(entry, uri, ip, status, strong, weak)

        _ ->
          acc
      end
    else
      acc
    end
  end

  defp classify(entry, uri, ip, status, strong, weak) do
    path = uri |> String.split("?") |> hd()

    cond do
      ip in ["127.0.0.1", "::1"] ->
        {strong, weak}

      path in ["/admin/login", "/admin/logout"] ->
        {strong, weak}

      String.starts_with?(path, "/admin") and status in 200..299 ->
        {note(strong, ip, entry), weak}

      String.starts_with?(path, "/live/") and status in [101, 200] and admin_referer?(uri) ->
        {strong, note(weak, ip, entry)}

      true ->
        {strong, weak}
    end
  end

  # When, how often, and with which browser — so a visit pattern that looks
  # nothing like the session can be seen not to match it.
  defp note(map, ip, entry) do
    at = entry["ts"]
    agent = entry |> get_in(["request", "headers", "User-Agent"]) |> List.wrap() |> List.first()

    Map.update(
      map,
      ip,
      %{requests: 1, first: at, last: at, agents: List.wrap(agent)},
      fn seen ->
        %{
          requests: seen.requests + 1,
          first: min(seen.first || at, at || seen.first),
          last: max(seen.last || at, at || seen.last),
          agents: Enum.uniq(seen.agents ++ List.wrap(agent))
        }
      end
    )
  end

  defp merge_evidence(a, b) do
    %{
      requests: a.requests + b.requests,
      first: min(a.first, b.first),
      last: max(a.last, b.last),
      agents: Enum.uniq(a.agents ++ b.agents)
    }
  end

  defp stamp(nil), do: nil
  defp stamp(ts) when is_number(ts), do: DateTime.from_unix!(trunc(ts))

  defp admin_referer?(uri) do
    with [_, encoded] <- Regex.run(~r/_live_referer=([^&]+)/, uri),
         decoded = URI.decode(encoded),
         %URI{path: path} when is_binary(path) <- URI.parse(decoded) do
      String.starts_with?(path, "/admin") and path not in ["/admin/login", "/admin/logout"]
    else
      _ -> false
    end
  end

  # --- storage ---------------------------------------------------------------

  defp dismissed_list do
    with json when is_binary(json) <- SiteSettings.get_setting(@dismissed),
         {:ok, list} when is_list(list) <- Jason.decode(json) do
      list
    else
      _ -> []
    end
  end

  defp stored do
    with json when is_binary(json) <- SiteSettings.get_setting(@setting),
         {:ok, %{} = map} <- Jason.decode(json) do
      map
    else
      _ -> %{}
    end
  end

  defp figures_for([]), do: %{}

  defp figures_for(hashes) do
    from(h in Hit,
      where: h.ip_hash in ^hashes,
      group_by: h.ip_hash,
      select:
        {h.ip_hash, count(h.id), count(fragment("DISTINCT date(?)", h.inserted_at)),
         count(fragment("DISTINCT ?", h.path)), min(h.inserted_at), max(h.inserted_at)}
    )
    |> Repo.all()
    |> Map.new(fn {hash, hits, days, pages, first, last} ->
      {hash, %{hits: hits, days: days, pages: pages, first_seen: first, last_seen: last}}
    end)
    |> merge_devices(hashes)
  end

  # The browsers the visits were made with, against the one that signed in.
  # Where they disagree, the address was the author's once and is being read by someone
  # else now — which is the whole reason this is a proposal.
  defp merge_devices(figures, hashes) do
    devices =
      from(h in Hit,
        where: h.ip_hash in ^hashes and not is_nil(h.user_agent),
        distinct: true,
        select: {h.ip_hash, h.user_agent}
      )
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Map.new(fn {hash, agents} ->
        {hash, agents |> Enum.map(&Analytics.friendly_device/1) |> Enum.uniq()}
      end)

    Map.new(figures, fn {hash, figure} ->
      {hash, Map.put(figure, :devices, Map.get(devices, hash, []))}
    end)
  end

  defp plain_address?(entry) do
    entry != "" and not String.contains?(entry, "/") and not String.contains?(entry, "*") and
      match?({:ok, _}, :inet.parse_address(String.to_charlist(entry)))
  end

  defp drop_nils(map), do: for({k, v} <- map, not is_nil(v), into: %{}, do: {k, v})
end
