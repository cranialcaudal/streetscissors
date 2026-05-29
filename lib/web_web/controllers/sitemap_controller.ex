defmodule WebWeb.SitemapController do
  use WebWeb, :controller

  def index(conn, _params) do
    # Define your routes to include
    static_pages = ["", "audio", "images", "manuscripts", "about"]
    # In production, this should come from your Endpoint config or specific env var
    # But for sitemap.xml it's often safer to hardcode or strictly control the canonical domain
    base_url = "http://streetscissors.com"

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      #{Enum.map(static_pages, fn page ->
      path = if page == "", do: "", else: "/#{page}"
      """
      <url>
        <loc>#{base_url}#{path}</loc>
        <lastmod>#{Date.to_string(Date.utc_today())}</lastmod>
        <changefreq>weekly</changefreq>
        <priority>#{if page == "", do: "1.0", else: "0.8"}</priority>
      </url>
      """
    end) |> Enum.join("")}
    </urlset>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end
end
