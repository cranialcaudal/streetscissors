defmodule Web.Analytics do
  import Ecto.Query, warn: false
  alias Web.Repo
  alias Web.Analytics.Hit

  # Constants
  @pst_offset -8

  def record_hit(path, user_agent, ip_hash) do
    %Hit{}
    |> Hit.changeset(%{path: path, user_agent: user_agent, ip_hash: ip_hash})
    |> Repo.insert()
  end

  def list_recent_hits(limit \\ 50) do
    from(h in Hit, order_by: [desc: h.inserted_at], limit: ^limit)
    |> Repo.all()
  end

  # Hits for today (resets at midnight PST)
  def count_hits_today do
    today_start_pst = get_today_start_pst_utc()

    from(h in Hit,
      where: h.inserted_at >= ^today_start_pst
    )
    |> Repo.aggregate(:count, :id)
  end

  def count_unique_visitors_today do
    today_start_pst = get_today_start_pst_utc()

    from(h in Hit,
      where: h.inserted_at >= ^today_start_pst,
      select: count(h.ip_hash, :distinct)
    )
    |> Repo.one()
  end

  # Returns the UTC NaiveDateTime corresponding to the start of the current day in PST.
  # So if it is 10:00 PM UTC (2:00 PM PST) on Jan 10, this returns Jan 10 00:00:00 PST converted to UTC (Jan 10 08:00:00 UTC).
  defp get_today_start_pst_utc do
    utc_now = NaiveDateTime.utc_now()

    # 1. Convert UTC now to PST now
    pst_now = NaiveDateTime.add(utc_now, @pst_offset * 3600, :second)

    # 2. Truncate to beginning of day (Midnight PST)
    pst_midnight = NaiveDateTime.beginning_of_day(pst_now)

    # 3. Convert back to UTC for the database query
    NaiveDateTime.add(pst_midnight, -@pst_offset * 3600, :second)
  end

  # Returns {total_hits_in_window, trend_data}
  # trend_data is a list of {start_date, count} tuples
  # Bins are consistently aligned to 14-day blocks ending at the next Midnight PST.
  def get_biweekly_trends(bins \\ 28) do
    # Definition: Bin 0 is the "current" 14-day period.
    # It ends at "Tomorrow Midnight PST" (the end of the current day).
    # It starts 14 days before that.

    # 1. Get Today Start (Midnight PST) in UTC
    today_start_utc = get_today_start_pst_utc()

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

    # The output needs to provide "start_date" for the label.
    # The template does: `Calendar.strftime(start_date, "%b %d")`
    # We should probably pass the PST start date so the label matches the user's timezone expectation.
    final_data =
      Enum.map(filled_bins, fn {utc_start, _utc_end, count} ->
        # Convert UTC start back to PST for display
        pst_start = NaiveDateTime.add(utc_start, @pst_offset * 3600, :second)

        # We also need the end date if the template uses it, but it filters unused variables usually.
        # Template uses: {start_date, _end, count}
        {pst_start, nil, count}
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

  def top_manuscripts(category, limit \\ 7) do
    prefix = "/manuscripts/#{category}/%"

    from(h in Hit,
      where: like(h.path, ^prefix),
      group_by: h.path,
      select: {h.path, count(h.id)},
      order_by: [desc: count(h.id)],
      limit: ^limit
    )
    |> Repo.all()
    |> Enum.map(fn {path, count} ->
      slug = path |> String.split("/") |> List.last()
      {slug, count}
    end)
  end

  def all_hits_by_prefix(prefix) do
    from(h in Hit,
      where: like(h.path, ^prefix),
      group_by: h.path,
      select: {h.path, count(h.id)}
    )
    |> Repo.all()
    |> Map.new(fn {path, count} ->
      slug = path |> String.split("/") |> List.last()
      {slug, count}
    end)
  end
end
