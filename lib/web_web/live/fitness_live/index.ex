defmodule WebWeb.FitnessLive.Index do
  use WebWeb, :live_view

  alias Web.Fitness
  alias Web.Fitness.Vault

  @impl true
  def mount(_params, session, socket) do
    is_admin = session["admin_user"] == true
    days = Vault.list_days()

    # Load HTML for all days, plus any rotating options. Days that do the same
    # thing every week come back with `options: []`, so the template handles
    # both shapes the same way.
    days_with_html =
      Enum.map(days, fn day ->
        case Vault.get_day_with_options(day.slug) do
          {:ok, %{html: html, options: options}} ->
            day |> Map.put(:html, html) |> Map.put(:options, options)

          _ ->
            day |> Map.put(:html, "") |> Map.put(:options, [])
        end
      end)

    {:ok,
     socket
     |> assign(:is_admin, is_admin)
     |> assign(:days, days_with_html)
     |> assign(:today_slug, Web.Clock.today_slug())
     |> assign(:logging_slug, nil)
     |> assign(:logging_name, nil)
     |> assign(:page_title, "Fitness & Sport")}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # Fired by the inline "Log" button that Web.Fitness.Vault stitches onto any
  # checkbox line referencing a `[[slug]]` exercise (see
  # Vault.render_markdown/1's ⟦LOG:slug⟧ marker). Only exercises with a
  # matching row in the `exercises` DB table are actually loggable — most of
  # the regimen's older wiki-links predate that table and won't resolve,
  # which is expected, not an error, so it just flashes instead of opening
  # the form.
  @impl true
  def handle_event("open_log", _params, %{assigns: %{is_admin: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("open_log", %{"slug" => slug}, socket) do
    case Fitness.get_exercise_by_slug(slug) do
      %Fitness.Exercise{} = exercise ->
        {:noreply,
         socket
         |> assign(:logging_slug, slug)
         |> assign(:logging_name, exercise.name)}

      nil ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This exercise isn't wired up for logging yet."
         )}
    end
  end

  @impl true
  def handle_event("close_log", _params, socket) do
    {:noreply,
     socket
     |> assign(:logging_slug, nil)
     |> assign(:logging_name, nil)}
  end

  @impl true
  def handle_event("save_log", _params, %{assigns: %{is_admin: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("save_log", %{"log" => params}, socket) do
    slug = socket.assigns.logging_slug

    with %Fitness.Exercise{} = exercise <- Fitness.get_exercise_by_slug(slug),
         metrics when map_size(metrics) > 0 <- log_metrics(params) do
      attrs = %{
        exercise_id: exercise.id,
        date: Date.utc_today(),
        metrics: metrics,
        note: blank_to_nil(params["note"])
      }

      case Fitness.create_exercise_log(attrs) do
        {:ok, _log} ->
          {:noreply,
           socket
           |> put_flash(:info, "Logged #{exercise.name}.")
           |> assign(:logging_slug, nil)
           |> assign(:logging_name, nil)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Couldn't save that — try again.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Enter at least one value to log.")}
    end
  end

  # Builds the `metrics` map the CSV export already understands
  # (fitness_controller.ex reads string values like "200 lbs"/"2 miles" out
  # of these same keys) — only the fields the user actually filled in.
  defp log_metrics(params) do
    %{}
    |> put_metric("weight", params["weight"])
    |> put_metric("distance", params["distance"])
    |> put_metric("time", params["time"])
    |> put_metric("result", params["result"])
  end

  defp put_metric(map, _key, nil), do: map
  defp put_metric(map, _key, ""), do: map
  defp put_metric(map, key, value), do: Map.put(map, key, String.trim(value))

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  @impl true
  def render(assigns) do
    ~H"""
    <div class="blog-bento-wrapper steel">
      <!-- Header -->
      <header class="blog-header-card">
        <h1 class="blog-header-title">Fitness & Sport</h1>
        <div class="blog-header-subtitle">Training, regimen & GPX action</div>
      </header>
      
    <!-- Section Navigation -->
      <WebWeb.FitnessSubnav.subnav active={:regimen} is_admin={@is_admin} />

      <div
        class={"blog-bento-card" <> if(@is_admin, do: " is-admin", else: "")}
        id="weekly-routine"
        phx-hook="GymRoutine"
      >
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem; border-bottom: 1px solid rgba(23, 20, 15, 0.05); padding-bottom: 1rem;">
          <h2 style="font-size: 2.2rem; font-family: var(--font-heading); color: var(--ink); text-transform: uppercase; letter-spacing: 2px;">
            Weekly Regimen
          </h2>
          <button class="reset-btn" id="reset-week" type="button">Reset All Checkboxes</button>
        </div>

        <% primary_slugs = ~w[monday tuesday wednesday thursday friday saturday sunday] %>
        <% primary_days = Enum.filter(@days, &(&1.slug in primary_slugs)) %>
        <% extra_modules = Enum.reject(@days, &(&1.slug in primary_slugs)) %>

        <div class="regimen-list">
          <%= for day <- primary_days do %>
            <details class="day-details" data-day={day.slug} open={day.slug == @today_slug}>
              <summary class="day-summary">
                <span class="day-title">{day.title}</span>
                <.icon name="hero-chevron-down" class="summary-icon" />
              </summary>
              <div class="day-content vault-day markdown-body" style="padding: 1rem 0;">
                {raw(day.html)}

                <%!-- Rotating days (Friday's swim-or-run, Saturday's four-week
                      cycle) render each option as its own dropdown, with the one
                      in rotation open. Which one is live comes from
                      Web.Fitness.Rotation off the ISO week — it used to be prose
                      that checklist_only/1 stripped, so the page showed a single
                      option and gave no sign the others existed. --%>
                <div :if={day.options != []} class="option-list">
                  <details
                    :for={option <- day.options}
                    class="option-details"
                    data-option={"#{day.slug}_#{option.key}"}
                    open={option.active?}
                  >
                    <summary class="option-summary">
                      <span class="option-label">{option.label}</span>
                      <span :if={option.active?} class="option-badge">this week</span>
                      <.icon name="hero-chevron-down" class="summary-icon" />
                    </summary>
                    <div class="option-content vault-day markdown-body">
                      {raw(option.html)}
                    </div>
                  </details>
                </div>
              </div>
            </details>
          <% end %>
        </div>

        <%= if length(extra_modules) > 0 do %>
          <div style="margin-top: 3rem; margin-bottom: 1rem; border-bottom: 1px solid rgba(23, 20, 15, 0.05); padding-bottom: 1rem;">
            <h2 style="font-size: 1.8rem; font-family: var(--font-heading); color: var(--ink); text-transform: uppercase; letter-spacing: 1px;">
              Additional Modules
            </h2>
          </div>
          <div class="regimen-list">
            <%= for day <- extra_modules do %>
              <details class="day-details" data-day={day.slug}>
                <summary class="day-summary">
                  <span class="day-title">{day.title}</span>
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

      <%= if @logging_slug do %>
        <div class="log-modal-backdrop" phx-click="close_log">
          <div class="log-modal" phx-click-away="close_log">
            <h3>Log: {@logging_name}</h3>
            <form phx-submit="save_log">
              <label>
                Weight <input type="text" name="log[weight]" placeholder="e.g. 200 lbs" autofocus />
              </label>
              <label>
                Distance <input type="text" name="log[distance]" placeholder="e.g. 2 miles" />
              </label>
              <label>
                Time <input type="text" name="log[time]" placeholder="e.g. 8:26 pace" />
              </label>
              <label>
                Result <input type="text" name="log[result]" placeholder="e.g. 30 inches, 20 reps" />
              </label>
              <label>
                Note <input type="text" name="log[note]" placeholder="optional" />
              </label>
              <div class="log-modal-actions">
                <button type="button" class="reset-btn" phx-click="close_log">Cancel</button>
                <button type="submit" class="log-save-btn">Save</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>

    <style>
      .regimen-list { display: flex; flex-direction: column; gap: 1rem; }
      .day-details {
        background: rgba(23, 20, 15, 0.03);
        border: 1px solid rgba(23, 20, 15, 0.1);
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
        background: rgba(23, 20, 15, 0.02);
        transition: background 0.2s;
      }
      .day-summary::-webkit-details-marker { display: none; }
      .day-summary:hover { background: rgba(194, 69, 29, 0.1); }
      .day-details[open] .day-summary { border-bottom: 1px solid rgba(23, 20, 15, 0.1); background: rgba(23, 20, 15, 0.05); }

      .day-title { font-size: 1.3rem; font-weight: bold; color: var(--theme-color); font-family: var(--font-heading); text-transform: uppercase; letter-spacing: 1px; min-width: 150px;}
      .day-desc { color: var(--ink-3); font-style: italic; font-size: 0.95rem; flex: 1; }
      .summary-icon { color: var(--ink-3); transition: transform 0.3s; font-size: 1.1rem; width: 1.1rem; height: 1.1rem; }
      .day-details[open] .summary-icon { transform: rotate(180deg); color: var(--ink); }

      .reset-btn { background: transparent; border: 1px solid var(--rule); color: var(--ink-3); padding: 0.4rem 0.8rem; cursor: pointer; border-radius: 4px; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 1px; transition: 0.2s;}
      .reset-btn:hover { border-color: var(--accent-color); color: var(--accent-color); background: rgba(194, 69, 29, 0.1); }

      /* Vault markdown day rendering */
      .vault-day h2 { color: var(--theme-color); font-size: 1.05rem; text-transform: uppercase; letter-spacing: 1px; margin-top: 2rem; margin-bottom: 0.5rem; padding: 0.6rem 1rem; background: rgba(194, 69, 29, 0.08); border-left: 3px solid var(--theme-color); border-radius: 4px; }
      .vault-day ul { list-style: none; padding: 0 1rem; margin: 0.5rem 0 1.5rem 0; }
      .vault-day li { padding: 0.35rem 0; display: flex; align-items: flex-start; gap: 0.8rem; color: var(--ink-2); font-size: 0.95rem; line-height: 1.5; }
      .vault-day li p { margin: 0; padding: 0; color: inherit; display: inline; }
      .vault-day li input[type="checkbox"] { width: 18px; height: 18px; accent-color: var(--theme-color); cursor: pointer; flex-shrink: 0; margin-top: 0.15rem; background: transparent; border: 1px solid var(--rule); }
      .vault-day blockquote { border-left: 3px solid #60a5fa; margin: 1rem 1rem 1.5rem 1rem; color: #93c5fd; font-size: 0.9rem; background: rgba(96, 165, 250, 0.08); padding: 0.75rem 1rem; border-radius: 0 4px 4px 0; }
      .vault-day blockquote p { margin: 0; padding: 0; color: inherit; }
      .vault-day em { color: #9ca3af; font-style: italic; }
      .vault-day p { color: #9ca3af; margin: 0.5rem 1rem 0.5rem 1rem; padding: 0; font-size: 0.95rem; line-height: 1.5; }

      /* Inline "Log" trigger stitched onto loggable checklist lines — logging
         is an admin-only write, same as every other mutation on this site,
         so the trigger only renders for the admin session. */
      .log-trigger { display: none; }
      .is-admin .log-trigger { display: inline-block; background: transparent; border: 1px solid rgba(23, 20, 15, 0.15); color: var(--ink-3); padding: 0.1rem 0.5rem; margin-left: 0.5rem; border-radius: 4px; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.5px; cursor: pointer; flex-shrink: 0; }
      .is-admin .log-trigger:hover { border-color: var(--theme-color); color: var(--theme-color); background: rgba(194, 69, 29, 0.1); }

      /* Log-entry modal */
      .log-modal-backdrop { position: fixed; inset: 0; background: rgba(0,0,0,0.6); display: flex; align-items: center; justify-content: center; z-index: 100; }
      .log-modal { background: var(--paper-sunk); border: 1px solid rgba(23, 20, 15, 0.15); border-radius: 8px; padding: 1.5rem; width: 90%; max-width: 360px; }
      .log-modal h3 { color: var(--theme-color); font-family: var(--font-heading); text-transform: uppercase; letter-spacing: 1px; font-size: 1.1rem; margin: 0 0 1rem 0; }
      .log-modal label { display: block; color: var(--ink-3); font-size: 0.85rem; margin-bottom: 0.75rem; }
      .log-modal input { display: block; width: 100%; margin-top: 0.25rem; padding: 0.5rem; background: rgba(23, 20, 15, 0.05); border: 1px solid var(--rule); border-radius: 4px; color: var(--ink-2); font-size: 0.9rem; }
      .log-modal-actions { display: flex; justify-content: flex-end; gap: 0.75rem; margin-top: 1rem; }
      .log-save-btn { background: var(--theme-color); border: none; color: var(--paper); padding: 0.4rem 1rem; border-radius: 4px; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 1px; cursor: pointer; font-weight: bold; }
    </style>
    """
  end
end
