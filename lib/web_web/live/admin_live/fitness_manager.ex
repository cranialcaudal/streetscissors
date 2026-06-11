defmodule WebWeb.AdminLive.FitnessManager do
  use WebWeb, :live_view

  alias Web.Fitness.Vault

  def mount(_params, session, socket) do
    if session["admin_user"] do
      days = Vault.list_days()
      exercises = Vault.list_all_exercises()
      posts = Vault.list_blog_posts()
      muscle_groups = Vault.list_muscle_groups()

      {:ok,
       assign(socket,
         page_title: "Fitness Manager | Streetscissors",
         # "days", "exercises", "posts"
         active_tab: "exercises",
         days: days,
         exercises: exercises,
         posts: posts,
         muscle_groups: muscle_groups,
         editor_mode: nil,
         editing_item: nil,
         form_data: %{}
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  # --- Handlers ---
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: tab, editor_mode: nil)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editor_mode: nil, editing_item: nil)}
  end

  def handle_event("new_item", %{"type" => type}, socket) do
    case type do
      "day" ->
        {:noreply,
         assign(socket,
           editor_mode: :day,
           form_data: %{
             "slug" => "",
             "title" => "",
             "description" => "",
             "tab" => "",
             "content" => ""
           }
         )}

      "exercise" ->
        {:noreply,
         assign(socket,
           editor_mode: :exercise,
           form_data: %{
             "slug" => "",
             "title" => "",
             "muscle_group" => "",
             "anatomy" => "",
             "functional_category" => "",
             "short_description" => "",
             "content" => ""
           }
         )}

      "post" ->
        {:noreply,
         assign(socket,
           editor_mode: :post,
           form_data: %{
             "slug" => "",
             "title" => "",
             "date" => Date.to_string(Date.utc_today()),
             "content" => ""
           }
         )}
    end
  end

  def handle_event("edit_day", %{"slug" => slug}, socket) do
    case Vault.get_day_raw(slug) do
      {:ok, meta, content} ->
        form = %{
          "slug" => slug,
          "title" => meta["title"] || "",
          "description" => meta["description"] || "",
          "tab" => meta["tab"] || "",
          "content" => content
        }

        {:noreply,
         assign(socket, editor_mode: :day, editing_item: %{slug: slug}, form_data: form)}

      :error ->
        {:noreply, put_flash(socket, :error, "Day not found.")}
    end
  end

  def handle_event("edit_exercise", %{"slug" => slug}, socket) do
    case Vault.get_exercise_raw(slug) do
      {:ok, raw_data, content} ->
        form = %{
          "slug" => slug,
          "title" => raw_data.name,
          "muscle_group" => raw_data.muscle_group,
          "anatomy" => raw_data.anatomy || "",
          "functional_category" => raw_data.functional_category || "",
          "thumbnail_url" => raw_data.thumbnail_url || "",
          "video_url" => raw_data.video_url || "",
          "short_description" => raw_data.short_description || "",
          "content" => content,
          # Track for folder moves
          "original_muscle_group" => raw_data.muscle_group
        }

        {:noreply,
         assign(socket, editor_mode: :exercise, editing_item: %{slug: slug}, form_data: form)}

      :error ->
        {:noreply, put_flash(socket, :error, "Exercise not found.")}
    end
  end

  def handle_event("edit_post", %{"slug" => slug}, socket) do
    case Vault.get_blog_post_raw(slug) do
      {:ok, meta, content} ->
        form = %{
          "slug" => slug,
          "title" => meta["title"] || "",
          "date" => meta["date"] || "",
          "content" => content
        }

        {:noreply,
         assign(socket, editor_mode: :post, editing_item: %{slug: slug}, form_data: form)}

      :error ->
        {:noreply, put_flash(socket, :error, "Post not found.")}
    end
  end

  def handle_event("save_day", %{"day" => params}, socket) do
    slug = params["slug"]

    if slug == "" do
      {:noreply, put_flash(socket, :error, "Slug is required.")}
    else
      Vault.update_day(slug, params)

      {:noreply,
       socket
       |> put_flash(:info, "Day saved.")
       |> assign(editor_mode: nil, days: Vault.list_days())}
    end
  end

  def handle_event("save_exercise", %{"exercise" => params}, socket) do
    slug = params["slug"]

    if slug == "" do
      {:noreply, put_flash(socket, :error, "Slug is required.")}
    else
      old_group = params["original_muscle_group"]
      Vault.update_exercise(slug, old_group, params)

      # Reload exercises and muscle groups
      {:noreply,
       socket
       |> put_flash(:info, "Exercise saved.")
       |> assign(
         editor_mode: nil,
         exercises: Vault.list_all_exercises(),
         muscle_groups: Vault.list_muscle_groups()
       )}
    end
  end

  def handle_event("save_post", %{"post" => params}, socket) do
    slug = params["slug"]

    if slug == "" do
      {:noreply, put_flash(socket, :error, "Slug is required.")}
    else
      Vault.update_blog_post(slug, params)

      {:noreply,
       socket
       |> put_flash(:info, "Post saved.")
       |> assign(editor_mode: nil, posts: Vault.list_blog_posts())}
    end
  end

  def handle_event("delete_exercise", %{"slug" => slug, "group" => group}, socket) do
    Vault.delete_exercise(slug, group)

    {:noreply,
     socket
     |> put_flash(:info, "Exercise deleted.")
     |> assign(exercises: Vault.list_all_exercises())}
  end

  def handle_event("delete_post", %{"slug" => slug}, socket) do
    Vault.delete_blog_post(slug)

    {:noreply,
     socket |> put_flash(:info, "Post deleted.") |> assign(posts: Vault.list_blog_posts())}
  end

  # --- Rendering ---
  def render(assigns) do
    ~H"""
    <div class="mission-control">
      <main class="workspace">
        <%= if @editor_mode do %>
          {render_editor(assigns)}
        <% else %>
          <header class="workspace-header">
            <div class="header-info">
              <h1 class="workspace-title">Fitness Database</h1>
              <p class="workspace-subtitle">Manage routines, biomechanics, and intelligence.</p>
            </div>

            <div class="header-actions">
              <button
                phx-click="switch_tab"
                phx-value-tab="exercises"
                class={["action-btn", @active_tab == "exercises" && "accent"]}
              >
                <i class="fas fa-dumbbell"></i> Wiki
              </button>
              <button
                phx-click="switch_tab"
                phx-value-tab="days"
                class={["action-btn", @active_tab == "days" && "accent"]}
              >
                <.icon name="hero-calendar" class="size-4" /> Regimen
              </button>
              <button
                phx-click="switch_tab"
                phx-value-tab="posts"
                class={["action-btn", @active_tab == "posts" && "accent"]}
              >
                <.icon name="hero-newspaper" class="size-4" /> Intelligence
              </button>
            </div>
          </header>

          <div class="workspace-content">
            <%= case @active_tab do %>
              <% "exercises" -> %>
                {render_exercises(assigns)}
              <% "days" -> %>
                {render_days(assigns)}
              <% "posts" -> %>
                {render_posts(assigns)}
            <% end %>
          </div>
        <% end %>
      </main>

      <style>
        @import url('https://fonts.googleapis.com/css2?family=Outfit:wght@300;500;800&family=JetBrains+Mono:wght@400;700&display=swap');

        :root {
          --panel-bg: rgba(10, 10, 12, 0.98);
          --border-color: rgba(255, 255, 255, 0.08);
          --accent-primary: #4ade80; /* Fitness Green */
          --accent-secondary: #00f2ff;
          --text-muted: #666;
          --glass-surface: rgba(255, 255, 255, 0.02);
        }

        .mission-control { display: flex; height: 100%; min-height: 80vh; background: #000; color: #fff; font-family: 'Outfit', sans-serif; overflow: hidden; }

        .workspace { flex: 1; display: flex; flex-direction: column; overflow: hidden; background: radial-gradient(circle at 70% 20%, rgba(74, 222, 128, 0.05), transparent 50%), #000; }
        .workspace-header { padding: 3rem 4rem; display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid var(--border-color); }
        .workspace-title { font-size: 2.2rem; font-weight: 800; margin: 0; letter-spacing: -1px; background: linear-gradient(to bottom, #fff, #888); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
        .workspace-subtitle { color: #555; margin: 0.5rem 0 0 0; font-size: 1rem; }
        .header-actions { display: flex; gap: 0.5rem; align-items: center; }
        .action-btn { padding: 0.8rem 1.5rem; border-radius: 30px; font-weight: 800; cursor: pointer; border: 1px solid rgba(255,255,255,0.1); display: flex; align-items: center; gap: 0.8rem; transition: all 0.3s; font-size: 0.9rem; letter-spacing: 0.5px; background: transparent; color: #aaa; }
        .action-btn.accent { background: var(--accent-primary); border: none; color: #000; }
        .action-btn.accent:hover { transform: scale(1.02); box-shadow: 0 10px 30px rgba(74, 222, 128, 0.2); }
        .workspace-content { flex: 1; overflow-y: auto; padding: 3rem 4rem; position: relative; }

        .items-list { display: grid; grid-template-columns: repeat(auto-fill, minmax(320px, 1fr)); gap: 2rem; }
        .writing-item { background: #080808; border: 1px solid var(--border-color); border-radius: 20px; padding: 2.5rem; display: flex; flex-direction: column; min-height: 200px; position: relative; transition: all 0.4s cubic-bezier(0.16, 1, 0.3, 1); }
        .writing-item:hover { border-color: rgba(74, 222, 128, 0.3); transform: translateY(-8px); background: #0c0c0e; box-shadow: 0 30px 60px rgba(0,0,0,0.5); }
        .item-type { font-size: 0.7rem; color: #444; margin-bottom: 0.8rem; letter-spacing: 2px; font-weight: 800; display: flex; align-items: center; gap: 0.6rem; }
        .item-title { font-size: 1.4rem; font-weight: 500; margin: 0 0 1.5rem 0; color: #fff; line-height: 1.25; }
        .item-meta { display: flex; align-items: center; justify-content: space-between; margin-top: auto; border-top: 1px solid rgba(255,255,255,0.03); padding-top: 1.2rem; }
        .pill-sm { font-size: 0.7rem; color: #888; font-weight: 800; text-transform: uppercase; letter-spacing: 1px; }
        .mtime { font-size: 0.75rem; color: #333; }
        .item-actions { position: absolute; top: 1.5rem; right: 1.5rem; display: flex; gap: 0.8rem; opacity: 0; transition: opacity 0.3s; }
        .writing-item:hover .item-actions { opacity: 1; }
        .icon-btn { width: 36px; height: 36px; border-radius: 10px; background: #000; border: 1px solid #222; color: #666; cursor: pointer; transition: all 0.2s; display: flex; align-items: center; justify-content: center; font-size: 0.9rem; }
        .icon-btn:hover { color: #fff; border-color: #444; background: #111; }
        .icon-btn.delete:hover { border-color: #f00; color: #f00; }

        .list-header-row { display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem; border-bottom: 1px solid var(--border-color); padding-bottom: 1rem; }
        .list-header-row h2 { margin: 0; font-size: 1.4rem; color: var(--accent-primary); }

        .editor-top-bar { display: flex; justify-content: space-between; align-items: center; padding: 1.5rem 2rem; background: #111; border-bottom: 1px solid var(--border-color); }
        .editor-top-bar .meta { display: flex; align-items: center; gap: 1rem; }
        .editor-top-bar .label { font-family: 'JetBrains Mono'; font-size: 0.75rem; color: #666; background: #222; padding: 0.3rem 0.6rem; border-radius: 4px; }
        .editor-top-bar .title { font-size: 1.2rem; font-weight: 600; }
        .editor-top-bar .actions { display: flex; gap: 1rem; }
        .editor-btn { padding: 0.6rem 1.2rem; border-radius: 6px; font-weight: 800; cursor: pointer; border: 1px solid rgba(255,255,255,0.1); font-size: 0.85rem; letter-spacing: 1px; background: transparent; color: #fff; transition: 0.3s; }
        .editor-btn.accent { background: var(--accent-primary); border: none; color: #000; }
        .editor-btn.accent:hover { opacity: 0.9; }

        .editor-scaffold { display: flex; flex-direction: column; height: calc(100vh - 80px); }
        .editor-controls { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 1rem; padding: 1.5rem 2rem; background: #080808; border-bottom: 1px solid var(--border-color); }
        .input-group { display: flex; flex-direction: column; gap: 0.5rem; }
        .input-group label { font-family: 'JetBrains Mono'; font-size: 0.7rem; color: #666; letter-spacing: 1px; }
        .sc-input { background: #111; border: 1px solid #222; color: #fff; padding: 0.8rem; border-radius: 6px; font-family: 'Outfit'; outline: none; }
        .sc-input:focus { border-color: var(--accent-primary); }
        .markdown-workspace { flex: 1; padding: 0; }
        .main-textarea { width: 100%; height: 100%; min-height: 500px; background: #050505; color: #e5e5e5; border: none; padding: 2rem; font-family: 'JetBrains Mono'; font-size: 0.95rem; line-height: 1.6; resize: none; outline: none; }
      </style>
    </div>
    """
  end

  defp render_exercises(assigns) do
    ~H"""
    <div class="list-header-row">
      <h2>Exercise Wiki</h2>
      <button phx-click="new_item" phx-value-type="exercise" class="action-btn accent">
        + New Exercise
      </button>
    </div>
    <%= for {group, exercises} <- @exercises do %>
      <h3 style="margin-top: 2rem; margin-bottom: 1rem; color: #888; text-transform: uppercase; font-size: 0.9rem; letter-spacing: 2px;">
        {group}
      </h3>
      <div class="items-list">
        <%= for ex <- exercises do %>
          <div class="writing-item manuscript">
            <div class="item-main">
              <div class="item-type">
                <i class="fas fa-dumbbell"></i> {ex.functional_category || "Uncategorized"}
              </div>
              <h3 class="item-title">{ex.name}</h3>
              <div class="item-meta">
                <span class="tag pill-sm">{ex.anatomy || "Unknown Anatomy"}</span>
              </div>
            </div>
            <div class="item-actions">
              <button phx-click="edit_exercise" phx-value-slug={ex.slug} class="icon-btn">
                <.icon name="hero-pencil-square" class="size-4" />
              </button>
              <button
                phx-click="delete_exercise"
                phx-value-slug={ex.slug}
                phx-value-group={group}
                class="icon-btn delete"
                phx-confirm="Delete exercise?"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
    """
  end

  defp render_days(assigns) do
    ~H"""
    <div class="list-header-row">
      <h2>Weekly Regimen</h2>
      <button phx-click="new_item" phx-value-type="day" class="action-btn accent">+ New Day</button>
    </div>
    <div class="items-list">
      <%= for day <- @days do %>
        <div class="writing-item manuscript">
          <div class="item-main">
            <div class="item-type"><.icon name="hero-calendar-days" class="size-4" /> MODULE</div>
            <h3 class="item-title">{day.title}</h3>
            <div class="item-meta">
              <span class="tag pill-sm">{day.tab}</span>
            </div>
          </div>
          <div class="item-actions">
            <button phx-click="edit_day" phx-value-slug={day.slug} class="icon-btn">
              <.icon name="hero-pencil-square" class="size-4" />
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_posts(assigns) do
    ~H"""
    <div class="list-header-row">
      <h2>Fitness Intelligence</h2>
      <button phx-click="new_item" phx-value-type="post" class="action-btn accent">+ New Post</button>
    </div>
    <div class="items-list">
      <%= for post <- @posts do %>
        <div class="writing-item manuscript">
          <div class="item-main">
            <div class="item-type"><.icon name="hero-newspaper" class="size-4" /> REPORT</div>
            <h3 class="item-title">{post.title}</h3>
            <div class="item-meta">
              <span class="tag pill-sm">{post.date}</span>
            </div>
          </div>
          <div class="item-actions">
            <button phx-click="edit_post" phx-value-slug={post.slug} class="icon-btn">
              <.icon name="hero-pencil-square" class="size-4" />
            </button>
            <button
              phx-click="delete_post"
              phx-value-slug={post.slug}
              class="icon-btn delete"
              phx-confirm="Delete post?"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_editor(assigns) do
    ~H"""
    <div class="full-screen-editor">
      <header class="editor-top-bar">
        <div class="meta">
          <span class="label">
            <%= case @editor_mode do %>
              <% :exercise -> %>
                EXERCISE
              <% :day -> %>
                DAY
              <% :post -> %>
                REPORT
            <% end %>
          </span>
          <span class="title">{@form_data["title"] || "New Item"}</span>
        </div>
        <div class="actions">
          <button phx-click="cancel_edit" class="editor-btn secondary">CANCEL</button>
          <button form="editor-form" type="submit" class="editor-btn accent">SAVE</button>
        </div>
      </header>

      <div class="editor-scaffold">
        <form id="editor-form" phx-submit={"save_#{@editor_mode}"}>
          <div class="editor-controls">
            <div class="input-group">
              <label>SLUG (filename)</label>
              <input
                name={"#{@editor_mode}[slug]"}
                value={@form_data["slug"]}
                class="sc-input"
                required
              />
            </div>
            <div class="input-group">
              <label>TITLE</label>
              <input
                name={"#{@editor_mode}[title]"}
                value={@form_data["title"]}
                class="sc-input"
                required
              />
            </div>

            <%= if @editor_mode == :exercise do %>
              <div class="input-group">
                <label>MUSCLE GROUP (FOLDER)</label>
                <input
                  name="exercise[muscle_group]"
                  value={@form_data["muscle_group"]}
                  list="muscle-groups"
                  class="sc-input"
                  placeholder="e.g. chest"
                  required
                />
                <datalist id="muscle-groups">
                  <%= for group <- @muscle_groups do %>
                    <option value={group}></option>
                  <% end %>
                </datalist>
                <input
                  type="hidden"
                  name="exercise[original_muscle_group]"
                  value={@form_data["original_muscle_group"]}
                />
              </div>
              <div class="input-group">
                <label>ANATOMY</label>
                <input
                  name="exercise[anatomy]"
                  value={@form_data["anatomy"]}
                  class="sc-input"
                  placeholder="e.g. Pectoralis Major"
                />
              </div>
              <div class="input-group">
                <label>FUNCTIONAL CATEGORY</label>
                <input
                  name="exercise[functional_category]"
                  value={@form_data["functional_category"]}
                  class="sc-input"
                  placeholder="e.g. Absolute Strength"
                />
              </div>
              <div class="input-group">
                <label>THUMBNAIL URL</label>
                <input
                  name="exercise[thumbnail_url]"
                  value={@form_data["thumbnail_url"]}
                  class="sc-input"
                />
              </div>
              <div class="input-group">
                <label>VIDEO URL</label>
                <input name="exercise[video_url]" value={@form_data["video_url"]} class="sc-input" />
              </div>
              <div class="input-group" style="grid-column: 1 / -1;">
                <label>SHORT DESCRIPTION</label>
                <input
                  name="exercise[short_description]"
                  value={@form_data["short_description"]}
                  class="sc-input"
                />
              </div>
            <% end %>

            <%= if @editor_mode == :day do %>
              <div class="input-group">
                <label>TAB NAME</label>
                <input name="day[tab]" value={@form_data["tab"]} class="sc-input" required />
              </div>
              <div class="input-group" style="grid-column: 1 / -1;">
                <label>DESCRIPTION</label>
                <input name="day[description]" value={@form_data["description"]} class="sc-input" />
              </div>
            <% end %>

            <%= if @editor_mode == :post do %>
              <div class="input-group">
                <label>DATE (YYYY-MM-DD)</label>
                <input name="post[date]" value={@form_data["date"]} class="sc-input" />
              </div>
            <% end %>
          </div>

          <div class="markdown-workspace">
            <textarea name={"#{@editor_mode}[content]"} class="main-textarea"><%= @form_data["content"] %></textarea>
          </div>
        </form>
      </div>
    </div>
    """
  end
end
