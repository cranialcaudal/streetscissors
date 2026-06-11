defmodule WebWeb.FitnessLive.Biometrics do
  use WebWeb, :live_view
  alias Web.Fitness
  alias Web.Fitness.Biometric

  def mount(_params, session, socket) do
    is_admin = session["admin_user"] == true

    if !is_admin do
      {:ok,
       socket
       |> put_flash(:error, "You must be an administrator to access this page.")
       |> redirect(to: ~p"/fitness")}
    else
      biometrics = Fitness.list_biometrics()

      # Initialize the changeset for a new entry (defaulting to today)
      changeset = Fitness.change_biometric(%Biometric{date: Date.utc_today()})

      {:ok,
       socket
       |> assign(:page_title, "Biometrics")
       |> assign(:return_to, "/fitness")
       |> assign(:return_label, "return to gym")
       |> assign(:is_admin, is_admin)
       |> assign(:biometrics, biometrics)
       |> assign(:form, to_form(changeset))
       |> assign(:editing_id, nil)}
    end
  end

  def handle_event("validate", %{"biometric" => params}, socket) do
    changeset =
      %Biometric{}
      |> Fitness.change_biometric(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"biometric" => params}, socket) do
    if !socket.assigns.is_admin do
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    else
      case Fitness.create_biometric(params) do
        {:ok, _biometric} ->
          # Refresh list
          {:noreply,
           socket
           |> put_flash(:info, "Biometric entry recorded")
           |> assign(:biometrics, Fitness.list_biometrics())
           |> assign(:form, to_form(Fitness.change_biometric(%Biometric{date: Date.utc_today()})))}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, form: to_form(changeset))}
      end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    if !socket.assigns.is_admin do
      {:noreply, put_flash(socket, :error, "Unauthorized")}
    else
      biometric = Fitness.get_biometric!(id)
      {:ok, _} = Fitness.delete_biometric(biometric)

      {:noreply,
       socket
       |> put_flash(:info, "Entry deleted")
       |> assign(:biometrics, Fitness.list_biometrics())}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="container" style="max-width: 900px; margin: 0 auto; padding: 2rem;">
      <header style="margin-bottom: 2rem; display: flex; justify-content: space-between; align-items: center;">
        <div>
          <h1 class="theme-title" style="margin-top: 0.5rem;">Daily Biometrics Log</h1>
          <p style="color: #888; font-style: italic; font-size: 0.9rem;">
            Track your daily weight, sleep, and recovery stats.
          </p>
        </div>
        <%= if @is_admin do %>
          <.link href={~p"/fitness/biometrics/export"} class="theme-btn" style="font-size: 0.9rem;">
            <.icon name="hero-table-cells" class="size-4" /> Export CSV
          </.link>
        <% end %>
      </header>

      <%= if @is_admin do %>
        <section class="glass-panel" style="padding: 2rem; margin-bottom: 3rem;">
          <h2 style="margin-bottom: 1.5rem; color: var(--theme-color);">New Daily Entry</h2>
          <.form for={@form} phx-change="validate" phx-submit="save" class="biometric-form">
            <div
              class="form-grid"
              style="display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 1.5rem; margin-bottom: 1.5rem;"
            >
              <div class="form-group">
                <label>Date</label>
                <.input
                  field={@form[:date]}
                  type="date"
                  style="background: rgba(0,0,0,0.3); border: 1px solid #444; color: #fff; padding: 0.5rem; width: 100%;"
                />
              </div>

              <div class="form-group">
                <label>Weight (lbs)</label>
                <.input
                  field={@form[:weight_lbs]}
                  type="number"
                  step="0.1"
                  placeholder="145.0"
                  style="background: rgba(0,0,0,0.3); border: 1px solid #444; color: #fff; padding: 0.5rem; width: 100%;"
                />
              </div>

              <div class="form-group">
                <label>Body Fat %</label>
                <.input
                  field={@form[:body_fat_percentage]}
                  type="number"
                  step="0.1"
                  placeholder="12.5"
                  style="background: rgba(0,0,0,0.3); border: 1px solid #444; color: #fff; padding: 0.5rem; width: 100%;"
                />
              </div>

              <div class="form-group">
                <label>Sleep (hrs)</label>
                <.input
                  field={@form[:sleep_hours]}
                  type="number"
                  step="0.1"
                  placeholder="7.5"
                  style="background: rgba(0,0,0,0.3); border: 1px solid #444; color: #fff; padding: 0.5rem; width: 100%;"
                />
              </div>

              <div class="form-group">
                <label>Protein (g)</label>
                <.input
                  field={@form[:protein_grams]}
                  type="number"
                  placeholder="160"
                  style="background: rgba(0,0,0,0.3); border: 1px solid #444; color: #fff; padding: 0.5rem; width: 100%;"
                />
              </div>

              <div class="form-group">
                <label>Water (oz)</label>
                <.input
                  field={@form[:water_oz]}
                  type="number"
                  placeholder="100"
                  style="background: rgba(0,0,0,0.3); border: 1px solid #444; color: #fff; padding: 0.5rem; width: 100%;"
                />
              </div>

              <div class="form-group">
                <label>Screen (hrs)</label>
                <.input
                  field={@form[:screentime_hours]}
                  type="number"
                  step="0.1"
                  placeholder="4.0"
                  style="background: rgba(0,0,0,0.3); border: 1px solid #444; color: #fff; padding: 0.5rem; width: 100%;"
                />
              </div>

              <div class="form-group">
                <label>RHR (bpm)</label>
                <.input
                  field={@form[:resting_hr]}
                  type="number"
                  placeholder="55"
                  style="background: rgba(0,0,0,0.3); border: 1px solid #444; color: #fff; padding: 0.5rem; width: 100%;"
                />
              </div>
            </div>

            <button type="submit" class="theme-btn" style="width: 100%;">Save Entry</button>
          </.form>
        </section>
      <% else %>
        <div style="background: rgba(255,255,255,0.05); padding: 1rem; margin-bottom: 2rem; border-radius: 4px; text-align: center; color: #aaa;">
          <em>Only administrators can edit biometric data.</em>
        </div>
      <% end %>

      <section>
        <h3 style="margin-bottom: 1rem; color: #aaa;">History</h3>
        <div style="overflow-x: auto;">
          <table style="width: 100%; border-collapse: collapse; color: #ddd; font-size: 0.9rem;">
            <thead>
              <tr style="border-bottom: 1px solid rgba(255,255,255,0.2); text-align: left;">
                <th style="padding: 0.75rem;">Date</th>
                <th style="padding: 0.75rem;">Weight</th>
                <th style="padding: 0.75rem;">BMI</th>
                <th style="padding: 0.75rem;">Body Fat %</th>
                <!-- Placeholder or calc -->
                <th style="padding: 0.75rem;">Sleep</th>
                <th style="padding: 0.75rem;">Protein</th>
                <th style="padding: 0.75rem;">Screen</th>
                <%= if @is_admin do %>
                  <th style="padding: 0.75rem;">Actions</th>
                <% end %>
              </tr>
            </thead>
            <tbody>
              <%= for entry <- @biometrics do %>
                <tr style="border-bottom: 1px solid rgba(255,255,255,0.05);">
                  <td style="padding: 0.75rem;">{entry.date}</td>
                  <td style="padding: 0.75rem;">
                    {if entry.weight_lbs, do: "#{entry.weight_lbs} lbs", else: "-"}
                  </td>
                  <td style="padding: 0.75rem;">
                    <%= if entry.weight_lbs do %>
                      <% # Calculate BMI: (Weight / Height^2) * 703. Height = 69 inches.
                      weight = Decimal.to_float(entry.weight_lbs)
                      bmi = weight * 703 / (69 * 69) %>
                      <span class={if bmi > 25, do: "text-yellow-500", else: "text-green-400"}>
                        {Float.round(bmi, 1)}
                      </span>
                    <% else %>
                      -
                    <% end %>
                  </td>
                  <td style="padding: 0.75rem;">
                    {if entry.body_fat_percentage, do: "#{entry.body_fat_percentage}%", else: "-"}
                  </td>
                  <td style="padding: 0.75rem;">{entry.sleep_hours || "-"} h</td>
                  <td style="padding: 0.75rem;">{entry.protein_grams || "-"} g</td>
                  <td style="padding: 0.75rem;">{entry.screentime_hours || "-"} h</td>
                  <%= if @is_admin do %>
                    <td style="padding: 0.75rem;">
                      <button
                        phx-click="delete"
                        phx-value-id={entry.id}
                        data-confirm="Are you sure?"
                        style="color: #ff3366; background: none; border: none; cursor: pointer;"
                      >
                        <.icon name="hero-trash" class="size-4" />
                      </button>
                    </td>
                  <% end %>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </section>
    </div>
    """
  end
end
