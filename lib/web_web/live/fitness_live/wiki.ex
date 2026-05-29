defmodule WebWeb.FitnessLive.Wiki do
  use WebWeb, :live_view

  alias Web.Fitness

  @impl true
  def mount(_params, _session, socket) do
    # Group exercises by muscle group
    exercises = Fitness.list_exercises()

    grouped =
      Enum.group_by(exercises, fn ex ->
        String.capitalize(ex.muscle_group || "Other")
      end)

    # Sort groups alphabetically
    grouped_sorted = Enum.sort(grouped)

    {:ok,
     socket
     |> assign(:page_title, "Exercise Wiki")
     |> assign(:return_to, "/fitness")
     |> assign(:return_label, "return to gym routine")
     |> assign(:grouped_exercises, grouped_sorted)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container">
      <header class="theme-header" style="margin-bottom: 2rem; display: none;">
        <h1 class="theme-title">Exercise Wiki</h1>
      </header>

      <div class="glass-panel" style="padding: 2rem; min-height: 70vh;">
        <%= for {group, list} <- @grouped_exercises do %>
          <div class="muscle-group-section" style="margin-bottom: 2rem;">
            <h3 style="color: var(--theme-color); font-size: 1.2rem; margin-bottom: 1rem;">
              {group}
            </h3>
            <ul style="list-style: none; padding: 0; display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1rem;">
              <%= for exercise <- Enum.sort_by(list, & &1.name) do %>
                <li>
                  <.link
                    navigate={~p"/fitness/#{exercise.slug}"}
                    class="gym-link"
                    style="display: block; padding: 0.75rem; background: rgba(255,255,255,0.02); border-radius: 4px; border: 1px solid rgba(255,255,255,0.05); transition: 0.2s;"
                    onmouseover="this.style.borderColor='var(--theme-color)'"
                    onmouseout="this.style.borderColor='rgba(255,255,255,0.05)'"
                  >
                    {exercise.name}
                  </.link>
                </li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <%= if @grouped_exercises == [] do %>
          <p style="color: #666; text-align: center;">No exercises indexed yet.</p>
        <% end %>
      </div>
    </div>

    <style>
      .gym-link {
          color: #ddd;
          text-decoration: none;
      }
      .gym-link:hover {
          color: var(--theme-color);
      }
    </style>
    """
  end
end
