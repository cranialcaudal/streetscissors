defmodule WebWeb.FeedController do
  use WebWeb, :controller

  @moduledoc """
  RSS 2.0 feed of the whole site — and, with `?keyword=`, of one thread
  through it.

  `/feed` used to carry the blog alone. It now carries the person: posts,
  captain's logs and rolls of film, newest first, so following the site means
  following all of it rather than one of its formats. `/feed?keyword=ferry`
  follows a keyword across the blog and the logs instead of an account —
  the same `?keyword=` the indexes filter on, normalised the same way.

  Log items carry an `<enclosure>` for their media, so a podcast app can
  follow the logs as a show. Descriptions are **excerpts, not full text**, on
  purpose: the piece is read where it lives, whole, beside everything it
  links to.

  Older fixes kept from the blog-only feed:

    * `pubDate` is real UTC with a numeric offset (it once stamped a local
      mtime with the literal "GMT").
    * The channel `<link>` and the item links agree on https.
    * The content type is `application/rss+xml`, with `<atom:link
      rel="self">` and `<language>`.
  """

  alias Web.Audio.Log
  alias Web.Keywords

  @limit 30

  def index(conn, %{"keyword" => raw}) when is_binary(raw) and raw != "" do
    keyword = Keywords.normalize(raw)

    case keyword_items(keyword) do
      [] ->
        send_resp(conn, 404, "No piece carries the keyword #{inspect(keyword)}.")

      items ->
        feed(conn, items,
          title: "streetscissors · #{keyword}",
          description: "Everything at streetscissors filed under #{keyword}",
          self_path: "/feed?" <> URI.encode_query(%{"keyword" => keyword})
        )
    end
  end

  def index(conn, _params) do
    items =
      post_items(Web.Blog.list_posts()) ++ log_items(Web.Audio.list_ready_logs()) ++ roll_items()

    feed(conn, items,
      title: "streetscissors",
      description: "streetscissors — essays, captain's logs and film",
      self_path: "/feed"
    )
  end

  defp keyword_items(keyword) do
    posts = Enum.filter(Web.Blog.list_posts(), &(keyword in &1.keywords))
    logs = Enum.filter(Web.Audio.list_ready_logs(), &(keyword in Log.keyword_list(&1)))
    post_items(posts) ++ log_items(logs)
  end

  defp feed(conn, items, opts) do
    items = items |> Enum.sort_by(& &1.at, {:desc, DateTime}) |> Enum.take(@limit)

    conn
    |> put_resp_content_type("application/rss+xml")
    |> send_resp(200, render_feed(items, opts))
  end

  # --- Items ---
  #
  # Each source becomes %{title, description, path, at, enclosure}; `at` is a
  # UTC DateTime used both to order the merged feed and as the pubDate.

  defp post_items(posts) do
    for post <- posts do
      %{
        title: post.title,
        description: post.excerpt,
        path: "/blog/#{post.slug}",
        at: DateTime.from_naive!(post.mtime, "Etc/UTC"),
        enclosure: nil
      }
    end
  end

  defp log_items(logs) do
    for log <- logs do
      %{
        title: "Captain's log · " <> Log.title(log),
        description: log.caption || log.description || "A #{log.kind} log.",
        path: "/logs/#{log.slug}",
        at: log.recorded_at || noon(log.recorded_on),
        enclosure: enclosure(log)
      }
    end
  end

  defp roll_items do
    for sheet <- Web.Negatives.list_contact_sheets() do
      %{
        title: "Roll #{sheet.roll} · #{sheet.format} #{color(sheet.color)}",
        description: "A contact sheet of roll #{sheet.roll}, scanned #{sheet.date}.",
        path: "/negatives/roll/#{sheet.roll}",
        at: DateTime.from_naive!(sheet.mtime, "Etc/UTC"),
        enclosure: nil
      }
    end
  end

  defp enclosure(%Log{} = log) do
    case Log.media_url(log) do
      nil ->
        nil

      url ->
        type = if Log.video?(log), do: "video/mp4", else: "audio/mp4"
        %{url: WebWeb.SEO.absolute(url), length: log.size_bytes || 0, type: type}
    end
  end

  defp noon(%Date{} = date), do: DateTime.new!(date, ~T[12:00:00], "Etc/UTC")
  defp noon(_), do: DateTime.utc_now()

  defp color("bw"), do: "black and white"
  defp color("color"), do: "colour"
  defp color(other), do: other

  # --- XML ---

  defp render_feed(items, opts) do
    self_url = WebWeb.SEO.absolute(opts[:self_path])

    # Newest item, not "now" — a fetch should not restate the whole feed as
    # freshly built.
    last_build =
      case items do
        [newest | _] -> newest.at
        [] -> DateTime.utc_now()
      end

    """
    <?xml version="1.0" encoding="UTF-8" ?>
    <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
    <channel>
      <title>#{escape_xml(opts[:title])}</title>
      <description>#{escape_xml(opts[:description])}</description>
      <link>#{WebWeb.SEO.base_url()}</link>
      <atom:link href="#{escape_xml(self_url)}" rel="self" type="application/rss+xml" />
      <language>en</language>
      <lastBuildDate>#{to_rfc822(last_build)}</lastBuildDate>
      <ttl>1800</ttl>

      #{Enum.map_join(items, "\n", &render_item/1)}
    </channel>
    </rss>
    """
  end

  defp render_item(item) do
    url = WebWeb.SEO.absolute(item.path)

    """
    <item>
      <title>#{escape_xml(item.title)}</title>
      <description>#{escape_xml(item.description)}</description>
      <link>#{url}</link>
      <guid isPermaLink="true">#{url}</guid>
      <pubDate>#{to_rfc822(item.at)}</pubDate>#{render_enclosure(item.enclosure)}
    </item>
    """
  end

  defp render_enclosure(nil), do: ""

  defp render_enclosure(%{url: url, length: length, type: type}) do
    ~s(\n  <enclosure url="#{escape_xml(url)}" length="#{length}" type="#{type}" />)
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

  defp to_rfc822(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%a, %d %b %Y %H:%M:%S +0000")
  end
end
