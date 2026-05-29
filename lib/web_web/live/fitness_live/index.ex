defmodule WebWeb.FitnessLive.Index do
  use WebWeb, :live_view

  alias Web.Fitness.Vault

  @impl true
  def mount(_params, session, socket) do
    is_admin = session["admin_user"] == true
    days = Vault.list_days()

    {:ok,
     socket
     |> assign(:is_admin, is_admin)
     |> assign(:days, days)
     |> assign(:active_day, nil)
     |> assign(:day_html, nil)
     |> assign(:wiki_open, false)
     |> assign(:grouped_exercises, [])
     |> assign(:latest_biometric, Web.Fitness.get_latest_biometric())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    active_day = params["day"] || List.first(socket.assigns.days, %{})[:slug]
    wiki_open = params["view"] == "wiki"
    filter_group = params["group"]
    filter_category = params["category"]

    day_html =
      if active_day do
        case Vault.get_day(active_day) do
          {:ok, html} -> html
          :error -> "<p>Day not found.</p>"
        end
      else
        "<p>No active day found.</p>"
      end

    grouped_exercises =
      if wiki_open do
        all = Vault.list_all_exercises()

        all =
          if filter_group do
            Enum.filter(all, fn {group, _} -> group == filter_group end)
          else
            all
          end

        all =
          if filter_category do
            Enum.map(all, fn {group, exercises} ->
              filtered =
                Enum.filter(exercises, fn ex -> ex.functional_category == filter_category end)

              {group, filtered}
            end)
            |> Enum.reject(fn {_group, exercises} -> exercises == [] end)
          else
            all
          end

        all
      else
        []
      end

    fitness_posts = Vault.list_blog_posts()

    {:noreply,
     socket
     |> assign(:page_title, "Fitness")
     |> assign(:active_day, active_day)
     |> assign(:day_html, day_html)
     |> assign(:wiki_open, wiki_open)
     |> assign(:filter_group, filter_group)
     |> assign(:filter_category, filter_category)
     |> assign(:grouped_exercises, grouped_exercises)
     |> assign(:fitness_posts, fitness_posts)}
  end

  @impl true
  def handle_event("close_wiki", _, socket) do
    {:noreply, push_patch(socket, to: ~p"/fitness?day=#{socket.assigns.active_day}")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="sensus-portal physical-portal">
      
    <!-- LEFT RAIL: NAVIGATION -->
      <nav class="sensus-rail">
        <div class="sensus-brand">
          <a
            href={~p"/"}
            class="sensus-brand-link"
            style="text-decoration: none; display: flex; align-items: center; gap: 1rem;"
          >
            <div class="blog-brand-icon" style="background: var(--theme-color); color: #fff;">
              <i class="fas fa-running"></i>
            </div>
            <h1 style="color: var(--theme-color); margin: 0;">Fitness</h1>
          </a>
          <div class="sensus-rail-sub">Biological Stewardship & Biometric Intel</div>
        </div>

        <div
          class="sensus-bio"
          style="font-size: 0.8rem; color: #555; line-height: 1.5; border-bottom: 1px solid var(--sensus-border); padding-bottom: 1.5rem; margin-bottom: 1.5rem;"
        >
          Stewardship of the biological architecture. Ensuring structural safety and metabolic efficiency amidst digital acceleration.
        </div>

        <ul class="sensus-nav-list" id="fitness-nav-list">
          <li>
            <a
              href="#weekly-routine"
              class="sensus-nav-link active"
              onclick="document.querySelectorAll('.sensus-nav-link').forEach(l => l.classList.remove('active')); this.classList.add('active');"
            >
              <i class="fas fa-calendar-alt"></i> Weekly Regimen
            </a>
          </li>
          <li>
            <a
              href="#fitness-intelligence"
              class="sensus-nav-link"
              onclick="document.querySelectorAll('.sensus-nav-link').forEach(l => l.classList.remove('active')); this.classList.add('active');"
            >
              <i class="fas fa-brain"></i> Fitness Intelligence
            </a>
          </li>
          <li>
            <.link patch={~p"/fitness?view=wiki"} class="sensus-nav-link">
              <i class="fas fa-book"></i> Exercise Wiki
            </.link>
          </li>
          <%= if @is_admin do %>
            <li>
              <.link navigate={~p"/fitness/biometrics"} class="sensus-nav-link">
                <i class="fas fa-chart-line"></i> Biometrics Dashboard
              </.link>
            </li>
          <% end %>
        </ul>

        <div style="flex-grow: 1;"></div>
        <div style="font-size: 0.7rem; color: #333; font-family: var(--sensus-font-mono);">
          v5.0.0-VAULT<br /> © 2026 STREETSCISSORS
        </div>
      </nav>
      
    <!-- CENTER: MAIN CONTENT -->
      <main class="sensus-main">
        
    <!-- WEEKLY REGIMEN -->
        <div
          id="weekly-routine"
          class="glass-panel"
          style="padding: 2rem; margin-bottom: 4rem; border: none; background: transparent;"
          phx-hook="GymRoutine"
        >
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 1rem;">
            <h2 style="font-size: 2.2rem; font-family: var(--font-heading); color: var(--theme-color); text-transform: uppercase; letter-spacing: 2px;">
              Weekly Regimen
            </h2>
            <button class="reset-btn" id="reset-week" type="button">Reset Week</button>
          </div>
          
    <!-- Day Tabs -->
          <div
            class="day-nav"
            id="day-nav"
            style="display: flex; gap: 0.5rem; margin-bottom: 3rem; flex-wrap: wrap; align-items: center;"
          >
            <% primary_slugs = ~w[monday tuesday wednesday thursday friday saturday sunday] %>
            <% primary_days = Enum.filter(@days, &(&1.slug in primary_slugs)) %>
            <% extra_modules = Enum.reject(@days, &(&1.slug in primary_slugs)) %>

            <%= for day <- primary_days do %>
              <.link
                patch={~p"/fitness?day=#{day.slug}"}
                class={"day-btn #{if @active_day == day.slug, do: "active"}"}
                type="button"
              >
                {day.tab}
              </.link>
            <% end %>

            <div
              class="module-dropdown"
              style="position: relative; margin-left: 0.5rem;"
              id="module-dropdown-container"
            >
              <button
                class={"day-btn #{if @active_day not in primary_slugs, do: "active"}"}
                type="button"
                style="display: flex; align-items: center; gap: 0.5rem;"
                onclick="document.getElementById('dropdown-options-menu').classList.toggle('show-menu')"
              >
                Modules <i class="fas fa-chevron-down" style="font-size: 0.7rem;"></i>
              </button>
              <div class="dropdown-options" id="dropdown-options-menu">
                <div class="dropdown-bridge"></div>
                <%= for day <- extra_modules do %>
                  <.link
                    patch={~p"/fitness?day=#{day.slug}"}
                    class={"dropdown-item #{if @active_day == day.slug, do: "active"}"}
                    onclick="document.getElementById('dropdown-options-menu').classList.remove('show-menu')"
                  >
                    {day.tab}
                  </.link>
                <% end %>
              </div>
            </div>
          </div>
          
    <!-- Day Content from Vault -->
          <div
            class="day-content vault-day markdown-body"
            data-day={@active_day}
            style="position: relative; margin-top: 1rem;"
          >
            <div
              id="active-day-header"
              style="margin-bottom: 1rem; border-bottom: 1px solid rgba(255,255,255,0.1); padding-bottom: 0.75rem;"
            >
              <%= if day = Enum.find(@days, & &1.slug == @active_day) do %>
                <h3 style="font-weight: bold; font-size: 1.4rem; color: #fff;">{day.title}</h3>
                <p style="color: #aaa; margin-top: 0.5rem; font-style: italic;">{day.description}</p>
              <% end %>
              <button
                class="reset-btn day-reset"
                type="button"
                data-reset={@active_day}
                style="margin-top: 0.75rem;"
              >
                Reset Day
              </button>
            </div>
            {raw(@day_html)}
          </div>
        </div>
        
    <!-- FITNESS INTELLIGENCE (BLOG) -->
        <div
          id="fitness-intelligence"
          class="fitness-blog-section"
          style="margin-top: 6rem; margin-bottom: 4rem;"
        >
          <div style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 1rem; margin-bottom: 2.5rem;">
            <h2 style="font-size: 2.2rem; font-family: var(--font-heading); text-transform: uppercase; color: #fff; letter-spacing: 2px;">
              Fitness Intelligence
            </h2>
          </div>

          <%= if @fitness_posts == [] do %>
            <p style="color: #666; font-style: italic;">No investigative reports available.</p>
          <% else %>
            <div
              class="sensus-content-list"
              style="display: flex; flex-direction: column; gap: 2.5rem;"
            >
              <%= for post <- @fitness_posts do %>
                <article
                  class="sensus-post-card"
                  style="background: rgba(255,255,255,0.02); border: 1px solid rgba(255,255,255,0.05); padding: 2.5rem; border-radius: 12px;"
                >
                  <h3
                    class="sensus-post-title"
                    style="font-size: 2rem; font-family: var(--font-heading); margin-bottom: 0.75rem;"
                  >
                    <.link
                      navigate={~p"/fitness-blog/#{post.slug}"}
                      style="color: #fff; text-decoration: none;"
                    >
                      {post.title}
                    </.link>
                  </h3>
                  <div
                    class="sensus-post-meta"
                    style="display: flex; gap: 2rem; color: #555; font-size: 0.85rem; margin-bottom: 1.5rem; text-transform: uppercase; letter-spacing: 1px;"
                  >
                    <%= if post.date do %>
                      <span>
                        <i class="far fa-calendar-alt" style="color: var(--theme-color);"></i> {post.date}
                      </span>
                    <% end %>
                  </div>
                  <p
                    class="sensus-post-excerpt"
                    style="color: #888; line-height: 1.8; margin-bottom: 2rem; font-size: 1.05rem;"
                  >
                    {post.excerpt}...
                  </p>
                  <footer class="sensus-post-actions">
                    <.link
                      navigate={~p"/fitness-blog/#{post.slug}"}
                      class="sensus-more-link"
                      style="color: var(--theme-color); text-decoration: none; font-weight: bold; font-size: 0.95rem; text-transform: uppercase; border: 1px solid rgba(255,102,0,0.3); padding: 0.6rem 1.2rem; border-radius: 4px;"
                    >
                      Open Report →
                    </.link>
                  </footer>
                </article>
              <% end %>
            </div>
          <% end %>
        </div>
      </main>
      
    <!-- RIGHT SIDEBAR -->
      <aside class="sensus-aside">
        <%= if @is_admin and @latest_biometric do %>
          <div
            class="sensus-aside-block"
            style="border: 1px solid rgba(74, 222, 128, 0.2); background: rgba(74, 222, 128, 0.05);"
          >
            <h3 style="color: #4ade80;"><i class="fas fa-microscope"></i> Live Biometrics</h3>
            <div style="display: flex; flex-direction: column; gap: 1rem; margin-top: 1rem;">
              <div style="display: flex; justify-content: space-between; font-size: 0.9rem;">
                <span style="color: #888;">Weight</span>
                <span style="color: #fff; font-weight: bold;">
                  {@latest_biometric.weight_lbs} lbs
                </span>
              </div>
              <.link
                navigate={~p"/fitness/biometrics"}
                class="theme-btn"
                style="width: 100%; margin-top: 0.5rem; font-size: 0.75rem; background: rgba(74, 222, 128, 0.1); border-color: rgba(74, 222, 128, 0.3);"
              >
                Admin Dashboard
              </.link>
            </div>
          </div>
        <% end %>

        <div class="sensus-aside-block">
          <h3>Tools & Resources</h3>
          <div style="display: flex; flex-direction: column; gap: 0.75rem;">
            <.link
              patch={~p"/fitness?view=wiki"}
              style="font-size: 0.85rem; color: #888; text-decoration: none; display: flex; align-items: center; gap: 0.5rem;"
            >
              <i class="fas fa-atlas" style="color: var(--theme-color);"></i> Full Exercise Wiki
            </.link>
            <%= if @is_admin do %>
              <a
                href={~p"/fitness/export/csv"}
                style="font-size: 0.85rem; color: #888; text-decoration: none; display: flex; align-items: center; gap: 0.5rem;"
              >
                <i class="fas fa-file-export" style="color: #888;"></i> Export Training Log (CSV)
              </a>
            <% end %>
          </div>
        </div>

        <div class="sensus-aside-block">
          <h3>Methodology</h3>
          <p style="font-size: 0.8rem; color: #555; line-height: 1.6;">
            A three-modal protocol balancing mechanical preservation, absolute strength, and transverse explosive mechanics. Stewardship over biological decay.
          </p>
        </div>
      </aside>
    </div>

    <!-- WIKI OVERLAY -->
    <%= if @wiki_open do %>
      <div id="wiki-overlay" class="exercise-overlay-container">
        <div class="exercise-overlay-backdrop" phx-click="close_wiki"></div>
        <div
          class="exercise-overlay-content glass-panel"
          style="max-height: 90vh; overflow-y: auto; width: 100%; max-width: 1000px;"
        >
          <header style="display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid rgba(255,102,0,0.2); padding-bottom: 1.5rem; margin-bottom: 2rem;">
            <div>
              <h2 style="font-family: var(--font-heading); font-size: 2.2rem; margin: 0; color: var(--theme-color); text-transform: uppercase; letter-spacing: 2px;">
                Exercise Wiki Index
              </h2>
              <%= if @filter_group || @filter_category do %>
                <div style="display: flex; align-items: center; gap: 0.75rem; margin-top: 0.75rem;">
                  <span style="color: #888; font-size: 0.8rem;">Filtered by:</span>
                  <%= if @filter_group do %>
                    <span style="background: rgba(255,102,0,0.1); border: 1px solid rgba(255,102,0,0.3); color: var(--theme-color); padding: 0.2rem 0.6rem; border-radius: 12px; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.5px;">
                      {@filter_group
                      |> String.replace("-", " ")
                      |> String.split(" ")
                      |> Enum.map(&String.capitalize/1)
                      |> Enum.join(" ")}
                    </span>
                  <% end %>
                  <%= if @filter_category do %>
                    <span style="background: rgba(74,222,128,0.08); border: 1px solid rgba(74,222,128,0.25); color: #4ade80; padding: 0.2rem 0.6rem; border-radius: 12px; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.5px;">
                      {@filter_category}
                    </span>
                  <% end %>
                  <.link
                    patch={~p"/fitness?view=wiki"}
                    style="color: #ff6b6b; font-size: 0.75rem; text-decoration: none; border: 1px solid rgba(255,107,107,0.3); padding: 0.2rem 0.6rem; border-radius: 12px;"
                  >
                    ✕ Clear filter
                  </.link>
                </div>
              <% end %>
            </div>
            <button
              phx-click="close_wiki"
              class="reset-btn"
              style="padding: 0.5rem; border-radius: 50%; width: 32px; height: 32px; display: flex; align-items: center; justify-content: center;"
            >
              <i class="fas fa-times"></i>
            </button>
          </header>

          <div
            class="wiki-grid"
            style="display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 2.5rem;"
          >
            <% active_slugs = Web.Fitness.Vault.active_slugs() %>
            <%= for {group, exercises} <- @grouped_exercises do %>
              <div class="wiki-group-card">
                <h3 style="color: var(--theme-color); font-size: 0.9rem; text-transform: uppercase; letter-spacing: 1px; border-left: 3px solid var(--theme-color); padding-left: 0.75rem; margin-bottom: 1.25rem;">
                  <.link
                    patch={~p"/fitness?view=wiki&group=#{group}"}
                    style="color: var(--theme-color); text-decoration: none;"
                  >
                    {group
                    |> String.replace("-", " ")
                    |> String.split(" ")
                    |> Enum.map(&String.capitalize/1)
                    |> Enum.join(" ")}
                  </.link>
                </h3>
                <ul style="list-style: none; padding: 0; display: flex; flex-direction: column; gap: 0.5rem;">
                  <%= for ex <- exercises do %>
                    <% is_active = Enum.member?(active_slugs, ex.slug) %>
                    <li>
                      <.link
                        navigate={~p"/fitness/#{ex.slug}"}
                        class={"wiki-index-item hover-exercise #{if is_active, do: "active", else: "inactive"}"}
                      >
                        <span>{ex.name}</span>
                        <%= if ex.functional_category do %>
                          <span style="float: right; color: #4ade80; font-size: 0.65rem; text-transform: uppercase; letter-spacing: 0.5px; opacity: 0.6;">
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
      </div>
    <% end %>

    <!-- HOVER POPOUT -->
    <div
      id="exercise-hover-popout"
      style="display: none; position: absolute; z-index: 50000; background: rgba(20,20,20,0.95); backdrop-filter: blur(8px); border: 1px solid rgba(255,102,0,0.3); border-radius: 8px; padding: 1rem; width: 340px; box-shadow: 0 10px 40px rgba(0,0,0,0.8); pointer-events: none; transform: translate(-50%, 10px); transition: opacity 0.15s ease-out;"
    >
      <div
        id="hover-thumbnail-container"
        style="width: 100%; aspect-ratio: 16/9; background: #000; border-radius: 4px; overflow: hidden; margin-bottom: 0.75rem; border: 1px solid rgba(255,255,255,0.1);"
      >
      </div>
      <h4
        id="hover-title"
        style="color: #fff; margin: 0 0 0.25rem 0; font-family: var(--font-heading); font-size: 1.25rem; letter-spacing: 0.5px;"
      >
      </h4>
      <div
        id="hover-muscle"
        style="color: var(--theme-color); text-transform: uppercase; font-size: 0.7rem; letter-spacing: 1px; margin-bottom: 0.5rem; font-weight: bold;"
      >
      </div>
      <p id="hover-desc" style="color: #bbb; font-size: 0.9rem; line-height: 1.4; margin: 0;"></p>
    </div>

    <style>
      .day-btn { background: rgba(255,255,255,0.05); border: 1px solid #444; color: #888; padding: 0.5rem 1rem; cursor: pointer; border-radius: 4px; transition: 0.3s; text-decoration: none; display: inline-block; }
      .day-btn.active, .day-btn:hover { color: white; border-color: var(--theme-color); background: rgba(255,102,0,0.1); }
      .module-dropdown:hover .dropdown-options, .dropdown-options.show-menu { display: flex; }
      .dropdown-bridge { position: absolute; top: -15px; left: 0; width: 100%; height: 15px; background: transparent; }
      .dropdown-options {
        display: none; position: absolute; top: 100%; left: 0; flex-direction: column;
        background: #111; border: 1px solid rgba(255,255,255,0.1); border-radius: 6px;
        min-width: 180px; z-index: 100; margin-top: 0.5rem; padding: 0.5rem 0;
        box-shadow: 0 10px 40px rgba(0,0,0,0.9);
      }
      .dropdown-item { padding: 0.5rem 1rem; color: #888; text-decoration: none; transition: 0.2s; font-size: 0.9rem; }
      .dropdown-item:hover, .dropdown-item.active { color: #fff; background: rgba(255,102,0,0.1); }
      .reset-btn { background: transparent; border: 1px solid #555; color: #888; padding: 0.3rem 0.6rem; cursor: pointer; border-radius: 4px; font-size: 0.8rem; }
      .reset-btn:hover { border-color: #ff6b6b; color: #ff6b6b; }

      /* Vault markdown day rendering */
      .vault-day h2 { color: var(--theme-color); font-size: 1.05rem; text-transform: uppercase; letter-spacing: 1px; margin-top: 2rem; margin-bottom: 0.5rem; padding: 0.6rem 1rem; background: rgba(255,102,0,0.08); border-left: 3px solid var(--theme-color); border-radius: 4px; }
      .vault-day ul { list-style: none; padding: 0 1rem; margin: 0.5rem 0 1.5rem 0; }
      .vault-day li { padding: 0.35rem 0; display: flex; align-items: flex-start; gap: 0.8rem; color: #e5e5e5; font-size: 0.95rem; line-height: 1.5; }
      .vault-day li p { margin: 0; padding: 0; color: inherit; display: inline; }
      .vault-day li input[type="checkbox"] { width: 18px; height: 18px; accent-color: var(--theme-color); cursor: pointer; flex-shrink: 0; margin-top: 0.15rem; background: transparent; border: 1px solid #555; }
      .vault-day blockquote { border-left: 3px solid #60a5fa; margin: 1rem 1rem 1.5rem 1rem; color: #93c5fd; font-size: 0.9rem; background: rgba(96, 165, 250, 0.08); padding: 0.75rem 1rem; border-radius: 0 4px 4px 0; }
      .vault-day blockquote p { margin: 0; padding: 0; color: inherit; }
      .vault-day em { color: #9ca3af; font-style: italic; }
      .vault-day p { color: #9ca3af; margin: 0.5rem 1rem 0.5rem 1rem; padding: 0; font-size: 0.95rem; line-height: 1.5; }

      .wiki-index-item { display: block; padding: 0.6rem 0.8rem; border-radius: 6px; transition: all 0.2s; font-size: 0.95rem; text-decoration: none; }
      .wiki-index-item.active { background: rgba(255,255,255,0.02); border: 1px solid rgba(255,255,255,0.05); color: #aaa; }
      .wiki-index-item.inactive { background: rgba(20, 184, 166, 0.05); border: 1px solid rgba(20, 184, 166, 0.2); color: #5eead4; }
      .wiki-index-item.active:hover { background: rgba(255,102,0, 0.1); border-color: rgba(255,102,0,0.4); color: #fff; }
      .wiki-index-item.inactive:hover { background: rgba(20, 184, 166, 0.15); border-color: rgba(20, 184, 166, 0.5); color: #fff; }

      .exercise-overlay-container { position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; display: flex; align-items: center; justify-content: center; z-index: 20000; padding: 2rem; }
      .exercise-overlay-backdrop { position: absolute; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); backdrop-filter: blur(5px); }
      .exercise-overlay-content { position: relative; width: 100%; max-width: 800px; z-index: 1001; padding: 2rem; animation: zoomIn 0.2s ease-out; }
      @keyframes zoomIn { from { opacity: 0; transform: scale(0.95); } to { opacity: 1; transform: scale(1); } }
    </style>
    """
  end
end
