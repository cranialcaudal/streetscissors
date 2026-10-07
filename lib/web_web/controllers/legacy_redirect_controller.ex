defmodule WebWeb.LegacyRedirectController do
  @moduledoc """
  Permanent redirects for retired URL spaces: the manuscripts section
  (merged into /blog), the old fitness blog / regimen paths (merged into the
  /fitness landing), `/audio` (the captain's logs became their own
  section at /logs when spoken work was split out of the blog), and `/faith`
  (the prayer pages, renamed /Christ).
  """

  use WebWeb, :controller

  def audio(conn, _params), do: moved(conn, ~p"/logs")

  # The admin's single ingestion hub split into one manager per section.
  def admin_content(conn, _params), do: moved(conn, ~p"/admin/blog")

  def manuscripts_index(conn, _params), do: moved(conn, ~p"/blog")

  def manuscripts_category(conn, _params), do: moved(conn, ~p"/blog")

  # The blog lived at /manuscripts/latent-sensus before the rename —
  # preserve deep links to posts.
  def manuscripts_show(conn, %{"category" => "latent-sensus", "slug" => slug}),
    do: moved(conn, "/blog/#{slug}")

  def manuscripts_show(conn, _params), do: moved(conn, ~p"/blog")

  # Audio never belonged to a post; spoken work is its own section now.
  def manuscripts_audio(conn, _params), do: moved(conn, ~p"/logs")

  def fitness_regimen(conn, _params), do: moved(conn, ~p"/fitness")

  def fitness_slug(conn, _params), do: moved(conn, ~p"/fitness")

  # The prayer pages moved from /faith to /Christ before they were published;
  # /christ is the same address as a hand types it.
  def christ(conn, %{"rest" => rest}) do
    path =
      Enum.join(
        ["/Christ" | Enum.map(rest, &URI.encode(&1, fn c -> URI.char_unreserved?(c) end))],
        "/"
      )

    moved(conn, if(conn.query_string == "", do: path, else: path <> "?" <> conn.query_string))
  end

  defp moved(conn, to) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: to)
  end
end
