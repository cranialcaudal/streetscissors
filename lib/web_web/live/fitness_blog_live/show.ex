defmodule WebWeb.FitnessBlogLive.Show do
  use WebWeb, :live_view

  alias Web.Fitness.Vault

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Vault.get_blog_post(slug) do
      {:ok, meta, html} ->
        {:ok,
         socket
         |> assign(:page_title, meta["title"] || slug)
         |> assign(:return_to, "/fitness-blog")
         |> assign(:return_label, "return to fitness intelligence")
         |> assign(:title, meta["title"] || slug)
         |> assign(:date, meta["date"])
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
    <div class="container">
      <header class="theme-header" style="margin-bottom: 2rem; display: none;">
        <h1 class="theme-title">{@title}</h1>
      </header>
      <div style="margin-bottom: 2rem;">
        <h1 class="theme-title">{@title}</h1>
        <%= if @date do %>
          <p style="color: #555; font-size: 0.8rem; text-transform: uppercase; letter-spacing: 1px; margin-top: 0.5rem;">
            {@date}
          </p>
        <% end %>
      </div>

      <div class="glass-panel markdown-body" style="padding: 2rem; min-height: 60vh;">
        {raw(@html)}
      </div>
    </div>
    """
  end
end
