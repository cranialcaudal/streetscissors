defmodule WebWeb.WebmentionController do
  @moduledoc """
  `POST /webmention` — where another site tells this one it has linked to a
  piece (`Web.Webmentions`). Advertised by `<link rel="webmention">` in every
  page's head.

  It runs outside `:browser`: the sender is a server, with no session and no
  CSRF token, and nothing it sends is trusted — the mention is only stored as
  `pending` and verified by fetching the source, then shown only once the
  author approves it. A per-IP limit stops the endpoint being used to make
  this machine fetch URLs in bulk.
  """

  use WebWeb, :controller

  @limit 20
  @window :timer.hours(1)

  def create(conn, params) do
    ip = WebWeb.ClientIP.from_conn(conn)

    with {:ok, _remaining} <-
           Web.RateLimit.hit("webmention:#{ip}", limit: @limit, window: @window),
         {:ok, _mention} <-
           Web.Webmentions.receive(params["source"], params["target"], our_host()) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(202, "Accepted. The source will be checked for a link to the target.\n")
    else
      {:error, :rate_limited, retry_after} ->
        conn
        |> put_resp_header("retry-after", to_string(retry_after))
        |> put_resp_content_type("text/plain")
        |> send_resp(429, "Too many webmentions from this address.\n")

      {:error, reason} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(400, message(reason) <> "\n")
    end
  end

  defp our_host, do: URI.parse(WebWeb.SEO.base_url()).host

  defp message(:not_a_web_url), do: "source and target must both be http(s) URLs."
  defp message(:target_not_ours), do: "target is not on this site."
  defp message(:source_is_ours), do: "source is on this site."
  defp message(:unknown_target), do: "target is not a post, log or frame here."
  defp message(%Ecto.Changeset{}), do: "that mention could not be stored."
  defp message(_), do: "that mention was refused."
end
