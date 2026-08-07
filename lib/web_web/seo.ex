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

  def site_name, do: @default_title
end
