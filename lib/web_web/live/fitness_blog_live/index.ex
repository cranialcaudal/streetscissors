defmodule WebWeb.FitnessBlogLive.Index do
  use WebWeb, :live_view

  alias Web.Fitness.Vault

  @impl true
  def mount(_params, session, socket) do
    is_admin = session["admin_user"] == true

    {:ok,
     socket
     |> assign(:is_admin, is_admin)
     |> assign(:page_title, "Fitness & Sport")
     |> assign(:return_to, "/")
     |> assign(:return_label, "return to home")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    posts = Vault.list_blog_posts()
    hit_counts = Web.Analytics.all_hits_by_prefix("/fitness-blog/%")

    posts =
      Enum.map(posts, fn post ->
        Map.put(post, :hit_count, Map.get(hit_counts, post.slug, 0))
      end)

    sort = params["sort"] || "recent"

    sorted_posts =
      case sort do
        "most-read" ->
          Enum.sort_by(posts, & &1.hit_count, :desc)

        "least-read" ->
          Enum.sort_by(posts, & &1.hit_count, :asc)

        "recent" ->
          Enum.sort_by(posts, & &1.date, :desc)

        _ ->
          Enum.sort_by(posts, & &1.date, :desc)
      end

    {:noreply,
     socket
     |> assign(:posts, sorted_posts)
     |> assign(:sort, sort)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="blog-bento-wrapper" style="--blog-accent: #ff6b6b;">
      
    <!-- Header -->
      <header class="blog-header-card">
        <h1 class="blog-header-title">Fitness & Sport</h1>
        <div class="blog-header-subtitle">Pro sports, amateur training & movement science</div>
      </header>
      
    <!-- Section Navigation -->
      <WebWeb.FitnessSubnav.subnav active={:blog} is_admin={@is_admin} />
      
    <!-- Sorting -->
      <div class="blog-sort-bar">
        <span class="blog-sort-label">Sort By:</span>
        <div class="blog-sort-options">
          <.link
            patch={~p"/fitness?sort=recent"}
            class={["blog-sort-pill", @sort == "recent" && "active"]}
          >
            Most Recent
          </.link>
          <.link
            patch={~p"/fitness?sort=most-read"}
            class={["blog-sort-pill", @sort == "most-read" && "active"]}
          >
            Most Read
          </.link>
          <.link
            patch={~p"/fitness?sort=least-read"}
            class={["blog-sort-pill", @sort == "least-read" && "active"]}
          >
            Least Read
          </.link>
        </div>
      </div>
      
    <!-- Feed -->
      <%= if Enum.empty?(@posts) do %>
        <div style="text-align: center; padding: 4rem 2rem; color: #444;">
          <p style="font-size: 1.1rem; margin-bottom: 0.5rem; font-family: var(--font-heading, 'Futura');">
            No reports filed yet.
          </p>
        </div>
      <% else %>
        <div class="blog-feed">
          <%= for {post, index} <- Enum.with_index(@posts) do %>
            <article class={[
              "blog-bento-card",
              (index == 0 and @sort == "recent") && "bento-span-full"
            ]}>
              <%= if index == 0 and @sort == "recent" do %>
                <div class="blog-bento-card-ribbon">NEW!</div>
              <% end %>

              <h2 class="blog-bento-title">
                <.link navigate={~p"/fitness/#{post.slug}"}>{post.title}</.link>
              </h2>

              <div class="blog-bento-meta">
                <%= if post.date do %>
                  <span class="blog-bento-meta-item">
                    <.icon name="hero-calendar" class="size-4" /> {post.date}
                  </span>
                <% end %>
                <span class="blog-bento-meta-item">
                  <.icon name="hero-chart-bar" class="size-4" /> {post.hit_count} views
                </span>
              </div>

              <p class="blog-bento-excerpt">
                {post.excerpt}...
              </p>

              <div class="blog-bento-actions">
                <.link
                  navigate={~p"/fitness/#{post.slug}"}
                  class="top-bar-link"
                  style="padding: 0.35rem 0.8rem; background: rgba(0,0,0,0.3); border: none;"
                >
                  Read Report →
                </.link>
              </div>
            </article>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end
end
