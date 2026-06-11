defmodule WebWeb.FitnessLive.Regimen do
  use WebWeb, :live_view

  alias Web.Fitness.Vault

  @impl true
  def mount(_params, session, socket) do
    is_admin = session["admin_user"] == true
    days = Vault.list_days()

    # Load HTML for all days
    days_with_html =
      Enum.map(days, fn day ->
        html =
          case Vault.get_day(day.slug) do
            {:ok, content} -> content
            _ -> ""
          end

        Map.put(day, :html, html)
      end)

    {:ok,
     socket
     |> assign(:is_admin, is_admin)
     |> assign(:days, days_with_html)
     |> assign(:page_title, "Weekly Regimen")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
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
      <WebWeb.FitnessSubnav.subnav active={:regimen} is_admin={@is_admin} />

      <div class="blog-bento-card bento-span-full" id="weekly-routine" phx-hook="GymRoutine">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 1rem;">
          <h2 style="font-size: 2.2rem; font-family: var(--font-heading); color: var(--theme-color); text-transform: uppercase; letter-spacing: 2px;">
            Weekly Regimen
          </h2>
          <button class="reset-btn" id="reset-week" type="button">Reset All Checkboxes</button>
        </div>

        <% primary_slugs = ~w[monday tuesday wednesday thursday friday saturday sunday] %>
        <% primary_days = Enum.filter(@days, &(&1.slug in primary_slugs)) %>
        <% extra_modules = Enum.reject(@days, &(&1.slug in primary_slugs)) %>

        <div class="regimen-list">
          <%= for day <- primary_days do %>
            <details class="day-details" data-day={day.slug}>
              <summary class="day-summary">
                <span class="day-title">{day.title}</span>
                <%= if day.description != "" do %>
                  <span class="day-desc">{day.description}</span>
                <% end %>
                <.icon name="hero-chevron-down" class="summary-icon" />
              </summary>
              <div class="day-content vault-day markdown-body" style="padding: 1rem 0;">
                {raw(day.html)}
              </div>
            </details>
          <% end %>
        </div>

        <%= if length(extra_modules) > 0 do %>
          <div style="margin-top: 3rem; margin-bottom: 1rem; border-bottom: 1px solid rgba(255,255,255,0.05); padding-bottom: 1rem;">
            <h2 style="font-size: 1.8rem; font-family: var(--font-heading); color: #fff; text-transform: uppercase; letter-spacing: 1px;">
              Additional Modules
            </h2>
          </div>
          <div class="regimen-list">
            <%= for day <- extra_modules do %>
              <details class="day-details" data-day={day.slug}>
                <summary class="day-summary">
                  <span class="day-title">{day.title}</span>
                  <%= if day.description != "" do %>
                    <span class="day-desc">{day.description}</span>
                  <% end %>
                  <.icon name="hero-chevron-down" class="summary-icon" />
                </summary>
                <div class="day-content vault-day markdown-body" style="padding: 1rem 0;">
                  {raw(day.html)}
                </div>
              </details>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>

    <style>
      .regimen-list { display: flex; flex-direction: column; gap: 1rem; }
      .day-details {
        background: rgba(255,255,255,0.03);
        border: 1px solid rgba(255,255,255,0.1);
        border-radius: 8px;
        overflow: hidden;
      }
      .day-summary {
        padding: 1.25rem 1.5rem;
        cursor: pointer;
        list-style: none; /* Hide default arrow */
        display: flex;
        align-items: center;
        gap: 1rem;
        background: rgba(255,255,255,0.02);
        transition: background 0.2s;
      }
      .day-summary::-webkit-details-marker { display: none; }
      .day-summary:hover { background: rgba(255,102,0,0.1); }
      .day-details[open] .day-summary { border-bottom: 1px solid rgba(255,255,255,0.1); background: rgba(255,255,255,0.05); }

      .day-title { font-size: 1.3rem; font-weight: bold; color: var(--theme-color); font-family: var(--font-heading); text-transform: uppercase; letter-spacing: 1px; min-width: 150px;}
      .day-desc { color: #aaa; font-style: italic; font-size: 0.95rem; flex: 1; }
      .summary-icon { color: #666; transition: transform 0.3s; font-size: 1.1rem; width: 1.1rem; height: 1.1rem; }
      .day-details[open] .summary-icon { transform: rotate(180deg); color: #fff; }

      .reset-btn { background: transparent; border: 1px solid #555; color: #888; padding: 0.4rem 0.8rem; cursor: pointer; border-radius: 4px; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 1px; transition: 0.2s;}
      .reset-btn:hover { border-color: #ff6b6b; color: #ff6b6b; background: rgba(255,107,107,0.1); }

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
