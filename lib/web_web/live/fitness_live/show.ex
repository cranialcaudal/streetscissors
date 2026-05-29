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
         |> assign(:return_to, "/fitness?view=wiki")
         |> assign(:return_label, "return to exercise wiki")
         |> assign(:exercise, exercise)
         |> assign(:tag_overlay, tag_overlay)
         |> assign(:tag_label, tag_label)
         |> assign(:tag_exercises, tag_exercises)}

      :error ->
        {:noreply,
         socket
         |> put_flash(:error, "Exercise not found.")
         |> push_navigate(to: "/fitness")}
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
    {:noreply, push_patch(socket, to: ~p"/fitness/#{slug}")}
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
    <div class="container" style="max-width: 860px; margin: 0 auto;">
      <header class="theme-header" style="margin-bottom: 2rem; display: none;">
        <h1 class="theme-title">{@exercise.name}</h1>
      </header>
      <h1 class="theme-title" style="margin-bottom: 2rem;">{@exercise.name}</h1>

      <%!-- VIDEO LEAD --%>
      <%= if @exercise.video_url do %>
        <div style="width: 100%; aspect-ratio: 16/9; border-radius: 10px; overflow: hidden; margin-bottom: 1.5rem; border: 1px solid rgba(255,102,0,0.2);">
          <iframe
            width="100%"
            height="100%"
            src={@exercise.video_url}
            title={@exercise.name}
            frameborder="0"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
            allowfullscreen
          >
          </iframe>
        </div>
      <% end %>

      <%!-- CONCEPT TAGS (clickable → pushes URL for proper back-button) --%>
      <div style="display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 2.5rem;">
        <%= if @exercise.anatomy do %>
          <.link
            patch={~p"/fitness/#{@exercise.slug}?tag_type=group&tag=#{@exercise.muscle_group}"}
            style="
              display: inline-flex; align-items: center; gap: 0.4rem; text-decoration: none;
              background: rgba(255,102,0,0.1); border: 1px solid rgba(255,102,0,0.3);
              color: var(--theme-color); padding: 0.35rem 0.85rem; border-radius: 20px;
              font-size: 0.8rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px;
              cursor: pointer; transition: background 0.2s, transform 0.15s;
            "
          >
            <i class="fas fa-dna" style="font-size: 0.7rem;"></i>
            {@exercise.anatomy}
          </.link>
        <% end %>
        <%= if @exercise.functional_category do %>
          <.link
            patch={
              ~p"/fitness/#{@exercise.slug}?tag_type=category&tag=#{@exercise.functional_category}"
            }
            style="
              display: inline-flex; align-items: center; gap: 0.4rem; text-decoration: none;
              background: rgba(74,222,128,0.08); border: 1px solid rgba(74,222,128,0.25);
              color: #4ade80; padding: 0.35rem 0.85rem; border-radius: 20px;
              font-size: 0.8rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px;
              cursor: pointer; transition: background 0.2s, transform 0.15s;
            "
          >
            <i class="fas fa-layer-group" style="font-size: 0.7rem;"></i>
            {@exercise.functional_category}
          </.link>
        <% end %>
        <%= if @show_blue_tag do %>
          <.link
            patch={~p"/fitness/#{@exercise.slug}?tag_type=group&tag=#{@exercise.muscle_group}"}
            style="
              display: inline-flex; align-items: center; gap: 0.4rem; text-decoration: none;
              background: rgba(96,165,250,0.08); border: 1px solid rgba(96,165,250,0.25);
              color: #60a5fa; padding: 0.35rem 0.85rem; border-radius: 20px;
              font-size: 0.8rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px;
              cursor: pointer; transition: background 0.2s, transform 0.15s;
            "
          >
            <i class="fas fa-book-medical" style="font-size: 0.7rem;"></i>
            {format_group(@exercise.muscle_group)}
          </.link>
        <% end %>
      </div>

      <%!-- BODY CONTENT --%>
      <div
        class="glass-panel markdown-body"
        style="padding: 2.5rem; line-height: 1.85; font-size: 1.05rem;"
      >
        {raw(@exercise.html)}
      </div>

      <%!-- VHP FOOTER REFERENCE --%>
      <footer style="margin-top: 2.5rem; padding: 1.25rem 1.5rem; border-top: 1px solid rgba(255,255,255,0.06); display: flex; align-items: center; gap: 0.75rem;">
        <span style="color: #555; font-size: 0.75rem; letter-spacing: 0.5px; text-transform: uppercase;">
          Anatomical Reference
        </span>
        <a
          href="https://www.nlm.nih.gov/research/visible/visible_human.html"
          target="_blank"
          rel="noopener noreferrer"
          style="color: #888; font-size: 0.8rem; text-decoration: none; border-bottom: 1px dotted #555; transition: color 0.2s;"
        >
          🔬 The Visible Human Project — National Library of Medicine
        </a>
        <span style="color: #444; font-size: 0.7rem;">·</span>
        <a
          href="https://www.nlm.nih.gov/research/visible/visible_gallery.html"
          target="_blank"
          rel="noopener noreferrer"
          style="color: #888; font-size: 0.8rem; text-decoration: none; border-bottom: 1px dotted #555; transition: color 0.2s;"
        >
          VHP Cross-Section Gallery
        </a>
      </footer>
    </div>

    <%!-- TAG POPOUT OVERLAY (stays on the exercise page) --%>
    <%= if @tag_overlay do %>
      <div
        class="exercise-overlay-container"
        style="position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; display: flex; align-items: center; justify-content: center; z-index: 20000; padding: 2rem;"
      >
        <div
          phx-click="close_tag_overlay"
          style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.75); backdrop-filter: blur(5px);"
        >
        </div>
        <div
          class="glass-panel"
          style="position: relative; z-index: 1; max-height: 80vh; overflow-y: auto; width: 100%; max-width: 600px; padding: 2rem; animation: zoomIn 0.2s ease-out;"
        >
          <header style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(255,102,0,0.2); padding-bottom: 1rem; margin-bottom: 1.5rem;">
            <div>
              <h3 style="font-family: var(--font-heading); font-size: 1.4rem; margin: 0; color: var(--theme-color); text-transform: uppercase; letter-spacing: 1.5px;">
                Related Exercises
              </h3>
              <div style="display: flex; align-items: center; gap: 0.5rem; margin-top: 0.5rem;">
                <span style="color: #888; font-size: 0.75rem;">Filtered by:</span>
                <span style={"
                  padding: 0.2rem 0.6rem; border-radius: 12px; font-size: 0.7rem;
                  text-transform: uppercase; letter-spacing: 0.5px;
                  #{if @tag_overlay == "group", do: "background: rgba(255,102,0,0.1); border: 1px solid rgba(255,102,0,0.3); color: var(--theme-color);", else: "background: rgba(74,222,128,0.08); border: 1px solid rgba(74,222,128,0.25); color: #4ade80;"}
                "}>
                  {@tag_label}
                </span>
              </div>
            </div>
            <button
              phx-click="close_tag_overlay"
              style="background: transparent; border: 1px solid #555; color: #888; padding: 0.4rem; border-radius: 50%; width: 28px; height: 28px; display: flex; align-items: center; justify-content: center; cursor: pointer; font-size: 0.7rem;"
            >
              ✕
            </button>
          </header>

          <%= for {group, exercises} <- @tag_exercises do %>
            <div style="margin-bottom: 1.5rem;">
              <h4 style="color: var(--theme-color); font-size: 0.8rem; text-transform: uppercase; letter-spacing: 1px; border-left: 3px solid var(--theme-color); padding-left: 0.6rem; margin-bottom: 0.75rem;">
                {format_group(group)}
              </h4>
              <ul style="list-style: none; padding: 0; display: flex; flex-direction: column; gap: 0.4rem;">
                <%= for ex <- exercises do %>
                  <li>
                    <.link
                      navigate={~p"/fitness/#{ex.slug}"}
                      style={"
                      display: flex; justify-content: space-between; align-items: center;
                      padding: 0.5rem 0.75rem; background: rgba(255,255,255,0.02);
                      border-radius: 6px; border: 1px solid rgba(255,255,255,0.05);
                      transition: all 0.2s; font-size: 0.9rem; color: #aaa; text-decoration: none;
                      #{if ex.slug == @exercise.slug, do: "border-color: var(--theme-color); color: var(--theme-color); background: rgba(255,102,0,0.05);", else: ""}
                    "}
                    >
                      <span>{ex.name}</span>
                      <%= if ex.slug == @exercise.slug do %>
                        <span style="font-size: 0.65rem; color: var(--theme-color); opacity: 0.6;">
                          CURRENT
                        </span>
                      <% end %>
                      <%= if ex.functional_category && @tag_overlay == "group" do %>
                        <span style="font-size: 0.6rem; color: #4ade80; text-transform: uppercase; letter-spacing: 0.5px; opacity: 0.5;">
                          {ex.functional_category}
                        </span>
                      <% end %>
                    </.link>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </div>
      </div>
    <% end %>

    <style>
      .markdown-body p { margin-bottom: 1.25rem; color: #ccc; }
      .markdown-body h3 { color: var(--theme-color); margin-top: 2.5rem; margin-bottom: 1rem; font-size: 1.15rem; text-transform: uppercase; letter-spacing: 1px; border-bottom: 1px solid rgba(255,102,0,0.15); padding-bottom: 0.5rem; }
      .markdown-body em { color: #999; }
      .markdown-body strong { color: #fff; }
      .markdown-body a { color: var(--theme-color); text-decoration: none; border-bottom: 1px dotted rgba(255,102,0,0.3); transition: border-color 0.2s; }
      .markdown-body a:hover { border-bottom-color: var(--theme-color); }
      .markdown-body blockquote { border-left: 3px solid rgba(255,102,0,0.3); padding: 0.75rem 1.25rem; margin: 1.5rem 0; background: rgba(255,255,255,0.02); border-radius: 0 6px 6px 0; color: #aaa; font-style: italic; }
      .markdown-body ul { padding-left: 1.5rem; margin-bottom: 1.25rem; }
      .markdown-body li { color: #ccc; margin-bottom: 0.5rem; }
      @keyframes zoomIn { from { opacity: 0; transform: scale(0.95); } to { opacity: 1; transform: scale(1); } }
    </style>
    """
  end
end
