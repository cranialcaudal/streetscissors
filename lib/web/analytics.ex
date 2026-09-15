defmodule Web.Analytics do
  import Ecto.Query, warn: false
  alias Web.Repo
  alias Web.Analytics.Hit

  @doc """
  Salted hash of a client IP, for counting a returning visitor as one visitor
  without storing the address.

  The salt matters: an unsalted SHA-256 of an IPv4 address is reversible by
  anyone willing to hash all four billion of them, so the column would still
  be personal data in everything but name. It is derived from
  `secret_key_base` rather than configured separately, so there is no new
  secret to deploy, and it is domain-separated so this hash can't be
  correlated with anything else signed by the same key.

  Changing (or first introducing) the salt re-identifies everyone: old and
  new hashes for the same visitor differ, so a returning visitor counts once
  more than they should, once.
  """
  def hash_ip(ip) when is_binary(ip) do
    :crypto.mac(:hmac, :sha256, ip_salt(), ip) |> Base.encode16()
  end

  defp ip_salt do
    secret =
      Application.get_env(:web, WebWeb.Endpoint)[:secret_key_base] ||
        raise "secret_key_base is unset; analytics IP hashing has no salt"

    :crypto.mac(:hmac, :sha256, secret, "analytics/ip/v1")
  end

  @doc """
  Whether a user agent belongs to a crawler rather than a reader.

  `\\+http` is the load-bearing pattern: well-behaved bots put a contact URL
  in their UA ("compatible; SomeBot/1.0; +https://example.com/bot"), and no
  real browser does, so it catches the long tail of scanners and one-off
  research crawlers without needing a name for each. Checked against every
  distinct UA this site has recorded: no plain-browser string matches.
  """
  @bot_ua ~r/bot\b|bots?\/|crawler|spider|scrape|headless|phantomjs|\+http|curl\/|wget\/|python[-\/]|aiohttp|httpx|scrapy|libwww|okhttp|java\/|go-http|node-fetch|axios|feedparser|simplepie|facebookexternalhit|slurp|bingpreview|semrush|ahrefs|serpstat|dataprovider|petalsearch|archive\.org|censys|leakix|internet-measurement|paloaltonetworks|palo alto networks/i

  def bot_user_agent?(nil), do: false
  def bot_user_agent?(ua) when is_binary(ua), do: Regex.match?(@bot_ua, ua)

  @doc """
  Whether a path is a sub-resource of a page rather than a page view.

  Static files never reach the analytics plug (the endpoint's `Plug.Static`
  halts first), but contact-sheet scans and ride thumbnails are served by
  controllers, so every photo on a negatives page was landing in the table as
  its own "visit".
  """
  def sub_resource_path?(path) when is_binary(path) do
    String.starts_with?(path, ["/negatives/image", "/negatives/preview"]) or
      String.ends_with?(path, "/thumb")
  end

  def record_hit(path, user_agent, ip_hash) do
    %Hit{}
    |> Hit.changeset(%{path: path, user_agent: user_agent, ip_hash: ip_hash})
    |> Repo.insert()
  end

  def list_recent_hits(limit \\ 50) do
    from(h in Hit, order_by: [desc: h.inserted_at], limit: ^limit)
    |> Repo.all()
  end

  # Hits for today (resets at local midnight, DST included — see Web.Clock)
  def count_hits_today do
    today_start = Web.Clock.local_day_start_utc()

    from(h in Hit,
      where: h.inserted_at >= ^today_start
    )
    |> Repo.aggregate(:count, :id)
  end

  def count_unique_visitors_today do
    today_start = Web.Clock.local_day_start_utc()

    from(h in Hit,
      where: h.inserted_at >= ^today_start,
      select: count(h.ip_hash, :distinct)
    )
    |> Repo.one()
  end

  # Returns {total_hits_in_window, trend_data}
  # trend_data is a list of {start_date, count} tuples
  # Bins are consistently aligned to 14-day blocks ending at the next Midnight PST.
  def get_biweekly_trends(bins \\ 28) do
    # Definition: Bin 0 is the "current" 14-day period.
    # It ends at "Tomorrow Midnight PST" (the end of the current day).
    # It starts 14 days before that.

    # 1. Get Today Start (local midnight) in UTC
    today_start_utc = Web.Clock.local_day_start_utc()

    # 2. The end of the current bin is "Tomorrow Midnight PST" (Today Start + 24 hours)
    current_bin_end_utc = NaiveDateTime.add(today_start_utc, 24 * 3600, :second)

    # 3. Create bins
    # We want a list of {start, end, count}
    # We will query the DB for all relevant hits first, then bucket them in Elixir for simplicity/speed (assuming volume is manageable)

    days_back = bins * 14

    total_window_start_utc =
      NaiveDateTime.add(current_bin_end_utc, -days_back * 24 * 3600, :second)

    hits =
      from(h in Hit,
        where: h.inserted_at >= ^total_window_start_utc and h.inserted_at < ^current_bin_end_utc,
        select: h.inserted_at
      )
      |> Repo.all()

    # Initialize bins
    # List of maps or tuples: {bin_index, start_utc, end_utc, count}
    # bin_index 0 = oldest? or newest?
    # Let's produce the output format expected: list of {start_date, count} (maybe start_date in PST for display?)
    # The template expects: {start_date, _end, count}

    # Let's iterate 0..(bins-1). i=0 is the NEWEST bin (current).
    bin_ranges =
      0..(bins - 1)
      |> Enum.map(fn i ->
        bin_end = NaiveDateTime.add(current_bin_end_utc, -i * 14 * 24 * 3600, :second)
        bin_start = NaiveDateTime.add(bin_end, -14 * 24 * 3600, :second)
        {bin_start, bin_end, 0}
      end)
      # Reverse so oldest is first in the list, which is better for iteration if we want chronological
      |> Enum.reverse()

    # Bucket hits
    # Since bin_ranges is ordered Oldest -> Newest, we can efficiently sort hits or just iterate.
    # Given N hits and M bins, O(N*M) is fine for reasonable N.

    filled_bins =
      Enum.reduce(hits, bin_ranges, fn hit_ts, acc ->
        Enum.map(acc, fn {b_start, b_end, c} ->
          if NaiveDateTime.compare(hit_ts, b_start) != :lt and
               NaiveDateTime.compare(hit_ts, b_end) == :lt do
            {b_start, b_end, c + 1}
          else
            {b_start, b_end, c}
          end
        end)
      end)

    # The label is the bin's start date in local time, so it reads as the
    # viewer's date rather than UTC's. Template does
    # `Calendar.strftime(start_date, "%b %d")`, which a Date satisfies.
    final_data =
      Enum.map(filled_bins, fn {utc_start, _utc_end, count} ->
        local_start =
          utc_start |> DateTime.from_naive!("Etc/UTC") |> Web.Clock.local_today()

        # Template uses: {start_date, _end, count}
        {local_start, nil, count}
      end)

    total_in_window = Enum.sum(Enum.map(final_data, fn {_, _, c} -> c end))

    {total_in_window, final_data}
  end

  def count_total_hits do
    # Per user request: All-time hits is the aggregate of the 28 bi-weekly bins
    {total, _} = get_biweekly_trends(28)
    total
  end

  def top_pages(limit \\ 5) do
    from(h in Hit,
      group_by: h.path,
      select: {h.path, count(h.id)},
      order_by: [desc: count(h.id)],
      limit: ^limit
    )
    |> Repo.all()
  end

  def reset_all_hits do
    Repo.delete_all(Hit)
  end

  @doc """
  Distinct visitors per slug, for a path prefix.

  Two things this has to get right, both of which it got wrong before:

    * **Decode the path.** Hits store `conn.request_path`, which is
      percent-encoded, so a post at `/blog/Tide%27s%20Out%2C%20Mostly`
      never matched its own slug ("Tide's Out, Mostly") and every post
      read 0 views. Clients also encode inconsistently (`%27` vs a literal
      `'`), so the same post lands under several paths; decoding collapses
      them onto one slug.

    * **Count visitors, not requests.** `count(id)` counted page loads, so
      one reader refreshing ten times read as ten. Distinct `ip_hash` per
      slug is the honest number, and matches what the header and the admin
      dashboard already report site-wide.

  Distinct `{path, ip_hash}` pairs are grouped in Elixir rather than SQL
  because the decoding SQLite can't do is exactly what merges the path
  variants — summing per-path counts instead would double-count a visitor
  who arrived under two different encodings.
  """
  def all_hits_by_prefix(prefix) do
    from(h in Hit,
      where: like(h.path, ^prefix),
      distinct: true,
      select: {h.path, h.ip_hash}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {path, ip_hash}, acc ->
      slug = path |> String.split("/") |> List.last() |> URI.decode()
      Map.update(acc, slug, MapSet.new([ip_hash]), &MapSet.put(&1, ip_hash))
    end)
    |> Map.new(fn {slug, visitors} -> {slug, MapSet.size(visitors)} end)
  end
end
