defmodule WebWeb.FitnessBlogLive.Index do
  use WebWeb, :live_view

  alias Web.Fitness.Vault

  @impl true
  def mount(_params, _session, socket) do
    posts = Vault.list_blog_posts()

    {:ok,
     socket
     |> assign(:page_title, "Fitness Intelligence")
     |> assign(:return_to, "/fitness")
     |> assign(:return_label, "return to fitness")
     |> assign(:posts, posts)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <header class="theme-header" style="margin-bottom: 2rem; display: none;">
        <h1 class="theme-title">Fitness Intelligence</h1>
      </header>
      <h1 class="theme-title" style="margin-bottom: 2rem;">Fitness Intelligence</h1>

      <%= if @posts == [] do %>
        <p style="color: #666; text-align: center; padding: 3rem;">No reports filed yet.</p>
      <% else %>
        <div style="display: flex; flex-direction: column; gap: 2rem;">
          <%= for post <- @posts do %>
            <article class="glass-panel" style="padding: 2rem; border-radius: 12px;">
              <h2 style="font-size: 1.6rem; font-family: var(--font-heading); margin-bottom: 0.5rem;">
                <.link
                  navigate={~p"/fitness-blog/#{post.slug}"}
                  style="color: #fff; text-decoration: none;"
                >
                  {post.title}
                </.link>
              </h2>
              <%= if post.date do %>
                <p style="color: #555; font-size: 0.8rem; text-transform: uppercase; letter-spacing: 1px; margin-bottom: 1rem;">
                  {post.date}
                </p>
              <% end %>
              <p style="color: #888; line-height: 1.7;">{post.excerpt}...</p>
              <.link
                navigate={~p"/fitness-blog/#{post.slug}"}
                class="sensus-more-link"
                style="margin-top: 1.5rem; display: inline-block; color: var(--theme-color); text-decoration: none; font-weight: bold; font-size: 0.9rem; text-transform: uppercase; border: 1px solid rgba(255,102,0,0.3); padding: 0.5rem 1rem; border-radius: 4px;"
              >
                Read Report →
              </.link>
            </article>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
