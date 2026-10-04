defmodule WebWeb.Microformats do
  @moduledoc """
  The small pieces of IndieWeb markup (microformats2) that let other people's
  sites and readers understand a page without a platform in between: a post,
  log or frame is an `h-entry`, and the site's author is an `h-card`.

  The properties themselves are plain classes on the elements a page already
  has (`p-name` on its title, `dt-published` on its `<time>`, `e-content` or
  `u-photo`), and no stylesheet targets them. What a page does not already
  show — its canonical URL, who wrote it — goes in the hidden fields here.

  The author is `config :web, :author_name` (`AUTHOR_NAME`), falling back to
  the site's name, so no personal detail enters the code.
  """

  use Phoenix.Component

  @doc "The author, as microformats and structured data name them."
  def author_name do
    case Application.get_env(:web, :author_name) do
      name when is_binary(name) and name != "" -> name
      _ -> WebWeb.SEO.site_name()
    end
  end

  @doc "An entry's permalink and author, for inside its `h-entry` root."
  attr :path, :string, required: true

  def entry_fields(assigns) do
    ~H"""
    <a class="u-url" href={WebWeb.SEO.absolute(@path)} hidden></a>
    <a class="p-author h-card" href={WebWeb.SEO.base_url()} hidden>{author_name()}</a>
    """
  end

  @doc """
  The site's representative `h-card`: the one a reader or another site takes
  to mean "who this is". Rendered on the homepage.
  """
  def representative_card(assigns) do
    ~H"""
    <a class="h-card p-name u-url u-uid" href={WebWeb.SEO.base_url()} hidden>{author_name()}</a>
    """
  end
end
