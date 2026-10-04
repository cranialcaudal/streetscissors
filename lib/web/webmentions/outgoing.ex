defmodule Web.Webmentions.Outgoing do
  @moduledoc """
  Webmentions sent: this site telling another "my post links to your page",
  so a citation runs both ways.

  `Web.Webmentions` receives them. Without this half the site could be cited
  and could not cite: a post that quoted someone's essay left no trace on
  their side, where the same link from them shows here as "Cited by".

  ## The flow

    1. `run/0`, hourly. Every published post is rendered and its links to
       other sites collected. A link not seen before becomes a `queued` row
       and a job; one seen before is left alone, so each is announced once.
    2. `deliver/1`, the job. The target page is fetched to find where it
       takes webmentions (a `Link` header, or the first `<link>` or `<a>`
       with `rel="webmention"`), and `source` and `target` are posted there.
       A page with no endpoint is recorded `no_endpoint` and not asked again:
       most of the web does not take them, and that is not a fault.
    3. A link that has left a post it was `sent` from is announced once more.
       The receiver re-reads our page, finds the link gone, and drops the
       citation. The row becomes `withdrawn`.

  Posts only, and anchors only. A captain's log has no text to link from,
  and an embedded player or picture is not a citation of its host.

  ## A stranger's URL, again

  The target is a link the author wrote, but the endpoint is whatever the
  target's page says it is, and both are fetched from a computer in a house.
  So the same guard as on the receiving side applies to each: the host is
  resolved and refused unless every address is public
  (`Web.Webmentions.public_host/1`), redirects are followed by hand with the
  check repeated at every hop, and the body read while looking for an
  endpoint is capped at a megabyte. The resolver and the HTTP options are the
  receiver's (`:webmention_resolver`, `:webmention_req_options`), so the
  suite never touches DNS or the network.

  `:webmention_send` set to `false` turns the hourly pass off.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Web.Blog
  alias Web.Repo
  alias Web.Webmentions
  alias Web.Webmentions.Sent
  alias Web.Workers.WebmentionSender

  @max_redirects 3
  @max_body 1_000_000
  @agent "streetscissors webmention sender"

  # --- The pass --------------------------------------------------------------

  @doc """
  Queues a mention for every link not yet announced, and a withdrawal for
  every announced link that has left its post.

  Returns `%{queued: n, withdrawn: n}`.
  """
  def run do
    wanted = MapSet.new(citations())
    rows = Repo.all(Sent)
    known = MapSet.new(rows, &{&1.source, &1.target})

    queued =
      for {source, target} <- wanted, not MapSet.member?(known, {source, target}) do
        {:ok, sent} =
          %Sent{} |> Sent.changeset(%{source: source, target: target}) |> Repo.insert()

        enqueue(sent)
      end

    withdrawn =
      for %Sent{status: "sent"} = sent <- rows,
          not MapSet.member?(wanted, {sent.source, sent.target}) do
        enqueue(sent)
      end

    %{queued: length(queued), withdrawn: length(withdrawn)}
  end

  @doc "Entry point for the scheduler. Never raises."
  def run_scheduled do
    if Application.get_env(:web, :webmention_send, true), do: run()
    :ok
  rescue
    error ->
      Logger.error("webmention pass crashed: #{Exception.message(error)}")
      :ok
  end

  @doc "Queues one row again, from the admin: a failure worth another try."
  def retry(%Sent{} = sent) do
    {:ok, sent} = sent |> Sent.changeset(%{status: "queued", detail: nil}) |> Repo.update()
    enqueue(sent)
  end

  defp enqueue(%Sent{id: id}), do: %{"id" => id} |> WebmentionSender.new() |> Oban.insert()

  @doc """
  Every `{source, target}` the site currently cites: `source` a published
  post's path, `target` a link in it to a page on another host.
  """
  def citations do
    for post <- Blog.list_posts(),
        {:ok, %{body: body}} <- [Blog.get_post(post.slug)],
        target <- external_links(Blog.to_html(body)),
        uniq: true do
      {"/blog/#{post.slug}", target}
    end
  end

  defp external_links(html) do
    own = own_hosts()

    for [href] <- Regex.scan(~r/<a\s[^>]*?href="([^"]+)"/i, html, capture: :all_but_first),
        href = String.replace(href, "&amp;", "&"),
        %URI{scheme: scheme, host: host} = URI.parse(href),
        scheme in ["http", "https"],
        is_binary(host),
        String.downcase(host) not in own do
      href
    end
  end

  defp own_hosts do
    host = String.downcase(WebWeb.Endpoint.config(:url)[:host])
    [host, "www." <> host]
  end

  # --- Delivering ------------------------------------------------------------

  @doc """
  Sends (or withdraws) one mention and records what happened. Definitive
  answers return `:ok`; a transport failure returns `{:error, reason}` so the
  job is retried, with the failure recorded in case the retries run out.
  """
  def deliver(id) do
    case Repo.get(Sent, id) do
      nil -> :ok
      sent -> sent |> announce() |> record(sent)
    end
  end

  defp announce(%Sent{source: source, target: target}) do
    with {:ok, endpoint} <- discover(target),
         :ok <- guard(endpoint) do
      post(endpoint, WebWeb.Endpoint.url() <> source, target)
    end
  end

  defp record({:ok, endpoint, status}, sent) do
    # Announced after the link left the post, it was a withdrawal.
    still_cited? = {sent.source, sent.target} in citations()

    save(sent, %{
      status: if(still_cited?, do: "sent", else: "withdrawn"),
      endpoint: endpoint,
      detail: "answered #{status}",
      sent_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  defp record(:no_endpoint, sent),
    do: save(sent, %{status: "no_endpoint", detail: "the page takes no webmentions"})

  defp record({:refused, reason}, sent),
    do: save(sent, %{status: "failed", detail: "refused: #{reason}"})

  defp record({:rejected, endpoint, status}, sent),
    do: save(sent, %{status: "failed", endpoint: endpoint, detail: "answered #{status}"})

  defp record({:error, reason}, sent) do
    save(sent, %{status: "failed", detail: "could not connect: #{describe(reason)}"})
    {:error, reason}
  end

  defp save(sent, attrs) do
    case sent |> Sent.changeset(attrs) |> Repo.update() do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp describe(%{reason: reason}), do: describe(reason)
  defp describe(reason) when is_atom(reason), do: to_string(reason)
  defp describe(reason), do: inspect(reason)

  # --- Finding the endpoint --------------------------------------------------

  @doc """
  Where `target` takes webmentions: `{:ok, url}`, `:no_endpoint`,
  `{:refused, reason}` or `{:error, reason}`.

  A `Link` header wins over the document, and in the document the first
  `<link>` or `<a>` with `rel="webmention"` wins, as the specification has
  it. A relative endpoint resolves against the address the page was finally
  served from, after any redirects.
  """
  def discover(target), do: fetch(target, @max_redirects)

  defp fetch(url, hops_left) do
    with {:ok, uri} <- web_url(url),
         :ok <- Webmentions.public_host(uri.host) do
      case Req.get(url, req_options(into: &cap_body/2, decode_body: false)) do
        {:ok, %Req.Response{status: status} = resp} when status in 200..299 ->
          endpoint(resp, uri)

        {:ok, %Req.Response{status: status} = resp} when status in [301, 302, 303, 307, 308] ->
          follow(Req.Response.get_header(resp, "location"), uri, hops_left)

        {:ok, %Req.Response{status: status}} when status in [404, 410] ->
          {:refused, "the page answers #{status}"}

        {:ok, %Req.Response{status: status}} ->
          {:error, {:http, status}}

        {:error, exception} ->
          {:error, exception}
      end
    end
  end

  defp follow([location | _], base, hops_left) when hops_left > 0,
    do: base |> URI.merge(location) |> URI.to_string() |> fetch(hops_left - 1)

  defp follow(_, _base, _hops_left), do: {:refused, :too_many_redirects}

  defp endpoint(resp, base) do
    body = IO.iodata_to_binary(resp.body || "")

    case header_endpoint(resp) || document_endpoint(body) do
      nil -> :no_endpoint
      href -> {:ok, base |> URI.merge(href) |> URI.to_string()}
    end
  end

  # Link: <https://example.com/webmention>; rel="webmention"
  defp header_endpoint(resp) do
    resp
    |> Req.Response.get_header("link")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.find_value(fn link ->
      with [_, href, params] <- Regex.run(~r/<([^>]*)>(.*)/s, link),
           [_, rel] <- Regex.run(~r/rel\s*=\s*"?([^";]+)"?/i, params),
           true <- "webmention" in String.split(String.downcase(rel)) do
        href
      else
        _ -> nil
      end
    end)
  end

  # The first <link> or <a> whose rel includes "webmention", in document
  # order. An empty href is a real answer: the page is its own endpoint.
  defp document_endpoint(body) do
    ~r/<(?:link|a)\s[^>]*>/i
    |> Regex.scan(body)
    |> Enum.find_value(fn [tag] ->
      with [_, rel] <- Regex.run(~r/\srel\s*=\s*["']([^"']*)["']/i, tag),
           true <- "webmention" in String.split(String.downcase(rel)),
           [_, href] <- Regex.run(~r/\shref\s*=\s*["']([^"']*)["']/i, tag) do
        String.replace(href, "&amp;", "&")
      else
        _ -> nil
      end
    end)
  end

  defp cap_body({:data, data}, {req, resp}) do
    body = [resp.body || "" | data] |> IO.iodata_to_binary()
    resp = %{resp | body: body}
    if byte_size(body) > @max_body, do: {:halt, {req, resp}}, else: {:cont, {req, resp}}
  end

  # --- Posting ---------------------------------------------------------------

  # The endpoint is the target page's word for where to post. It is checked
  # like any other address a stranger chose.
  defp guard(endpoint) do
    with {:ok, uri} <- web_url(endpoint), do: Webmentions.public_host(uri.host)
  end

  defp post(endpoint, source, target) do
    case Req.post(endpoint, req_options(form: [source: source, target: target])) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        {:ok, endpoint, status}

      {:ok, %Req.Response{status: status}} when status in 400..499 ->
        {:rejected, endpoint, status}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp req_options(extra) do
    [
      redirect: false,
      retry: false,
      receive_timeout: 10_000,
      headers: [{"user-agent", @agent}]
    ]
    |> Keyword.merge(extra)
    |> Keyword.merge(Application.get_env(:web, :webmention_req_options, []))
  end

  defp web_url(value) do
    case URI.parse(String.trim(value)) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, uri}

      _ ->
        {:refused, :not_a_web_url}
    end
  end

  # --- Reading, for the admin ------------------------------------------------

  @doc "Every mention sent or attempted, newest first."
  def list, do: Repo.all(from s in Sent, order_by: [desc: s.updated_at, desc: s.id])

  def get!(id), do: Repo.get!(Sent, id)
end
