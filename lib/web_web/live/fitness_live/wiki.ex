defmodule WebWeb.FitnessLive.Wiki do
  use WebWeb, :live_view

  alias Web.Fitness.Vault

  @impl true
  def mount(_params, session, socket) do
    is_admin = session["admin_user"] == true

    # Exercises are file-based content (see Web.Fitness.Vault), not DB rows.
    # list_all_exercises/0 returns [{muscle_group_folder, [exercise, ...]}, ...].
    grouped_sorted =
      Vault.list_all_exercises()
      |> Enum.map(fn {group, exercises} -> {String.capitalize(group), exercises} end)
      |> Enum.reject(fn {_group, exercises} -> exercises == [] end)
      |> Enum.sort()

    {:ok,
     socket
     |> assign(:is_admin, is_admin)
     |> assign(:page_title, "Exercise Wiki")
     |> assign(:return_to, "/fitness")
     |> assign(:return_label, "return to fitness")
     |> assign(:grouped_exercises, grouped_sorted)}
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
      <WebWeb.FitnessSubnav.subnav active={:wiki} is_admin={@is_admin} />

      <div class="blog-bento-card bento-span-full" style="padding: 2rem;">
        <h2 style="font-size: 2.2rem; font-family: var(--font-heading); color: var(--theme-color); text-transform: uppercase; letter-spacing: 2px; margin-bottom: 2rem; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 1rem;">
          Exercise Wiki
        </h2>

        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 2rem;">
          <%= for {group, list} <- @grouped_exercises do %>
            <div
              class="wiki-group-card"
              style="background: rgba(255,255,255,0.02); border: 1px solid rgba(255,255,255,0.05); border-radius: 12px; padding: 1.5rem;"
            >
              <h3 style="color: var(--theme-color); font-size: 1rem; text-transform: uppercase; letter-spacing: 1px; border-left: 3px solid var(--theme-color); padding-left: 0.75rem; margin-bottom: 1.25rem;">
                {group}
              </h3>
              <ul style="list-style: none; padding: 0; display: flex; flex-direction: column; gap: 0.75rem;">
                <%= for exercise <- Enum.sort_by(list, & &1.name) do %>
                  <li>
                    <.link
                      navigate={~p"/fitness/wiki/#{exercise.slug}"}
                      class="gym-link"
                      style="display: block; padding: 0.75rem; background: rgba(255,255,255,0.03); border-radius: 8px; border: 1px solid rgba(255,255,255,0.05); transition: 0.2s; font-size: 0.95rem;"
                      onmouseover="this.style.borderColor='var(--theme-color)'; this.style.background='rgba(255,102,0,0.05)'"
                      onmouseout="this.style.borderColor='rgba(255,255,255,0.05)'; this.style.background='rgba(255,255,255,0.03)'"
                    >
                      {exercise.name}
                    </.link>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </div>

        <%= if @grouped_exercises == [] do %>
          <p style="color: #666; text-align: center;">No exercises indexed yet.</p>
        <% end %>
      </div>
    </div>
    """
  end
end
