defmodule Web.IndexNow do
  @moduledoc """
  Tells search engines which address changed, the moment it does, by
  IndexNow (one ping reaches Bing, Yandex, Seznam and the others that share
  it), instead of waiting for the next crawl of the sitemap.

  Off unless `INDEXNOW_KEY` is set (`config :web, :indexnow_key`). The key is
  served at `/indexnow.txt` (`WebWeb.IndexNowController`) and named in each
  ping as `keyLocation`, which is how the engines know the ping is the
  site's own. A ping is an Oban job (`Web.Workers.IndexNowPing`), so a slow
  answer never holds up a save.

  Called when a post is saved published (`Web.Blog.write_source/4`), a log is
  published (`Web.Logs`) and a roll is published
  (`Web.Scanner.Pipeline.publish_roll/4`).
  """

  @endpoint "https://api.indexnow.org/indexnow"

  @doc "The key, or nil when IndexNow is off."
  def key do
    case Application.get_env(:web, :indexnow_key) do
      "" <> key when key != "" -> key
      _ -> nil
    end
  end

  @doc "Queues a ping for `paths` (site paths like `/blog/a-post`). Nothing when off."
  def changed(paths) when is_list(paths) do
    if key() && paths != [] do
      %{"paths" => paths} |> Web.Workers.IndexNowPing.new() |> Oban.insert()
    end

    :ok
  end

  def changed(path) when is_binary(path), do: changed([path])

  @doc false
  def ping(paths) do
    base = WebWeb.SEO.base_url()

    body = %{
      host: URI.parse(base).host,
      key: key(),
      keyLocation: base <> "/indexnow.txt",
      urlList: Enum.map(paths, &WebWeb.SEO.absolute/1)
    }

    options = [json: body, receive_timeout: 10_000, retry: false]

    case Req.post(@endpoint, options ++ Application.get_env(:web, :indexnow_req_options, [])) do
      {:ok, %{status: status}} when status in [200, 202] -> :ok
      # The engines refusing the key or the addresses is an answer, not a fault
      # to retry.
      {:ok, %{status: status}} when status in [400, 403, 422] -> {:cancel, "refused (#{status})"}
      {:ok, %{status: status}} -> {:error, "answered #{status}"}
      {:error, reason} -> {:error, reason}
    end
  end
end
