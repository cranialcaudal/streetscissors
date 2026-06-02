defmodule WebWeb.FitnessLive.Regimen do
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
     |> assign(:day_html, nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    active_day = params["day"] || List.first(socket.assigns.days, %{})[:slug]

    day_html =
      if active_day do
        case Vault.get_day(active_day) do
          {:ok, html} -> html
          :error -> "<p>Day not found.</p>"
        end
      else
        "<p>No active day found.</p>"
      end

    {:noreply,
     socket
     |> assign(:page_title, "Weekly Regimen")
     |> assign(:active_day, active_day)
     |> assign(:day_html, day_html)}
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
        <div class="bento-fitness-sub-row" style="display: flex; gap: 1rem; margin-bottom: 2rem;">
          <a
            href="/fitness"
            class="bento-card bento-card-skinny"
            style="flex: 1; text-align: center; padding: 1rem; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1); border-radius: 12px; text-decoration: none;"
          >
            <span
              class="bento-label-small"
              style="color: #fff; font-family: var(--font-heading); text-transform: uppercase; letter-spacing: 1px;"
            >
              📰 Blog
            </span>
          </a>
          <a
            href="/fitness/wiki"
            class="bento-card bento-card-skinny"
            style="flex: 1; text-align: center; padding: 1rem; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1); border-radius: 12px; text-decoration: none;"
          >
            <span
              class="bento-label-small"
              style="color: #fff; font-family: var(--font-heading); text-transform: uppercase; letter-spacing: 1px;"
            >
              📖 Wiki
            </span>
          </a>
          <%= if @is_admin do %>
            <a
              href="/fitness/biometrics"
              class="bento-card bento-card-skinny"
              style="flex: 1; text-align: center; padding: 1rem; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1); border-radius: 12px; text-decoration: none;"
            >
              <span
                class="bento-label-small"
                style="color: #fff; font-family: var(--font-heading); text-transform: uppercase; letter-spacing: 1px;"
              >
                📊 Biometrics
              </span>
            </a>
          <% end %>
        </div>

        <div class="blog-bento-card bento-span-full" id="weekly-routine" phx-hook="GymRoutine">
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
                patch={~p"/fitness/regimen?day=#{day.slug}"}
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
                    patch={~p"/fitness/regimen?day=#{day.slug}"}
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
      </style>

    """
  end
end
