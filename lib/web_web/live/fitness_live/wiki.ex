defmodule WebWeb.FitnessLive.Wiki do
  use WebWeb, :live_view

  alias Web.Fitness.Vault

  @impl true
  def mount(_params, _session, socket) do
    # Exercises are file-based content (see Web.Fitness.Vault), not DB rows.
    # list_all_exercises/0 returns [{muscle_group_folder, [exercise, ...]}, ...].
    grouped_sorted =
      Vault.list_all_exercises()
      |> Enum.map(fn {group, exercises} -> {String.capitalize(group), exercises} end)
      |> Enum.reject(fn {_group, exercises} -> exercises == [] end)
      |> Enum.sort()

    {:ok,
     socket
     |> assign(:page_title, "Exercise Wiki")
     |> assign(:return_to, "/fitness")
     |> assign(:return_label, "return to fitness")
     |> assign(:grouped_exercises, grouped_sorted)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="blog-bento-wrapper steel">
      <!-- Header -->
      <header class="blog-header-card">
        <h1 class="blog-header-title">Fitness & Sport</h1>
        <div class="blog-header-subtitle">Pro sports, amateur training & movement science</div>
      </header>
      
    <!-- Section Navigation -->
      <WebWeb.FitnessSubnav.subnav active={:wiki} />

      <div class="blog-bento-card bento-span-full wiki-index">
        <h2 class="wiki-index-title">Exercise Wiki</h2>

        <div class="wiki-groups">
          <div :for={{group, list} <- @grouped_exercises} class="wiki-group-card">
            <h3 class="wiki-group-title">{group}</h3>
            <ul class="wiki-group-list">
              <li :for={exercise <- Enum.sort_by(list, & &1.name)}>
                <.link navigate={~p"/fitness/wiki/#{exercise.slug}"} class="gym-link">
                  {exercise.name}
                </.link>
              </li>
            </ul>
          </div>
        </div>

        <p :if={@grouped_exercises == []} class="wiki-index-empty">No exercises indexed yet.</p>
      </div>
    </div>
    """
  end
end
