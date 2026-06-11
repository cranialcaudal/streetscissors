defmodule WebWeb.FitnessBlogLive.Show do
  use WebWeb, :live_view

  alias Web.Fitness.Vault

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Vault.get_blog_post(slug) do
      {:ok, meta, html} ->
        hit_counts = Web.Analytics.all_hits_by_prefix("/fitness-blog/#{slug}")
        hit_count = Map.get(hit_counts, slug, 0)

        {:ok,
         socket
         |> assign(:page_title, meta["title"] || slug)
         |> assign(:return_to, "/fitness-blog")
         |> assign(:return_label, "return to fitness intelligence")
         |> assign(:title, meta["title"] || slug)
         |> assign(:date, meta["date"])
         |> assign(:hit_count, hit_count)
         |> assign(:html, html)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Post not found.")
         |> push_navigate(to: "/fitness-blog")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={assigns[:current_scope]}>
      <div class="blog-bento-wrapper" style="--blog-accent: #1e90ff;">
        <div class="blog-post-panel">
          <header class="blog-post-header">
            <div style="margin-bottom: 1rem;">
              <.back_link navigate={@return_to} label={@return_label} />
            </div>

            <h1 class="blog-post-title">{@title}</h1>

            <div class="blog-post-meta">
              <%= if @date do %>
                <span class="blog-bento-meta-item">
                  <.icon name="hero-calendar" class="size-4" /> {@date}
                </span>
              <% end %>
              <span class="blog-bento-meta-item">
                <.icon name="hero-chart-bar" class="size-4" /> {@hit_count} views
              </span>
            </div>
          </header>

          <div class="blog-post-content prose prose-invert">
            {raw(@html)}
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
