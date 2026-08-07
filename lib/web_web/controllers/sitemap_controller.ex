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
    urls = static_urls() ++ blog_urls() ++ log_urls() ++ fitness_urls() ++ ride_urls()

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
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
      {"/fitness/rides", nil, "weekly", "0.6"},
      {"/about", nil, "monthly", "0.7"},
      {"/guestbook", nil, "monthly", "0.4"}
    ]
  end

  # Real dates, so a crawler can trust the field.
  defp blog_urls do
    Enum.map(Web.Blog.list_posts(), fn post ->
      {"/blog/#{post.slug}", post.date, "monthly", "0.8"}
    end)
  end

  defp log_urls do
    Enum.map(Web.Audio.list_published_logs(), fn log ->
      {"/logs/#{log.slug}", log.recorded_on, "monthly", "0.8"}
    end)
  end

  defp fitness_urls do
    Enum.map(Web.Fitness.Vault.list_all_exercises(), fn exercise ->
      {"/fitness/wiki/#{exercise.slug}", nil, "monthly", "0.4"}
    end)
  rescue
    # The wiki reads a markdown vault off disk; a missing one must not 500 the
    # sitemap and take every other URL with it.
    _ -> []
  end

  defp ride_urls do
    Enum.map(Web.Rides.list_recorded_rides(), fn ride ->
      {"/fitness/rides/#{ride.id}", nil, "yearly", "0.3"}
    end)
  rescue
    _ -> []
  end

  defp entry({path, lastmod, changefreq, priority}) do
    """
      <url>
        <loc>#{WebWeb.SEO.absolute(path)}</loc>#{lastmod_tag(lastmod)}
        <changefreq>#{changefreq}</changefreq>
        <priority>#{priority}</priority>
      </url>
    """
  end

  defp lastmod_tag(nil), do: ""
  defp lastmod_tag(%Date{} = date), do: "\n    <lastmod>#{Date.to_iso8601(date)}</lastmod>"
end
