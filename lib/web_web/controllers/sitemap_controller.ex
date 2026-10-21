defmodule WebWeb.SitemapController do
  use WebWeb, :controller

  @moduledoc """
  XML sitemap.

  Previously this hardcoded `http://streetscissors.com` — search engines treat
  http and https as separate sites, so every entry pointed at the pre-redirect
  URL — stamped `lastmod` as "today" on every fetch (which teaches a crawler to
  ignore the field), and listed only 7 static paths, omitting the wiki, rides,
  individually addressable negative frames and the logs.

  The host now comes from the endpoint config, so it follows PHX_HOST and the
  https scheme rather than being restated here.
  """

  def index(conn, _params) do
    urls =
      static_urls() ++
        blog_urls() ++
        log_urls() ++ fitness_urls() ++ ride_urls() ++ negatives_urls() ++ daybook_urls()

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
    #{Enum.map_join(urls, "", &entry/1)}</urlset>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  # {path, lastmod, changefreq, priority}
  defp static_urls do
    [
      {"/", nil, "weekly", "1.0"},
      {"/blog", nil, "weekly", "0.9"},
      {"/logs", nil, "weekly", "0.9"},
      {"/negatives", nil, "weekly", "0.8"},
      {"/fitness", nil, "weekly", "0.7"},
      {"/fitness/wiki", nil, "monthly", "0.6"},
      # /food and /england2026 are deliberately absent — both are unlisted.
      {"/fitness/rides", nil, "weekly", "0.6"},
      {"/about", nil, "monthly", "0.7"},
      {"/how-to", nil, "monthly", "0.6"},
      {"/roadmap", nil, "monthly", "0.6"},
      {"/guestbook", nil, "monthly", "0.4"}
    ]
  end

  # Real dates, so a crawler can trust the field. The post's own date, not
  # its file's time: a copy or a checkout makes every file "changed today".
  defp blog_urls do
    Enum.map(Web.Blog.list_posts(), fn post ->
      {"/blog/#{post.slug}", post.date, "monthly", "0.8"}
    end)
  end

  defp log_urls do
    Enum.map(Web.Logs.list_ready_logs(), fn log ->
      {"/logs/#{log.slug}", log.recorded_on, "monthly", "0.8"}
    end)
  end

  # The wiki comes back grouped, `[{group, exercises}]`. Reading it as a flat
  # list raised on the first group, the rescue below caught it, and no wiki
  # page was ever listed.
  defp fitness_urls do
    wiki = Path.join(Web.Fitness.Vault.base_path(), "exercise-wiki")

    for {group, exercises} <- Web.Fitness.Vault.list_all_exercises(), exercise <- exercises do
      path = Path.join([wiki, group, exercise.slug <> ".md"])
      {"/fitness/wiki/#{exercise.slug}", file_date(path), "monthly", "0.4"}
    end
  rescue
    # The wiki reads a markdown vault off disk; a missing one must not 500 the
    # sitemap and take every other URL with it.
    _ -> []
  end

  # This week, then every year, week and day with work in it — and only those: an empty day
  # is a 404, so listing it would send crawlers to a dead end.
  defp daybook_urls do
    entries = Web.Daybook.entries()

    years =
      Enum.map(Web.Daybook.years(entries), fn year ->
        {"/daybook/#{year}", nil, "monthly", "0.5"}
      end)

    days =
      entries
      |> Enum.map(& &1.date)
      |> Enum.uniq()
      |> Enum.map(&{"/day/#{Date.to_iso8601(&1)}", &1, "yearly", "0.3"})

    weeks =
      entries
      |> Enum.map(&Web.Daybook.week_path(&1.date))
      |> Enum.uniq()
      |> Enum.map(&{&1, nil, "yearly", "0.3"})

    [{"/daybook", nil, "weekly", "0.5"}] ++ years ++ weeks ++ days
  rescue
    _ -> []
  end

  defp ride_urls do
    Enum.map(Web.Rides.list_rides(), fn ride ->
      {"/fitness/rides/#{ride.id}", nil, "yearly", "0.3"}
    end)
  rescue
    _ -> []
  end

  # A roll and each of its printed frames are separately addressable, so both
  # are listed. Built as strings rather than ~p sigils, which means the
  # compiler will not catch a route change here — the test below is what does.
  # Each carries its picture (the sheet, or the print), since the picture is
  # what the page is; the roll's date is when it was scanned.
  defp negatives_urls do
    Enum.flat_map(Web.Negatives.list_contact_sheets(), fn sheet ->
      roll = WebWeb.NegativesLive.Format.pad(sheet.roll)
      scanned = iso_date(sheet.date)

      frames =
        Enum.map(Web.Negatives.list_frames(sheet.roll), fn frame ->
          {"/negatives/roll/#{roll}/frame/#{frame.frame}", scanned, "yearly", "0.5", frame.url}
        end)

      [{"/negatives/roll/#{roll}", scanned, "monthly", "0.6", sheet.preview_url} | frames]
    end)
  rescue
    # Reads the archive off disk; a bad roll folder must not 500 the sitemap.
    _ -> []
  end

  defp entry({path, lastmod, changefreq, priority}),
    do: entry({path, lastmod, changefreq, priority, nil})

  defp entry({path, lastmod, changefreq, priority, image}) do
    """
      <url>
        <loc>#{WebWeb.SEO.absolute(path)}</loc>#{lastmod_tag(lastmod)}
        <changefreq>#{changefreq}</changefreq>
        <priority>#{priority}</priority>#{image_tag(image)}
      </url>
    """
  end

  defp image_tag(nil), do: ""

  defp image_tag(url) do
    loc =
      url |> WebWeb.SEO.absolute() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

    "\n    <image:image><image:loc>#{loc}</image:loc></image:image>"
  end

  defp file_date(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} -> mtime |> NaiveDateTime.from_erl!() |> NaiveDateTime.to_date()
      _ -> nil
    end
  end

  defp file_date(_path), do: nil

  defp iso_date("" <> text) do
    case Date.from_iso8601(text) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp iso_date(_), do: nil

  defp lastmod_tag(nil), do: ""
  defp lastmod_tag(%Date{} = date), do: "\n    <lastmod>#{Date.to_iso8601(date)}</lastmod>"
end
