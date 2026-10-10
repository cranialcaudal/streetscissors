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
     |> assign(:all_exercises, grouped_sorted)}
  end

  # The filter is in the address (`?q=row`), so a narrowed wiki can be linked
  # to and survives a reload. Filtering is against the list already read.
  @impl true
  def handle_params(params, _uri, socket) do
    query = Web.Search.clean(params["q"])

    {:noreply,
     socket
     |> assign(:query, query)
     |> assign(:grouped_exercises, filtered(socket.assigns.all_exercises, query))}
  end

  @impl true
  def handle_event("filter", %{"q" => query}, socket) do
    path =
      case Web.Search.clean(query) do
        "" -> ~p"/fitness/wiki"
        q -> ~p"/fitness/wiki?#{[q: q]}"
      end

    {:noreply, push_patch(socket, to: path, replace: true)}
  end

  defp filtered(groups, ""), do: groups

  # Every word has to appear somewhere in an exercise's name, muscle group,
  # anatomy or category, so "upper pull" and "lats" both find a pull-up.
  defp filtered(groups, query) do
    words = query |> String.downcase() |> String.split(" ")

    groups
    |> Enum.map(fn {group, exercises} ->
      {group, Enum.filter(exercises, &matches?(&1, group, words))}
    end)
    |> Enum.reject(fn {_group, exercises} -> exercises == [] end)
  end

  defp matches?(exercise, group, words) do
    haystack =
      [
        exercise.name,
        group,
        exercise.muscle_group,
        exercise.anatomy,
        exercise.functional_category
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join(" ", &String.downcase(to_string(&1)))

    Enum.all?(words, &String.contains?(haystack, &1))
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

        <form
          phx-change="filter"
          phx-submit="filter"
          id="wiki-search"
          class="wiki-search"
          role="search"
        >
          <input
            type="search"
            name="q"
            value={@query}
            class="wiki-search-input"
            placeholder="Find an exercise, a muscle, a movement"
            aria-label="Search the exercise wiki"
            phx-debounce="150"
            autocomplete="off"
          />
        </form>

        <p :if={@query != "" and @grouped_exercises == []} class="wiki-search-note" role="status">
          No exercise matches “{@query}”.
          <a href={~p"/search?#{[q: @query]}"}>Search the whole site</a>
        </p>

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

        <p :if={@all_exercises == []} class="wiki-index-empty">No exercises indexed yet.</p>
      </div>
    </div>
    """
  end
end
