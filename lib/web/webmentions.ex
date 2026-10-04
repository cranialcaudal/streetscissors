defmodule Web.Webmentions do
  @moduledoc """
  Webmentions received: another site telling this one "my page links to
  yours" (https://www.w3.org/TR/webmention/). It is how independent sites
  cite each other without a platform in the middle — the conversation a
  quote-post pretends to be, between two homes that each own their words.

  ## The flow

    1. `POST /webmention` with `source` (their page) and `target` (ours).
       `receive/3` checks the target is one of our pieces, stores the pair as
       `pending`, and queues a verification. The sender gets a 202.
    2. `Web.Workers.WebmentionVerifier` fetches the source and confirms it
       really links to the target (`verify/1`). A confirmed mention is `held`.
    3. The author approves or rejects it at `/admin/citations`. Only
       `approved` mentions appear under the piece, as "Cited by".
    4. A later ping re-verifies. A source that stops linking, or answers 410,
       becomes `gone` and leaves the page.

  ## Fetching a stranger's URL, safely

  Verification makes this machine — a computer in a house — fetch a URL
  someone else chose. Unguarded, that is a way to make it request things on
  its own network (SSRF). So before every request, and again at every
  redirect hop, the host is resolved and refused if any of its addresses is
  loopback, private, link-local, carrier-grade NAT, unique-local or
  otherwise not public. Redirects are followed by hand (at most three), with
  a 10-second timeout and a 1 MB cap on the body. (The HTTP client resolves
  the name again when it connects, so a host that changes its DNS answer in
  between could slip past; the fetch is a GET whose body is only searched
  for a link, which keeps what such a trick could reach small.)
  """

  import Ecto.Query, warn: false

  alias Web.Pieces
  alias Web.Repo
  alias Web.Webmentions.Webmention

  @max_redirects 3
  @max_body 1_000_000

  # --- Receiving ---

  @doc """
  Accepts a mention of `target` (a URL on `our_host`) by `source`. Returns
  `{:ok, mention}` once it is stored and queued, or `{:error, reason}`.
  """
  def receive(source, target, our_host) do
    with {:ok, source_uri} <- web_url(source),
         {:ok, target_uri} <- web_url(target),
         :ok <- ours(target_uri, our_host),
         :ok <- not_ours(source_uri, our_host),
         {:ok, piece} <- Pieces.from_path(target_uri.path || "/"),
         {:ok, _} <- Pieces.resolve(piece) do
      store(source, target, piece, source_uri.host)
    else
      {:error, _} = error -> error
      :error -> {:error, :unknown_target}
    end
  end

  defp web_url(value) when is_binary(value) do
    case URI.parse(String.trim(value)) do
      %URI{scheme: scheme, host: host} = uri
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, uri}

      _ ->
        {:error, :not_a_web_url}
    end
  end

  defp web_url(_), do: {:error, :not_a_web_url}

  defp ours(%URI{host: host}, our_host) do
    if String.downcase(host) == String.downcase(our_host),
      do: :ok,
      else: {:error, :target_not_ours}
  end

  defp not_ours(%URI{host: host}, our_host) do
    if String.downcase(host) == String.downcase(our_host),
      do: {:error, :source_is_ours},
      else: :ok
  end

  defp store(source, target, piece, host) do
    existing = Repo.get_by(Webmention, source: source, target: target)

    result =
      (existing || %Webmention{})
      |> Webmention.changeset(%{
        source: source,
        target: target,
        piece: piece,
        source_host: String.downcase(host),
        status: if(existing, do: existing.status, else: "pending")
      })
      |> Repo.insert_or_update()

    with {:ok, mention} <- result do
      %{"id" => mention.id} |> Web.Workers.WebmentionVerifier.new() |> Oban.insert()
      {:ok, mention}
    end
  end

  # --- Verifying ---

  @doc """
  Fetches the source and records what it says. Definitive answers (it links,
  it doesn't, it's gone) return `:ok`; a transport failure returns
  `{:error, reason}` so the job is retried.
  """
  def verify(id) do
    case Repo.get(Webmention, id) do
      nil -> :ok
      mention -> mention |> fetch_source() |> record(mention)
    end
  end

  defp record({:ok, body}, mention) do
    if links_to?(body, mention.target) do
      save(mention, %{
        status: if(mention.status in ["pending", "gone"], do: "held", else: mention.status),
        title: title_of(body),
        author_name: author_of(body),
        verified_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
    else
      vanish(mention)
    end
  end

  defp record({:gone, _status}, mention), do: vanish(mention)
  defp record({:refused, _reason}, mention), do: vanish(mention)
  defp record({:error, _reason} = error, _mention), do: error

  # A source that doesn't link (yet, or any more) is `gone`: off the page,
  # and back to `held` if a later ping finds the link — senders often ping
  # before the citing page is live. Only the author rejects, and a rejection
  # sticks.
  defp vanish(%Webmention{status: "rejected"}), do: :ok
  defp vanish(mention), do: save(mention, %{status: "gone"})

  defp save(mention, attrs) do
    case mention |> Webmention.changeset(attrs) |> Repo.update() do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp fetch_source(%Webmention{source: source}), do: fetch(source, @max_redirects)

  defp fetch(url, hops_left) do
    with {:ok, uri} <- web_url(url),
         :ok <- public_host(uri.host) do
      request(url, uri, hops_left)
    else
      {:error, :not_a_web_url} -> {:refused, :not_a_web_url}
      {:refused, _} = refused -> refused
    end
  end

  defp request(url, uri, hops_left) do
    options =
      [
        redirect: false,
        retry: false,
        receive_timeout: 10_000,
        decode_body: false,
        headers: [{"user-agent", "streetscissors webmention verifier"}],
        into: &cap_body/2
      ]
      |> Keyword.merge(Application.get_env(:web, :webmention_req_options, []))

    case Req.get(url, options) do
      {:ok, %Req.Response{status: status} = resp} when status in 200..299 ->
        {:ok, IO.iodata_to_binary(resp.body || "")}

      {:ok, %Req.Response{status: status} = resp} when status in [301, 302, 303, 307, 308] ->
        follow(Req.Response.get_header(resp, "location"), uri, hops_left)

      {:ok, %Req.Response{status: status}} when status in [404, 410] ->
        {:gone, status}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp follow([location | _], base, hops_left) when hops_left > 0,
    do: base |> URI.merge(location) |> URI.to_string() |> fetch(hops_left - 1)

  defp follow(_, _base, _hops_left), do: {:refused, :too_many_redirects}

  # Stops reading once the body passes the cap: a page that cites us will
  # have said so well within a megabyte.
  defp cap_body({:data, data}, {req, resp}) do
    body = [resp.body || "" | data] |> IO.iodata_to_binary()
    resp = %{resp | body: body}
    if byte_size(body) > @max_body, do: {:halt, {req, resp}}, else: {:cont, {req, resp}}
  end

  @doc false
  # Every address the host resolves to must be public. The resolver is
  # configurable so the suite never touches real DNS.
  def public_host(host) do
    {module, fun} = Application.get_env(:web, :webmention_resolver, {__MODULE__, :resolve})

    case apply(module, fun, [host]) do
      [] ->
        {:refused, :unresolvable}

      addresses ->
        if Enum.all?(addresses, &public_address?/1), do: :ok, else: {:refused, :private_address}
    end
  end

  @doc false
  def resolve(host) do
    charlist = String.to_charlist(host)

    case :inet.parse_address(charlist) do
      {:ok, address} ->
        [address]

      {:error, _} ->
        v4 =
          case :inet.getaddrs(charlist, :inet),
            do: (
              {:ok, list} -> list
              _ -> []
            )

        v6 =
          case :inet.getaddrs(charlist, :inet6),
            do: (
              {:ok, list} -> list
              _ -> []
            )

        v4 ++ v6
    end
  end

  @doc false
  def public_address?({a, b, _, _} = _ipv4) do
    not (a == 0 or a == 10 or a == 127 or a >= 224 or
           (a == 100 and b in 64..127) or
           (a == 169 and b == 254) or
           (a == 172 and b in 16..31) or
           (a == 192 and b == 168) or
           (a == 198 and b in 18..19))
  end

  def public_address?({0, 0, 0, 0, 0, 0, 0, _}), do: false

  def public_address?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: public_address?({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)})

  def public_address?({first, _, _, _, _, _, _, _}) when first in 0xFC00..0xFDFF, do: false
  def public_address?({first, _, _, _, _, _, _, _}) when first in 0xFE80..0xFEBF, do: false
  def public_address?({first, _, _, _, _, _, _, _}) when first in 0xFF00..0xFFFF, do: false
  def public_address?({_, _, _, _, _, _, _, _}), do: true
  def public_address?(_), do: false

  # --- Reading the source ---

  # The page counts as citing us if it contains a link to the target, with or
  # without its scheme or a trailing slash.
  defp links_to?(body, target) do
    bare = target |> String.replace(~r{^https?:}, "") |> String.trim_trailing("/")
    Regex.match?(~r/href\s*=\s*["']?(https?:)?#{Regex.escape(bare)}\/?["'\s>]/i, body)
  end

  defp title_of(body) do
    case Regex.run(~r{<title[^>]*>(.*?)</title>}is, body) do
      [_, title] -> clean(title)
      _ -> nil
    end
  end

  defp author_of(body) do
    case Regex.run(~r|class\s*=\s*["'][^"']*\bp-author\b[^"']*["'][^>]*>([^<]{1,200})<|i, body) do
      [_, name] -> clean(name)
      _ -> nil
    end
  end

  defp clean(text) do
    text
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace(~r/&amp;/, "&")
    |> String.replace(~r/&#0?39;|&apos;/, "'")
    |> String.replace(~r/&quot;/, "\"")
    |> String.replace(~r/&lt;/, "<")
    |> String.replace(~r/&gt;/, ">")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
  end

  # --- Reading and moderating ---

  @doc "Mentions shown under a piece: approved only, oldest first."
  def list_approved(piece) when is_binary(piece) do
    from(w in Webmention,
      where: w.piece == ^piece and w.status == "approved",
      order_by: [asc: w.inserted_at]
    )
    |> Repo.all()
  end

  def list_approved(_), do: []

  @doc "Mentions for the admin, newest first; `status` narrows them."
  def list(status \\ nil) do
    Webmention
    |> then(fn q -> if status, do: where(q, [w], w.status == ^status), else: q end)
    |> order_by([w], desc: w.updated_at)
    |> Repo.all()
  end

  @doc "How many verified mentions wait for the author."
  def count_held, do: Repo.aggregate(from(w in Webmention, where: w.status == "held"), :count)

  def count_by_status do
    from(w in Webmention, group_by: w.status, select: {w.status, count(w.id)})
    |> Repo.all()
    |> Map.new()
  end

  def get!(id), do: Repo.get!(Webmention, id)

  def approve(%Webmention{} = mention), do: set_status(mention, "approved")
  def reject(%Webmention{} = mention), do: set_status(mention, "rejected")
  def delete(%Webmention{} = mention), do: Repo.delete(mention)

  defp set_status(mention, status) do
    mention |> Ecto.Changeset.change(status: status) |> Repo.update()
  end
end
