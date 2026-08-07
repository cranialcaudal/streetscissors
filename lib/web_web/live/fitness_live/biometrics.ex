defmodule WebWeb.FitnessLive.Biometrics do
  use WebWeb, :live_view
  alias Web.Fitness
  alias Web.Fitness.Biometric

  @line_metrics [
    {"Score", "score"},
    {"HRV (ms)", "hrv_ms"},
    {"Sleep (h)", "sleep_hours"},
    {"Weight (lbs)", "weight_lbs"},
    {"Resting HR", "resting_hr"},
    {"Active Cal", "active_calories"},
    {"Protein (g)", "protein_grams"},
    {"Energy", "energy"},
    {"Soreness", "soreness"}
  ]

  def mount(_params, session, socket) do
    is_admin = session["admin_user"] == true

    if !is_admin do
      {:ok,
       socket
       |> put_flash(:error, "Administrators only.")
       |> redirect(to: ~p"/fitness")}
    else
      biometrics = load_with_scores()
      changeset = Fitness.change_biometric(%Biometric{date: Date.utc_today()})

      socket =
        socket
        |> assign(
          page_title: "Biometrics",
          is_admin: true,
          biometrics: biometrics,
          form: to_form(changeset),
          chart_type: :line,
          line_metric: "score",
          line_metrics: @line_metrics,
          webhook_token: load_webhook_token(),
          show_token: false
        )
        |> push_chart_data(biometrics)

      {:ok, socket}
    end
  end

  def handle_event("validate", %{"biometric" => params}, socket) do
    cs = %Biometric{} |> Fitness.change_biometric(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, form: to_form(cs))}
  end

  def handle_event("save", %{"biometric" => params}, socket) do
    case Fitness.create_biometric(params) do
      {:ok, _} ->
        biometrics = load_with_scores()

        {:noreply,
         socket
         |> put_flash(:info, "Entry recorded.")
         |> assign(
           biometrics: biometrics,
           form: to_form(Fitness.change_biometric(%Biometric{date: Date.utc_today()}))
         )
         |> push_chart_data(biometrics)}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, form: to_form(cs))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, _} = id |> Fitness.get_biometric!() |> Fitness.delete_biometric()
    biometrics = load_with_scores()

    {:noreply,
     socket
     |> put_flash(:info, "Entry deleted.")
     |> assign(biometrics: biometrics)
     |> push_chart_data(biometrics)}
  end

  def handle_event("set_chart", %{"type" => type, "metric" => metric}, socket) do
    chart_type = String.to_existing_atom(type)

    {:noreply,
     socket
     |> assign(chart_type: chart_type, line_metric: metric)
     |> push_event("biometrics:chart", %{type: type, metric: metric})}
  end

  def handle_event("set_chart", %{"type" => type}, socket) do
    chart_type = String.to_existing_atom(type)

    {:noreply,
     socket
     |> assign(chart_type: chart_type)
     |> push_event("biometrics:chart", %{type: type, metric: socket.assigns.line_metric})}
  end

  def handle_event("generate_token", _params, socket) do
    token = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    {:ok, _} = Web.SiteSettings.put_setting("health_webhook_token", token)
    {:noreply, assign(socket, webhook_token: token, show_token: true)}
  end

  def handle_event("save_token", %{"token" => token}, socket) do
    token = String.trim(token)

    if token == "" do
      Web.SiteSettings.delete_setting("health_webhook_token")
      {:noreply, assign(socket, webhook_token: nil, show_token: false)}
    else
      {:ok, _} = Web.SiteSettings.put_setting("health_webhook_token", token)

      {:noreply,
       assign(socket, webhook_token: token, show_token: false)
       |> put_flash(:info, "Webhook token saved.")}
    end
  end

  def handle_event("toggle_token", _params, socket) do
    {:noreply, assign(socket, show_token: !socket.assigns.show_token)}
  end

  defp load_webhook_token do
    case Web.SiteSettings.get_setting("health_webhook_token") do
      t when is_binary(t) and t != "" -> t
      _ -> nil
    end
  end

  defp push_chart_data(socket, biometrics) do
    entries =
      biometrics
      |> Enum.reverse()
      |> Enum.map(fn b ->
        %{
          date: Date.to_iso8601(b.date),
          score: b.score,
          sleep_hours: to_f(b.sleep_hours),
          hrv_ms: b.hrv_ms,
          weight_lbs: to_f(b.weight_lbs),
          resting_hr: b.resting_hr,
          active_calories: b.active_calories,
          protein_grams: b.protein_grams,
          water_oz: b.water_oz,
          soreness: b.soreness,
          energy: b.energy,
          spo2_percent: to_f(b.spo2_percent),
          vo2_max: to_f(b.vo2_max),
          respiratory_rate: to_f(b.respiratory_rate)
        }
      end)

    push_event(socket, "biometrics:data", %{
      entries: entries,
      goals: Biometric.goals()
    })
  end

  defp load_with_scores do
    Fitness.list_biometrics()
    |> Enum.map(fn b -> Map.put(b, :score, Biometric.compute_score(b)) end)
  end

  defp to_f(nil), do: nil
  defp to_f(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_f(n), do: n * 1.0

  defp score_color(nil), do: "var(--ink-4)"
  defp score_color(s) when s >= 80, do: "#4ade80"
  defp score_color(s) when s >= 60, do: "#facc15"
  defp score_color(_), do: "#f87171"

  defp chart_tab_class(current, target),
    do: if(current == target, do: "bio-tab bio-tab--active", else: "bio-tab")

  def render(assigns) do
    ~H"""
    <div class="bio-page steel">
      <header class="bio-header">
        <h1 class="bio-title">Biometrics</h1>
        <.link href={~p"/fitness/biometrics/export"} class="bio-export-btn">
          <.icon name="hero-table-cells" class="size-4" /> CSV
        </.link>
      </header>

      <%!-- Score summary for latest entry --%>
      <div :if={hd_or_nil(@biometrics)} class="bio-score-banner">
        <% latest = hd(@biometrics) %>
        <div class="bio-score-ring" style={"--score-color: #{score_color(latest.score)}"}>
          <span class="bio-score-num">{latest.score || "—"}</span>
          <span class="bio-score-label">today's score</span>
        </div>
        <div class="bio-score-chips">
          <span :if={latest.hrv_ms} class="bio-chip">HRV {latest.hrv_ms} ms</span>
          <span :if={latest.sleep_hours} class="bio-chip">Sleep {latest.sleep_hours} h</span>
          <span :if={latest.resting_hr} class="bio-chip">RHR {latest.resting_hr} bpm</span>
          <span :if={latest.active_calories} class="bio-chip">🔥 {latest.active_calories} kcal</span>
          <span :if={latest.energy} class="bio-chip">Energy {latest.energy}/10</span>
          <span :if={latest.soreness} class="bio-chip">Soreness {latest.soreness}/10</span>
        </div>
      </div>

      <%!-- Chart section --%>
      <section :if={@biometrics != []} class="bio-chart-section">
        <div class="bio-tabs">
          <button
            class={chart_tab_class(@chart_type, :line)}
            phx-click="set_chart"
            phx-value-type="line"
            phx-value-metric={@line_metric}
          >
            Line
          </button>
          <button
            class={chart_tab_class(@chart_type, :violin)}
            phx-click="set_chart"
            phx-value-type="violin"
          >
            Violin
          </button>
          <button
            class={chart_tab_class(@chart_type, :waterfall)}
            phx-click="set_chart"
            phx-value-type="waterfall"
          >
            Waterfall
          </button>

          <div :if={@chart_type == :line} class="bio-metric-select">
            <select phx-change="set_chart" name="metric">
              <option
                :for={{label, key} <- @line_metrics}
                value={key}
                selected={@line_metric == key}
              >
                {label}
              </option>
            </select>
          </div>
        </div>

        <canvas
          id="bio-chart"
          class="bio-canvas"
          phx-hook="BiometricCharts"
          phx-update="ignore"
          data-chart-type={@chart_type}
          data-line-metric={@line_metric}
        >
        </canvas>
      </section>

      <%!-- Entry form --%>
      <section class="bio-form-section">
        <h2 class="bio-section-heading">New entry</h2>
        <.form for={@form} phx-change="validate" phx-submit="save" class="bio-form">
          <div class="bio-form-group-label">date & body</div>
          <div class="bio-form-grid">
            <div class="bio-field">
              <label>Date</label>
              <.input field={@form[:date]} type="date" class="bio-input" />
            </div>
            <div class="bio-field">
              <label>Weight (lbs)</label>
              <.input
                field={@form[:weight_lbs]}
                type="number"
                step="0.1"
                placeholder="165.0"
                class="bio-input"
              />
            </div>
            <div class="bio-field">
              <label>Body Fat %</label>
              <.input
                field={@form[:body_fat_percentage]}
                type="number"
                step="0.1"
                placeholder="12.5"
                class="bio-input"
              />
            </div>
          </div>

          <div class="bio-form-group-label">recovery (Apple Watch)</div>
          <div class="bio-form-grid">
            <div class="bio-field">
              <label>HRV (ms)</label>
              <.input field={@form[:hrv_ms]} type="number" placeholder="55" class="bio-input" />
            </div>
            <div class="bio-field">
              <label>RHR (bpm)</label>
              <.input field={@form[:resting_hr]} type="number" placeholder="52" class="bio-input" />
            </div>
            <div class="bio-field">
              <label>Sleep (h)</label>
              <.input
                field={@form[:sleep_hours]}
                type="number"
                step="0.1"
                placeholder="7.5"
                class="bio-input"
              />
            </div>
            <div class="bio-field">
              <label>SpO₂ %</label>
              <.input
                field={@form[:spo2_percent]}
                type="number"
                step="0.1"
                placeholder="98.5"
                class="bio-input"
              />
            </div>
            <div class="bio-field">
              <label>Resp. rate</label>
              <.input
                field={@form[:respiratory_rate]}
                type="number"
                step="0.1"
                placeholder="14.2"
                class="bio-input"
              />
            </div>
            <div class="bio-field">
              <label>VO₂ max</label>
              <.input
                field={@form[:vo2_max]}
                type="number"
                step="0.1"
                placeholder="52.5"
                class="bio-input"
              />
            </div>
            <div class="bio-field">
              <label>Active cal</label>
              <.input
                field={@form[:active_calories]}
                type="number"
                placeholder="620"
                class="bio-input"
              />
            </div>
          </div>

          <div class="bio-form-group-label">nutrition</div>
          <div class="bio-form-grid">
            <div class="bio-field">
              <label>Protein (g)</label>
              <.input field={@form[:protein_grams]} type="number" placeholder="160" class="bio-input" />
            </div>
            <div class="bio-field">
              <label>Water (oz)</label>
              <.input field={@form[:water_oz]} type="number" placeholder="100" class="bio-input" />
            </div>
          </div>

          <div class="bio-form-group-label">subjective</div>
          <div class="bio-form-grid">
            <div class="bio-field">
              <label>Energy (1–10)</label>
              <.input
                field={@form[:energy]}
                type="number"
                min="1"
                max="10"
                placeholder="7"
                class="bio-input"
              />
            </div>
            <div class="bio-field">
              <label>Soreness (1–10)</label>
              <.input
                field={@form[:soreness]}
                type="number"
                min="1"
                max="10"
                placeholder="3"
                class="bio-input"
              />
            </div>
            <div class="bio-field">
              <label>Screentime (h)</label>
              <.input
                field={@form[:screentime_hours]}
                type="number"
                step="0.1"
                placeholder="4.0"
                class="bio-input"
              />
            </div>
          </div>

          <button type="submit" class="bio-save-btn">Save entry</button>
        </.form>
      </section>

      <%!-- History table --%>
      <section class="bio-history">
        <h2 class="bio-section-heading">History</h2>
        <div class="bio-table-wrap">
          <table class="bio-table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Score</th>
                <th>HRV</th>
                <th>Sleep</th>
                <th>RHR</th>
                <th>Weight</th>
                <th>Energy</th>
                <th>Soreness</th>
                <th>Active cal</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={b <- @biometrics}>
                <td>{b.date}</td>
                <td>
                  <span class="bio-score-badge" style={"color: #{score_color(b.score)}"}>
                    {b.score || "—"}
                  </span>
                </td>
                <td>{b.hrv_ms || "—"}</td>
                <td>{b.sleep_hours || "—"}</td>
                <td>{b.resting_hr || "—"}</td>
                <td>{b.weight_lbs || "—"}</td>
                <td>{b.energy || "—"}</td>
                <td>{b.soreness || "—"}</td>
                <td>{b.active_calories || "—"}</td>
                <td>
                  <button
                    phx-click="delete"
                    phx-value-id={b.id}
                    data-confirm="Delete this entry?"
                    class="bio-delete-btn"
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <%!-- Health Auto Export webhook --%>
      <section class="bio-webhook-section">
        <h2 class="bio-section-heading">Health Auto Export webhook</h2>
        <p class="bio-webhook-endpoint">
          <code>POST https://streetscissors.com/api/health/ingest</code>
        </p>
        <p class="bio-webhook-hint">
          Set this URL in Health Auto Export → Automations → add REST API export.
          Set the Authorization header to <code>Bearer &lt;token&gt;</code>.
        </p>

        <div :if={@webhook_token} class="bio-webhook-token-row">
          <code class="bio-token-display">
            {if @show_token, do: @webhook_token, else: String.duplicate("•", 24)}
          </code>
          <button class="bio-webhook-btn" phx-click="toggle_token">
            {if @show_token, do: "hide", else: "show"}
          </button>
        </div>
        <p :if={!@webhook_token} class="bio-webhook-hint">No token set — generate one below.</p>

        <div class="bio-webhook-actions">
          <button class="bio-webhook-btn bio-webhook-btn--primary" phx-click="generate_token">
            {if @webhook_token, do: "Regenerate token", else: "Generate token"}
          </button>

          <form phx-submit="save_token" class="bio-webhook-custom">
            <input
              type="text"
              name="token"
              placeholder="or paste your own token…"
              autocomplete="off"
              class="bio-webhook-input"
            />
            <button type="submit" class="bio-webhook-btn">Save</button>
          </form>
        </div>
      </section>

      <style>
        .bio-page { max-width: 960px; margin: 0 auto; padding: 2rem 1rem 5rem; color: #ddd; }
        .bio-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 2rem; }
        .bio-title { font-family: var(--font-heading); font-weight: 900; font-size: 2.2rem; text-transform: uppercase; letter-spacing: 3px; color: var(--ink); margin: 0; }
        .bio-export-btn { display: flex; align-items: center; gap: 0.4rem; font-size: 0.8rem; font-family: var(--font-mono, monospace); color: var(--ink-3); border: 1px solid #333; border-radius: 6px; padding: 0.4rem 0.8rem; text-decoration: none; }
        .bio-export-btn:hover { color: var(--ink-3); border-color: var(--ink-4); }

        /* score banner */
        .bio-score-banner { display: flex; align-items: center; gap: 2rem; background: rgba(23, 20, 15, 0.03); border: 1px solid #222; border-radius: 12px; padding: 1.5rem; margin-bottom: 2rem; flex-wrap: wrap; }
        .bio-score-ring { display: flex; flex-direction: column; align-items: center; justify-content: center; width: 90px; height: 90px; border-radius: 50%; border: 4px solid var(--score-color, var(--ink-4)); flex-shrink: 0; }
        .bio-score-num { font-family: var(--font-heading); font-weight: 900; font-size: 1.8rem; color: var(--score-color, var(--ink-3)); line-height: 1; }
        .bio-score-label { font-family: var(--font-mono, monospace); font-size: 0.55rem; letter-spacing: 1px; text-transform: uppercase; color: var(--ink-3); margin-top: 2px; }
        .bio-score-chips { display: flex; flex-wrap: wrap; gap: 0.5rem; }
        .bio-chip { background: rgba(23, 20, 15, 0.05); border: 1px solid #2a2a2a; border-radius: 20px; padding: 0.25rem 0.7rem; font-family: var(--font-mono, monospace); font-size: 0.75rem; color: var(--ink-3); }

        /* chart */
        .bio-chart-section { margin-bottom: 2.5rem; }
        .bio-tabs { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 1rem; flex-wrap: wrap; }
        .bio-tab { background: none; border: 1px solid #333; color: var(--ink-3); font-family: var(--font-mono, monospace); font-size: 0.78rem; letter-spacing: 1px; padding: 0.35rem 0.9rem; border-radius: 6px; cursor: pointer; transition: all 0.15s; }
        .bio-tab:hover { color: var(--ink-3); border-color: var(--ink-4); }
        .bio-tab--active { background: rgba(23, 20, 15, 0.06); border-color: var(--ink-4); color: var(--ink-2); }
        .bio-metric-select select { background: var(--paper-sunk); border: 1px solid #333; color: var(--ink-3); border-radius: 6px; padding: 0.35rem 0.7rem; font-family: var(--font-mono, monospace); font-size: 0.78rem; cursor: pointer; }
        .bio-canvas { display: block; width: 100%; height: 300px; border-radius: 10px; border: 1px solid rgba(23, 20, 15, 0.08); background: rgba(23, 20, 15, 0.02); cursor: crosshair; }

        /* form */
        .bio-form-section { background: rgba(23, 20, 15, 0.02); border: 1px solid #1e1e1e; border-radius: 12px; padding: 1.5rem; margin-bottom: 2.5rem; }
        .bio-section-heading { font-family: var(--font-mono, monospace); font-size: 0.7rem; text-transform: uppercase; letter-spacing: 2px; color: var(--ink-4); margin: 0 0 1.25rem; }
        .bio-form-group-label { font-family: var(--font-mono, monospace); font-size: 0.65rem; text-transform: uppercase; letter-spacing: 2px; color: #444; margin: 1.25rem 0 0.6rem; }
        .bio-form-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(130px, 1fr)); gap: 0.75rem; }
        .bio-field label { display: block; font-size: 0.72rem; color: var(--ink-3); margin-bottom: 0.25rem; font-family: var(--font-mono, monospace); }
        .bio-input { background: rgba(0,0,0,0.4) !important; border: 1px solid #2a2a2a !important; color: var(--ink-2) !important; padding: 0.45rem 0.6rem !important; width: 100% !important; border-radius: 6px !important; font-size: 0.85rem !important; }
        .bio-save-btn { margin-top: 1.5rem; width: 100%; background: rgba(23, 20, 15, 0.07); border: 1px solid #333; color: var(--ink-2); padding: 0.7rem; border-radius: 8px; font-family: var(--font-mono, monospace); font-size: 0.85rem; letter-spacing: 1px; cursor: pointer; transition: background 0.15s; }
        .bio-save-btn:hover { background: rgba(23, 20, 15, 0.12); }

        /* table */
        .bio-history { }
        .bio-history .bio-section-heading { margin-bottom: 0.75rem; }
        .bio-table-wrap { overflow-x: auto; }
        .bio-table { width: 100%; border-collapse: collapse; font-size: 0.82rem; }
        .bio-table th { text-align: left; color: var(--ink-4); padding: 0.5rem 0.75rem; border-bottom: 1px solid #1e1e1e; font-family: var(--font-mono, monospace); font-size: 0.7rem; letter-spacing: 1px; text-transform: uppercase; font-weight: 600; }
        .bio-table td { padding: 0.5rem 0.75rem; border-bottom: 1px solid var(--rule); }
        .bio-score-badge { font-family: var(--font-heading); font-weight: 800; font-size: 0.95rem; }
        .bio-delete-btn { background: none; border: none; color: #444; cursor: pointer; }
        .bio-delete-btn:hover { color: #f87171; }

        /* webhook */
        .bio-webhook-section { background: rgba(23, 20, 15, 0.02); border: 1px solid #1e1e1e; border-radius: 12px; padding: 1.5rem; margin-top: 2.5rem; }
        .bio-webhook-endpoint code { font-family: var(--font-mono, monospace); font-size: 0.8rem; color: #a78bfa; }
        .bio-webhook-hint { color: var(--ink-4); font-size: 0.78rem; font-family: var(--font-mono, monospace); margin: 0.5rem 0; }
        .bio-webhook-hint code { color: var(--ink-3); }
        .bio-webhook-token-row { display: flex; align-items: center; gap: 0.75rem; margin: 1rem 0 0.5rem; }
        .bio-token-display { font-family: var(--font-mono, monospace); font-size: 0.78rem; color: var(--ink-3); background: #0a0a0a; border: 1px solid #222; border-radius: 6px; padding: 0.4rem 0.75rem; word-break: break-all; }
        .bio-webhook-actions { display: flex; flex-direction: column; gap: 0.75rem; margin-top: 1rem; }
        .bio-webhook-custom { display: flex; gap: 0.5rem; }
        .bio-webhook-input { flex: 1; background: #0a0a0a; border: 1px solid #2a2a2a; color: var(--ink-2); border-radius: 6px; padding: 0.4rem 0.7rem; font-family: var(--font-mono, monospace); font-size: 0.78rem; }
        .bio-webhook-btn { background: none; border: 1px solid #333; color: #777; font-family: var(--font-mono, monospace); font-size: 0.75rem; padding: 0.4rem 0.9rem; border-radius: 6px; cursor: pointer; transition: all 0.15s; white-space: nowrap; }
        .bio-webhook-btn:hover { color: #ccc; border-color: var(--ink-4); }
        .bio-webhook-btn--primary { border-color: #4a4a7a; color: #a78bfa; }
        .bio-webhook-btn--primary:hover { background: rgba(167,139,250,0.08); }

        @media (max-width: 640px) {
          .bio-score-banner { gap: 1rem; }
          .bio-score-ring { width: 72px; height: 72px; }
          .bio-score-num { font-size: 1.4rem; }
        }
      </style>
    </div>
    """
  end

  defp hd_or_nil([]), do: nil
  defp hd_or_nil([h | _]), do: h
end
