defmodule WebWeb.FeedController do
  use WebWeb, :controller

  def index(conn, _params) do
    # Get all manuscripts across main writing categories, sorted by date
    posts =
      ["fiction", "reflections", "sensus"]
      |> Enum.flat_map(fn category ->
        Web.Manuscripts.list_files(category)
        |> Enum.map(fn file ->
          Map.put(file, :category, category)
        end)
      end)
      |> Enum.sort_by(& &1.mtime, {:desc, NaiveDateTime})
      |> Enum.take(20)

    xml = generate_feed(posts)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  defp generate_feed(posts) do
    items = Enum.map(posts, &generate_item/1) |> Enum.join("\n")

    """
    <?xml version="1.0" encoding="UTF-8" ?>
    <rss version="2.0">
    <channel>
      <title>Street Scissors</title>
      <description>The Latent Sensus of The World</description>
      <link>http://streetscissors.com</link>
      <lastBuildDate>#{current_date_rfc822()}</lastBuildDate>
      <pubDate>#{current_date_rfc822()}</pubDate>
      <ttl>1800</ttl>

      #{items}
    </channel>
    </rss>
    """
  end

  defp generate_item(post) do
    url = "https://streetscissors.com/manuscripts/#{post.category}/#{post.slug}"
    desc = get_description(post.category, post.slug)

    """
    <item>
      <title>#{escape_xml(post.title)}</title>
      <description>#{escape_xml(desc)}</description>
      <link>#{url}</link>
      <guid isPermaLink="true">#{url}</guid>
      <pubDate>#{date_to_rfc822(post.mtime)}</pubDate>
    </item>
    """
  end

  defp get_description(category, slug) do
    case Web.Manuscripts.get_manuscript(category, slug) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(fn line ->
          line == "" or String.starts_with?(line, "#")
        end)
        |> List.first("")
        |> String.slice(0, 300)

      _ ->
        ""
    end
  end

  defp escape_xml(nil), do: ""

  defp escape_xml(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp current_date_rfc822 do
    date_to_rfc822(NaiveDateTime.utc_now())
  end

  defp date_to_rfc822(naive) do
    Calendar.strftime(naive, "%a, %d %b %Y %H:%M:%S GMT")
  end
end
