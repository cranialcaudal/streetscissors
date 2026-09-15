defmodule WebWeb.SEO do
  @moduledoc """
  Per-page metadata for the root layout.

  Before this, every page on the site shared one Open Graph card ("streetscissors" /
  "A space for reflections, manuscripts, and more"), there was no
  `<meta name="description">` and no canonical URL at all, and `og:image` was a
  relative path — which no unfurler resolves, so links posted anywhere rendered
  without an image.

  Pages opt in by assigning `:page_title`, `:og_title`, `:og_description` and
  optionally `:canonical_path` / `:og_type`; everything falls back to sensible
  site-wide defaults.
  """

  @default_title "streetscissors"
  @default_description "Photographs, essays and recordings from the streetscissors darkroom."
  @default_image "/images/preview_logo.png"

  @doc "Absolute site URL, e.g. `https://streetscissors.com`."
  def base_url, do: WebWeb.Endpoint.url()

  @doc "Turns a site-relative path into an absolute URL."
  def absolute(nil), do: nil
  def absolute("http" <> _ = url), do: url
  def absolute("/" <> _ = path), do: base_url() <> path

  @doc """
  Canonical URL for the current page.

  Prefers an explicit `:canonical_path` assign; otherwise falls back to the
  request path, which is only present for controller-rendered pages and the
  initial (dead) render of a LiveView. Returns `nil` when neither is known
  rather than emitting a wrong canonical, which is worse than none.
  """
  def canonical_url(assigns) do
    cond do
      path = assigns[:canonical_path] -> absolute(path)
      conn = assigns[:conn] -> absolute(conn.request_path)
      true -> nil
    end
  end

  def title(assigns), do: assigns[:page_title] || @default_title

  @doc "OG title falls back to the page title, so posts get their own card."
  def og_title(assigns), do: assigns[:og_title] || assigns[:page_title] || @default_title

  def description(assigns) do
    assigns[:meta_description] || assigns[:og_description] || @default_description
  end

  @doc "Always absolute — a relative og:image is silently ignored by unfurlers."
  def og_image(assigns), do: absolute(assigns[:og_image] || @default_image)

  @doc "`article` for a single post or log, `website` for everything else."
  def og_type(assigns), do: assigns[:og_type] || "website"

  @doc """
  Crawler directive for the current page, or `nil` to send none.

  Only unlisted pages assign `:robots` (currently just `/food`). Returning `nil`
  rather than `"index, follow"` for everything else is deliberate: indexing is
  already the default, and a page that says nothing is treated identically to
  one that opts in.
  """
  def robots(assigns), do: assigns[:robots]

  def site_name, do: @default_title

  @doc """
  JSON-LD identifying the site's author, so crawlers get an explicit
  authorship signal without any `sameAs` — no cross-linking to other profiles,
  by design. The name comes from `config :web, :author_name` (set from
  `AUTHOR_NAME` at runtime) so it stays out of the code; unset, nothing is
  emitted.

  Returns a full `<script>` tag, ready to `raw/1` into the layout. HEEx
  treats a *literal* `<script>` tag in template source as raw text — an
  `{...}` expression written inside one is never evaluated, it leaks into the
  page as text. Building the whole tag as a string here and `raw/1`-ing it at
  a template position with no literal `<script>` wrapper sidesteps that.
  """
  def person_json_ld_tag do
    case Application.get_env(:web, :author_name) do
      name when is_binary(name) and name != "" ->
        json_ld_tag(%{
          "@context" => "https://schema.org",
          "@type" => "Person",
          "name" => name,
          "url" => base_url()
        })

      _ ->
        ""
    end
  end

  @doc "JSON-LD identifying the site itself, keyed to its exact brand name."
  def website_json_ld_tag do
    json_ld_tag(%{
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => site_name(),
      "url" => base_url()
    })
  end

  defp json_ld_tag(data) do
    ~s(<script type="application/ld+json">#{Jason.encode!(data)}</script>)
  end
end
