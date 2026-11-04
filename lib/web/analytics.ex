defmodule Web.Analytics do
  @moduledoc """
  Counting visits without keeping who made them. Every browser request records
  a hit (`WebWeb.Plugs.Analytics`): the path, the user agent and a **hash** of
  the IP address, keyed with a secret derived from `SECRET_KEY_BASE` (`hash_ip/1`), so it
  cannot be turned back into an address.
  Bots, prefetches, the author's own reading (`Web.Analytics.Owner`, and
  `WebWeb.OwnerMark` on the browser) and the addresses in `EXCLUDED_IPS` are
  not counted.

  The rest of the module answers questions about those hits, with one
  vocabulary everywhere:

    * **a view** is a hit: one page load (or one shown prefetch, `/seen`);
    * **a visitor** is a distinct `ip_hash`, counted once per page however
      the page's address was spelled: paths are percent-decoded and their
      query dropped, and the visitors of every spelling are *unioned*, never
      summed, so one reader at two spellings is one (`visitors_by_page/2`);
    * **a day** starts at Pacific midnight (`Web.Clock`), so a window of
      days is whole local days (`day_start_utc/1`).

  Post "witnessed" counts are visitors, all time. Captain's logs count
  *views* of their own kind (`Web.Logs`'s plays), which is a different
  measure and is labelled so.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Web.Repo
  alias Web.Analytics.{AccessLog, Hit, Owner, PageWitness}

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
  @bot_ua ~r/bot\b|bots?\/|crawler|spider|scrape|headless|phantomjs|\+http|curl\/|wget\/|python[-\/]|aiohttp|httpx|scrapy|libwww|okhttp|java\/|go-http|node-fetch|axios|feedparser|simplepie|facebookexternalhit|meta-external|bytespider|bytedance|baiduspider|yandexbot|amazonbot|applebot|sogou|google-inspectiontool|selenium|playwright|puppeteer|slurp|bingpreview|semrush|ahrefs|serpstat|dataprovider|petalsearch|archive\.org|censys|leakix|internet-measurement|paloaltonetworks|palo alto networks/i

  def bot_user_agent?(nil), do: false
  def bot_user_agent?(ua) when is_binary(ua), do: Regex.match?(@bot_ua, ua)

  @doc """
  Whether a path is a sub-resource of a page rather than a page view.

  Static files never reach the analytics plug (the endpoint's `Plug.Static`
  halts first), but contact-sheet scans and ride thumbnails are served by
  controllers, so every photo on a negatives page was landing in the table as
  its own "visit".

  `/negatives/frame` covers both the downscaled print and the original
  download. A frame's *page* is `/negatives/roll/:roll/frame/:n`, which this
  does not match, so real visits to a photograph are still counted.
  """
  def sub_resource_path?(path) when is_binary(path) do
    String.starts_with?(path, [
      "/negatives/image",
      "/negatives/preview",
      "/negatives/frame"
    ]) or
      String.ends_with?(path, "/thumb")
  end

  def record_hit(path, user_agent, ip_hash, referrer \\ nil) do
    %Hit{}
    |> Hit.changeset(%{
      path: path,
      user_agent: user_agent,
      ip_hash: ip_hash,
      referrer: referrer
    })
    |> Repo.insert()
  end

  # Every figure the site reports leaves the author's own reading out, and it
  # is left out here rather than at each caller so that a count added later
  # cannot quietly start including him. His visits are not deleted: the rows
  # stay, and `/admin/readers` shows them under "Mine".
  #
  # The set is a handful of hashes held in :persistent_term, so this costs a
  # list of bound parameters and no query of its own.
  defp countable(query) do
    case Owner.hash_list() do
      [] -> query
      hashes -> from(r in query, where: r.ip_hash not in ^hashes)
    end
  end

  @doc "Distinct human readers per post slug, combining /blog and legacy /manuscripts paths."
  def post_readers do
    Map.merge(
      visitors_by_prefix("/manuscripts/latent-sensus/%"),
      visitors_by_prefix("/blog/%"),
      fn _slug, old, new -> MapSet.union(old, new) end
    )
    |> Enum.reduce(%{}, fn {slug, visitors}, acc ->
      clean = Web.Keywords.slugify(slug)
      Map.update(acc, clean, visitors, &MapSet.union(&1, visitors))
    end)
    |> Map.new(fn {slug, visitors} -> {slug, MapSet.size(visitors)} end)
  end

  @doc "The most recent distinct reader hits with parsed device and referrer."
  def recent_readers(limit \\ 15) do
    from(h in Hit,
      where: not is_nil(h.ip_hash),
      order_by: [desc: h.id],
      limit: ^limit,
      select: %{
        id: h.id,
        path: h.path,
        user_agent: h.user_agent,
        ip_hash: h.ip_hash,
        referrer: h.referrer,
        at: h.inserted_at
      }
    )
    |> countable()
    |> Repo.all()
    |> Enum.map(fn hit ->
      %{
        id: hit.id,
        path: page(hit.path),
        badge: String.slice(hit.ip_hash, 0, 6),
        device: friendly_device(hit.user_agent),
        source: friendly_source(hit.referrer),
        at: hit.at
      }
    end)
  end

  @doc "Parses a user-agent string into a concise device/browser name."
  def friendly_device(nil), do: "Browser"

  def friendly_device(ua) when is_binary(ua) do
    cond do
      String.contains?(ua, "iPhone") -> "iPhone"
      String.contains?(ua, "iPad") -> "iPad"
      String.contains?(ua, "Android") -> "Android"
      String.contains?(ua, "CrOS") -> "Chromebook"
      String.contains?(ua, "Macintosh") or String.contains?(ua, "Mac OS") -> "Mac"
      String.contains?(ua, "Windows") -> "Windows"
      String.contains?(ua, "Linux") -> "Linux"
      true -> "Browser"
    end
  end

  @doc "Parses a referrer host/domain into a friendly source name."
  def friendly_source(nil), do: "Direct"
  def friendly_source(""), do: "Direct"

  def friendly_source(host) when is_binary(host) do
    cond do
      String.contains?(host, "google") ->
        "Google"

      String.contains?(host, "duckduckgo") ->
        "DuckDuckGo"

      String.contains?(host, "bing") ->
        "Bing"

      String.contains?(host, "ycombinator") ->
        "Hacker News"

      String.contains?(host, "reddit") ->
        "Reddit"

      String.contains?(host, "t.co") or String.contains?(host, "twitter") or
          String.contains?(host, "x.com") ->
        "X / Twitter"

      String.contains?(host, "substack") ->
        "Substack"

      String.contains?(host, "github") ->
        "GitHub"

      true ->
        host
    end
  end

  @doc """
  Aggregates the top visitors from `analytics_hits` and resolves or guesses
  each visitor's geographic location and reading profile.

  Locations come from two sources:
    * `:geo` — matched against recent Caddy access logs (by hashing `client_ip`
      in memory) and resolved to city, region, country, and ISP in
      `reader_geo_cache.json` without storing raw IPs in the database;
    * `:inferred` — when a visitor predates the current access log window,
      estimated from their UTC active-hour timezone pattern and whether they
      read the author's local pages (training days and rides).
  """
  def top_readers(opts \\ []) do
    min_hits = Keyword.get(opts, :min_hits, 2)
    limit = Keyword.get(opts, :limit, 60)
    filter = Keyword.get(opts, :filter, :readers)
    geo_cache = Keyword.get_lazy(opts, :geo_cache, &load_geo_cache/0)

    from(h in Hit,
      where: not is_nil(h.ip_hash),
      select: {h.ip_hash, h.path, h.user_agent, h.referrer, h.inserted_at}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.reduce([], fn {ip_hash, rows}, acc ->
      total_hits = length(rows)

      if total_hits >= min_hits do
        [build_reader_profile(ip_hash, rows, total_hits, geo_cache) | acc]
      else
        acc
      end
    end)
    |> Enum.filter(fn r ->
      case filter do
        # The author is neither a reader nor a bot: he is his own view, and he
        # is taken out before the others are counted or cut off.
        :readers -> not r.mine? and not r.bot_burst?
        :bots -> not r.mine? and r.bot_burst?
        :mine -> r.mine?
        _ -> true
      end
    end)
    |> Enum.sort_by(fn r -> {-r.total_hits, -r.active_days, r.ip_hash} end)
    |> cut(limit)
  end

  # The cut comes after the filter, never before. Until 2026-10-31 the page
  # asked for the top 150 of everything and sorted readers out afterwards, so
  # one scraper on 276 addresses pushed every real reader off the list.
  defp cut(profiles, nil), do: profiles
  defp cut(profiles, limit), do: Enum.take(profiles, limit)

  @doc "Removes all hits for a given `ip_hash` (e.g. an author IP or bot burst)."
  def forget_reader(ip_hash) when is_binary(ip_hash) do
    from(h in Hit, where: h.ip_hash == ^ip_hash)
    |> Repo.delete_all()
  end

  @doc "Loads the cached `ip_hash => geo_map` resolved from access logs."
  def load_geo_cache do
    path = geo_cache_path()

    with true <- is_binary(path) and File.regular?(path),
         {:ok, body} <- File.read(path),
         {:ok, map} when is_map(map) <- Jason.decode(body) do
      map
    else
      _ -> %{}
    end
  end

  @doc """
  Scans Caddy access logs in memory, matches `client_ip` hashes against top
  database visitors, resolves missing locations via ip-api batch lookup, and
  updates `reader_geo_cache.json`.
  """
  def refresh_geo_cache do
    cache = load_geo_cache()
    hash_to_ip = scan_caddy_logs_for_ips()

    top_hashes =
      from(h in Hit,
        where: not is_nil(h.ip_hash),
        group_by: h.ip_hash,
        order_by: [desc: count(h.id)],
        limit: 500,
        select: h.ip_hash
      )
      |> Repo.all()

    missing =
      for h <- top_hashes,
          not Map.has_key?(cache, h),
          ip = Map.get(hash_to_ip, h),
          not is_nil(ip),
          into: %{},
          do: {h, ip}

    if map_size(missing) == 0 or not Application.get_env(:web, :geo_lookup_enabled, true) do
      {:ok, 0}
    else
      unique_ips = missing |> Map.values() |> Enum.uniq() |> Enum.take(100)

      payload =
        Enum.map(unique_ips, fn ip ->
          %{
            query: ip,
            fields: "status,query,country,regionName,city,isp,org,as,asname,hosting,proxy,mobile"
          }
        end)

      case Req.post("http://ip-api.com/batch", json: payload, receive_timeout: 8_000) do
        {:ok, %Req.Response{status: 200, body: results}} when is_list(results) ->
          ip_geo =
            for %{"status" => "success", "query" => ip} = item <- results, into: %{} do
              {ip,
               %{
                 "city" => item["city"] || "",
                 "region" => item["regionName"] || "",
                 "country" => item["country"] || "",
                 "isp" => item["isp"] || "",
                 "org" => item["org"] || "",
                 "as" => item["as"] || "",
                 "asname" => item["asname"] || "",
                 "hosting" => item["hosting"] == true,
                 "proxy" => item["proxy"] == true,
                 "mobile" => item["mobile"] == true
               }}
            end

          added =
            for {h, ip} <- missing, geo = Map.get(ip_geo, ip), not is_nil(geo), into: %{} do
              {h, geo}
            end

          merged = Map.merge(cache, added)
          save_geo_cache(merged)
          {:ok, map_size(added)}

        _ ->
          {:error, :lookup_failed}
      end
    end
  end

  defp geo_cache_path do
    Application.get_env(
      :web,
      :reader_geo_cache_path,
      Path.expand("~/streetscissors-data/logs/reader_geo_cache.json")
    )
  end

  defp save_geo_cache(map) do
    case geo_cache_path() do
      path when is_binary(path) ->
        File.mkdir_p(Path.dirname(path))
        File.write(path, Jason.encode!(map, pretty: true))

      _ ->
        :ok
    end
  end

  # `Web.Analytics.AccessLog` reads the gzipped rotations as well as the live
  # file. That is the difference between five days of resolvable locations and
  # seventy-eight: the glob here used to end in `.log`, which matches the live
  # file and none of the rotations, so almost every visitor older than a few
  # days fell through to a guess.
  defp scan_caddy_logs_for_ips do
    AccessLog.reduce_lines(%{}, fn line, map ->
      case Regex.run(~r/"client_ip"\s*:\s*"([^"]+)"/, line) do
        [_, ip] when ip not in ["127.0.0.1", "::1"] ->
          Map.put_new(map, hash_ip(ip), ip)

        _ ->
          map
      end
    end)
  end

  defp build_reader_profile(ip_hash, rows, total_hits, geo_cache) do
    timestamps = Enum.map(rows, &elem(&1, 4))
    first_seen = Enum.min(timestamps, NaiveDateTime)
    last_seen = Enum.max(timestamps, NaiveDateTime)

    active_days =
      timestamps
      |> Enum.map(fn ts ->
        ts |> DateTime.from_naive!("Etc/UTC") |> Web.Clock.local_today()
      end)
      |> MapSet.new()
      |> MapSet.size()

    page_counts = Enum.frequencies_by(rows, fn {_, path, _, _, _} -> page(path) end)
    distinct_pages = map_size(page_counts)

    top_pages =
      page_counts
      |> Enum.sort_by(fn {p, c} -> {-c, p} end)
      |> Enum.take(5)

    devices =
      rows
      |> Enum.map(&elem(&1, 2))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&friendly_device/1)
      |> Enum.uniq()

    sources =
      rows
      |> Enum.map(&elem(&1, 3))
      |> Enum.map(&friendly_source/1)
      |> Enum.uniq()

    location = resolve_or_guess_location(ip_hash, geo_cache, timestamps, page_counts)
    mine? = Owner.mine?(ip_hash)
    span_seconds = NaiveDateTime.diff(last_seen, first_seen, :second)

    bot_burst? =
      (active_days == 1 and total_hits >= 25 and span_seconds <= 600) or
        (active_days == 1 and total_hits >= 30 and distinct_pages <= 2) or
        (location.hosting? and active_days == 1)

    %{
      ip_hash: ip_hash,
      badge: String.slice(ip_hash, 0, 6),
      mine?: mine?,
      total_hits: total_hits,
      active_days: active_days,
      distinct_pages: distinct_pages,
      first_seen: first_seen,
      last_seen: last_seen,
      devices: if(devices == [], do: ["Browser"], else: devices),
      sources: if(sources == [], do: ["Direct"], else: sources),
      top_pages: top_pages,
      location: location,
      bot_burst?: bot_burst?
    }
  end

  defp resolve_or_guess_location(ip_hash, geo_cache, timestamps, page_counts) do
    case Map.get(geo_cache, ip_hash) do
      %{} = geo ->
        city = geo["city"] || ""
        region = geo["region"] || ""
        country = geo["country"] || ""

        label =
          [city, region, country]
          |> Enum.reject(&(&1 == ""))
          |> Enum.join(", ")

        isp = geo["isp"] || ""
        org = geo["org"] || ""

        detail =
          cond do
            isp != "" and org != "" and isp != org -> "#{isp} (#{org})"
            isp != "" -> isp
            org != "" -> org
            true -> "Matched in access log"
          end

        hosting? = geo["hosting"] == true or datacenter_isp?(detail)

        %{
          kind: :geo,
          label: if(label == "", do: "Unknown location", else: label),
          detail: detail,
          hosting?: hosting?,
          mobile?: geo["mobile"] == true
        }

      nil ->
        guess_location_from_behavior(timestamps, page_counts)
    end
  end

  @datacenter_pattern ~r/ovh|alibaba|amazon|aws|digitalocean|hetzner|fastly|linode|choopa|vultr|microsoft|google cloud|ws telecom|limited network|censys|scaleway|contabo/i

  defp datacenter_isp?(detail) when is_binary(detail),
    do: Regex.match?(@datacenter_pattern, detail)

  defp guess_location_from_behavior(timestamps, page_counts) do
    mean_utc_hour = circular_mean_utc_hour(timestamps)
    local_affinity? = has_local_affinity?(page_counts)
    pt_hour_label = format_pt_hour(mean_utc_hour)

    region =
      cond do
        local_affinity? and (mean_utc_hour in 15..23 or mean_utc_hour in 0..3) ->
          "Near the author (guessed)"

        mean_utc_hour in 19..23 or mean_utc_hour in 0..2 ->
          "US West / Pacific–Mountain (guessed)"

        mean_utc_hour in 15..18 ->
          "US East / Americas (guessed)"

        mean_utc_hour in 9..14 ->
          "Europe / UK (guessed)"

        true ->
          "Asia / Pacific (guessed)"
      end

    detail =
      if local_affinity? do
        "Active ~#{pt_hour_label} PT · reads the local training & ride pages"
      else
        "Active ~#{pt_hour_label} PT · estimated from visit timestamps"
      end

    %{
      kind: :inferred,
      label: region,
      detail: detail,
      hosting?: false,
      mobile?: false
    }
  end

  defp circular_mean_utc_hour([]), do: 21

  defp circular_mean_utc_hour(timestamps) do
    angles =
      Enum.map(timestamps, fn ts ->
        (ts.hour + ts.minute / 60.0) * 2.0 * :math.pi() / 24.0
      end)

    sin_sum = Enum.sum(Enum.map(angles, &:math.sin/1))
    cos_sum = Enum.sum(Enum.map(angles, &:math.cos/1))
    mean_angle = :math.atan2(sin_sum, cos_sum)
    rem(round(mean_angle * 24.0 / (2.0 * :math.pi())) + 24, 24)
  end

  defp format_pt_hour(utc_hour) do
    pt_hour = rem(utc_hour - 7 + 24, 24)

    cond do
      pt_hour == 0 -> "12am"
      pt_hour < 12 -> "#{pt_hour}am"
      pt_hour == 12 -> "12pm"
      true -> "#{pt_hour - 12}pm"
    end
  end

  defp has_local_affinity?(page_counts) do
    Enum.any?(Map.keys(page_counts), fn path ->
      String.starts_with?(path, [
        "/fitness/rides",
        "/food",
        "/fitness/session",
        "/fitness/day",
        "/day/"
      ]) or
        path == "/fitness"
    end)
  end

  # Hits for today (resets at local midnight, DST included — see Web.Clock)
  def count_hits_today do
    today_start = Web.Clock.local_day_start_utc()

    from(h in Hit,
      where: h.inserted_at >= ^today_start
    )
    |> countable()
    |> Repo.aggregate(:count, :id)
  end

  def count_unique_visitors_today do
    today_start = Web.Clock.local_day_start_utc()

    from(h in Hit,
      where: h.inserted_at >= ^today_start,
      select: count(h.ip_hash, :distinct)
    )
    |> countable()
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
      |> countable()
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

  @doc "The pages most visitors have opened, all time: `[{path, visitors}]`."
  def top_pages(limit \\ 5) do
    nil
    |> visitors_by_page()
    |> Enum.map(fn {path, visitors} -> {path, MapSet.size(visitors)} end)
    |> Enum.sort_by(fn {path, n} -> {-n, path} end)
    |> Enum.take(limit)
  end

  @doc """
  The visitors of each page, as `%{page => MapSet of ip_hash}`: hits whose
  path is `LIKE` one of `patterns` (every hit when nil), since `since` (a UTC
  `NaiveDateTime`, or nil for all time) and, with `before:`, before that. A page is its path decoded and
  without its query, so the spellings of one address share one set.
  """
  def visitors_by_page(patterns, since \\ nil, opts \\ []) do
    query =
      from(h in Hit,
        where: not is_nil(h.ip_hash),
        distinct: true,
        select: {h.path, h.ip_hash}
      )

    query = if since, do: where(query, [h], h.inserted_at >= ^since), else: query

    query =
      case opts[:before] do
        nil -> query
        before -> where(query, [h], h.inserted_at < ^before)
      end

    query =
      case patterns do
        nil ->
          query

        patterns ->
          matches =
            Enum.reduce(patterns, dynamic(false), fn pattern, acc ->
              dynamic([h], ^acc or like(h.path, ^pattern))
            end)

          where(query, ^matches)
      end

    query
    |> countable()
    |> Repo.all()
    |> Enum.reduce(%{}, fn {path, ip_hash}, acc ->
      Map.update(acc, page(path), MapSet.new([ip_hash]), &MapSet.put(&1, ip_hash))
    end)
  end

  @doc "A hit's path as a page: decoded, without its query."
  def page(path), do: path |> String.split("?") |> hd() |> URI.decode()

  @doc "Pacific midnight starting `date`, as a UTC `NaiveDateTime`."
  def day_start_utc(%Date{} = date),
    do: Web.Clock.local_day_start_utc(DateTime.new!(date, ~T[20:00:00], "Etc/UTC"))

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
    prefix
    |> visitors_by_prefix()
    |> Map.new(fn {slug, visitors} -> {slug, MapSet.size(visitors)} end)
  end

  @doc """
  The visitors behind `all_hits_by_prefix/1`, as `%{slug => MapSet of
  ip_hash}`, before they are counted — so a caller merging a post's several
  addresses can union the sets and count one reader once. Readers whose hits
  have been pruned are still here, from `PageWitness`.
  """
  def visitors_by_prefix(prefix) do
    hits =
      from(h in Hit,
        where: like(h.path, ^prefix),
        distinct: true,
        select: {h.path, h.ip_hash}
      )
      |> countable()
      |> Repo.all()

    kept =
      from(w in PageWitness, where: like(w.page, ^prefix), select: {w.page, w.ip_hash})
      |> countable()
      |> Repo.all()

    Enum.reduce(hits ++ kept, %{}, fn {path, ip_hash}, acc ->
      slug = path |> String.split("/") |> List.last() |> URI.decode()
      Map.update(acc, slug, MapSet.new([ip_hash]), &MapSet.put(&1, ip_hash))
    end)
  end

  # How long a hit keeps its user agent (needed only to purge bots that slipped
  # through), how long a hit is kept at all (the dashboard's trend reads 392
  # days), and which pages are counted for all time, so their readers are
  # folded into PageWitness before their hits go.
  @agent_days 30
  @keep_days 400
  @witnessed ["/blog/%", "/manuscripts/latent-sensus/%"]

  @doc """
  Retention, nightly (`Web.Scheduler`): a hit older than #{@agent_days} days
  loses its user agent, and one older than #{@keep_days} days is deleted,
  after a blog page's readers are folded into `PageWitness` so "witnessed"
  stays all-time. `now` is for tests. Returns what was done.
  """
  def prune(now \\ NaiveDateTime.utc_now()) do
    agent_cutoff = NaiveDateTime.add(now, -@agent_days * 86_400)
    keep_cutoff = NaiveDateTime.add(now, -@keep_days * 86_400)

    {anonymised, _} =
      from(h in Hit, where: h.inserted_at < ^agent_cutoff and not is_nil(h.user_agent))
      |> Repo.update_all(set: [user_agent: nil])

    Repo.transaction(fn ->
      stamp = NaiveDateTime.truncate(now, :second)

      # visitors_by_page/3 already leaves the author out, but a witness row is
      # kept for all time and no later pass revisits it, so this is said twice
      # on purpose: it is the one place where getting it wrong is permanent.
      witnesses =
        @witnessed
        |> visitors_by_page(nil, before: keep_cutoff)
        |> Enum.flat_map(fn {page, visitors} ->
          Enum.map(visitors, &%{page: page, ip_hash: &1, inserted_at: stamp})
        end)
        |> Enum.reject(&Owner.mine?(&1.ip_hash))

      witnesses
      |> Enum.chunk_every(500)
      |> Enum.each(&Repo.insert_all(PageWitness, &1, on_conflict: :nothing))

      {deleted, _} = Repo.delete_all(from(h in Hit, where: h.inserted_at < ^keep_cutoff))
      %{anonymised: anonymised, folded: length(witnesses), deleted: deleted}
    end)
  end

  @doc """
  Reader locations, nightly (`Web.Scheduler`): resolve whoever the access log
  still holds and the cache does not, then drop the cache's orphans.

  Its own scheduler entry rather than part of `run_scheduled/0`, so a lookup
  that cannot reach ip-api never stands between the site and its retention.
  """
  def geo_scheduled do
    refresh_geo_cache()
    prune_geo_cache()
    :ok
  rescue
    error ->
      Logger.warning("reader locations could not be refreshed: #{Exception.message(error)}")
      :ok
  end

  @doc """
  Forgets the location of a visitor the site has otherwise forgotten.

  A hit loses its user agent after #{@agent_days} days and is deleted after
  #{@keep_days}, but nothing aged the location cache out, so it became the one
  record of a visitor that outlived every other. An entry is kept while its
  hash is still a visit, or is the author's — not merely because it was once
  looked up.
  """
  def prune_geo_cache do
    cache = load_geo_cache()

    live =
      from(h in Hit, where: not is_nil(h.ip_hash), distinct: true, select: h.ip_hash)
      |> Repo.all()
      |> MapSet.new()
      |> MapSet.union(MapSet.new(Owner.hash_list()))

    kept = for {hash, geo} <- cache, MapSet.member?(live, hash), into: %{}, do: {hash, geo}
    dropped = map_size(cache) - map_size(kept)

    if dropped > 0, do: save_geo_cache(kept)

    {:ok, dropped}
  end

  @doc false
  def run_scheduled, do: prune()

  @doc """
  Forgets every visit. Nothing on the site calls this: it is for the console
  (`bin/web rpc 'Web.Analytics.reset_all_hits()'`), and it cannot be undone
  except from a database snapshot.
  """
  def reset_all_hits do
    Repo.delete_all(Hit)
  end
end
