defmodule WebWeb.FitnessLive.Show do
  use WebWeb, :live_view

  alias Web.Fitness.Vault

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"slug" => slug} = params, _, socket) do
    case Vault.get_exercise_by_slug(slug) do
      {:ok, exercise} ->
        # Check for tag overlay params
        {tag_overlay, tag_label, tag_exercises} =
          case {params["tag_type"], params["tag"]} do
            {type, value} when is_binary(type) and is_binary(value) and value != "" ->
              compute_tag_filter(type, value)

            _ ->
              {nil, nil, []}
          end

        {:noreply,
         socket
         |> assign(:page_title, exercise.name)
         |> assign(:return_to, "/fitness/wiki")
         |> assign(:return_label, "return to exercise wiki")
         |> assign(:exercise, exercise)
         |> assign_figure(exercise)
         |> assign(:tag_overlay, tag_overlay)
         |> assign(:tag_label, tag_label)
         |> assign(:tag_exercises, tag_exercises)}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Exercise not found.")
         |> push_navigate(to: "/fitness/wiki")}
    end
  end

  # The exercise's figure: its film when there is one of the figure as it
  # now stands (`Web.Fitness.Clip`), else the flat drawing baked from the
  # same file, which costs a solve and is always current. A file that fails
  # `Web.Fitness.Figure.build/1` draws nothing here and is listed on
  # /admin/health with what is wrong with it.
  defp assign_figure(socket, exercise) do
    clip = Web.Fitness.Clip.find(exercise.slug, exercise.anatomy)

    socket
    |> assign(:clip, clip)
    |> assign(:figure, if(clip, do: nil, else: drawing(exercise.slug)))
    |> assign(
      :muscles,
      exercise.anatomy |> Web.Fitness.Clip.muscles() |> Enum.map(&Web.Fitness.Clip.label/1)
    )
  end

  defp drawing(slug) do
    case Web.Fitness.Figure.load(slug) do
      {:ok, figure} -> figure
      _ -> nil
    end
  end

  defp compute_tag_filter(type, value) do
    all = Vault.list_all_exercises()

    {filtered, label} =
      case type do
        "group" ->
          result = Enum.filter(all, fn {group, _} -> group == value end)

          {result,
           value
           |> String.replace("-", " ")
           |> String.split(" ")
           |> Enum.map(&String.capitalize/1)
           |> Enum.join(" ")}

        "category" ->
          result =
            Enum.map(all, fn {group, exercises} ->
              filtered = Enum.filter(exercises, fn ex -> ex.functional_category == value end)
              {group, filtered}
            end)
            |> Enum.reject(fn {_, exercises} -> exercises == [] end)

          {result, value}

        _ ->
          {all, "All Exercises"}
      end

    {type, label, filtered}
  end

  @impl true
  def handle_event("close_tag_overlay", _, socket) do
    slug = socket.assigns.exercise.slug
    {:noreply, push_patch(socket, to: ~p"/fitness/wiki/#{slug}")}
  end

  defp format_group(slug) do
    slug
    |> String.replace("-", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp anatomy_matches_group?(exercise) do
    a = (exercise.anatomy || "") |> String.downcase() |> String.replace("-", " ") |> String.trim()

    g =
      (exercise.muscle_group || "")
      |> String.downcase()
      |> String.replace("-", " ")
      |> String.trim()

    a == g
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :show_blue_tag, not anatomy_matches_group?(assigns.exercise))

    ~H"""
    <div class="container steel wiki-page">
      <h1 class="theme-title wiki-title">{@exercise.name}</h1>
      <p :if={@exercise.short_description} class="wiki-lede">{@exercise.short_description}</p>

      <WebWeb.FitnessFigure.figure
        :if={@clip || @figure}
        id={"figure-#{@exercise.slug}"}
        figure={@figure}
        clip={@clip}
        muscles={@muscles}
        label={@exercise.name}
      />

      <%!-- Each tag opens the exercises that share it, over this page; the
            choice is in the address, so Back closes it. --%>
      <div class="wiki-tags">
        <.link
          :if={@exercise.anatomy}
          patch={~p"/fitness/wiki/#{@exercise.slug}?tag_type=group&tag=#{@exercise.muscle_group}"}
          class="wiki-tag wiki-tag--anatomy"
        >
          <.icon name="hero-heart" class="size-3" />
          {@exercise.anatomy}
        </.link>
        <.link
          :if={@exercise.functional_category}
          patch={
            ~p"/fitness/wiki/#{@exercise.slug}?tag_type=category&tag=#{@exercise.functional_category}"
          }
          class="wiki-tag wiki-tag--category"
        >
          <.icon name="hero-rectangle-stack" class="size-3" />
          {@exercise.functional_category}
        </.link>
        <.link
          :if={@show_blue_tag}
          patch={~p"/fitness/wiki/#{@exercise.slug}?tag_type=group&tag=#{@exercise.muscle_group}"}
          class="wiki-tag wiki-tag--group"
        >
          <.icon name="hero-book-open" class="size-3" />
          {format_group(@exercise.muscle_group)}
        </.link>
      </div>

      <div class="glass-panel markdown-body wiki-body">
        {raw(@exercise.html)}
      </div>

      <%!-- Verified PubMed / DOI citations, resolved from the shared bibliography. --%>
      <section :if={@exercise.references != []} class="glass-panel wiki-sources" aria-label="Sources">
        <h3 class="wiki-sources-title">Sources</h3>
        <ol>
          <li :for={ref <- @exercise.references}>
            {ref["authors"]}
            <span :if={ref["year"] not in [nil, ""]}>({ref["year"]}).</span>
            <span class="wiki-source-title">{ref["title"]}.</span>
            <em :if={ref["journal"] not in [nil, ""]} class="wiki-source-journal">
              {ref["journal"]}.
            </em>
            <div class="wiki-source-links">
              <a
                :if={ref["pmid"] not in [nil, ""]}
                href={"https://pubmed.ncbi.nlm.nih.gov/#{ref["pmid"]}/"}
                target="_blank"
                rel="noopener noreferrer"
              >
                PubMed: {ref["pmid"]}
              </a>
              <a
                :if={ref["doi"] not in [nil, ""]}
                href={"https://doi.org/#{ref["doi"]}"}
                target="_blank"
                rel="noopener noreferrer"
              >
                DOI: {ref["doi"]}
              </a>
            </div>
          </li>
        </ol>
      </section>

      <footer class="wiki-foot">
        <span class="wiki-foot-label">Anatomical reference</span>
        <a
          href="https://www.nlm.nih.gov/research/visible/visible_human.html"
          target="_blank"
          rel="noopener noreferrer"
        >
          The Visible Human Project, National Library of Medicine
        </a>
        <a
          href="https://www.nlm.nih.gov/research/visible/visible_gallery.html"
          target="_blank"
          rel="noopener noreferrer"
        >
          Cross-section gallery
        </a>
      </footer>
    </div>

    <div :if={@tag_overlay} class="wiki-overlay steel">
      <div class="wiki-overlay-shade" phx-click="close_tag_overlay"></div>
      <div class="glass-panel wiki-overlay-panel">
        <header class="wiki-overlay-head">
          <div>
            <h3 class="wiki-overlay-title">Related exercises</h3>
            <span class="wiki-overlay-by">Filtered by <b>{@tag_label}</b></span>
          </div>
          <button
            type="button"
            class="wiki-overlay-close"
            phx-click="close_tag_overlay"
            aria-label="Close"
          >
            ✕
          </button>
        </header>

        <div :for={{group, exercises} <- @tag_exercises} class="wiki-overlay-group">
          <h4>{format_group(group)}</h4>
          <ul>
            <li :for={ex <- exercises}>
              <.link
                navigate={~p"/fitness/wiki/#{ex.slug}"}
                class={["wiki-overlay-link", ex.slug == @exercise.slug && "is-current"]}
              >
                <span>{ex.name}</span>
                <small :if={ex.slug == @exercise.slug}>This page</small>
                <small :if={
                  (ex.slug != @exercise.slug and ex.functional_category) && @tag_overlay == "group"
                }>
                  {ex.functional_category}
                </small>
              </.link>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end
end
