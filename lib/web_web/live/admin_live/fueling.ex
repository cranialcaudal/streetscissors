defmodule WebWeb.AdminLive.Fueling do
  @moduledoc """
  The daily fueling plan (`/admin/fitness/fueling`): each day's targets, its
  meals and snacks, the supplements and a staples reference.

  The plan itself is the author's and lives in the vault
  (`Web.Fitness.Fueling`, `content/fitness/fueling.json`); this page only lays
  it out. Without the file the page says where to write one.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Fitness.Fueling

  @impl true
  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok, assign(socket, page_title: "Fueling | Admin", plan: Fueling.load())}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  @impl true
  def handle_params(params, _uri, %{assigns: %{plan: {:ok, plan}}} = socket) do
    order = plan["day_order"]
    today = Web.Clock.today_slug()

    slug =
      cond do
        params["day"] in order -> params["day"]
        today in order -> today
        true -> hd(order)
      end

    {:noreply, assign(socket, selected_slug: slug, day: plan["days"][slug])}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def render(%{plan: :none} = assigns) do
    ~H"""
    <.page_head slug="Training / Fueling" title="Daily fueling">
      <:actions>
        <.link navigate={~p"/admin/fitness"} class="adm-btn">Fitness vault</.link>
      </:actions>
    </.page_head>

    <div id="fueling-none">
      <.empty>
        No fueling plan yet. Write one to <code>content/fitness/fueling.json</code>
        (its shape is in <code>Web.Fitness.Fueling</code>).
      </.empty>
    </div>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, :p, elem(assigns.plan, 1))

    ~H"""
    <.page_head slug="Training / Fueling" title="Daily fueling">
      <:lede>
        {@p["lede"]} Full recipes and shopping lists live at <.link
          href={~p"/food"}
          target="_blank"
          class="adm-link"
        >/food</.link>.
      </:lede>
      <:actions>
        <.link navigate={~p"/admin/fitness"} class="adm-btn">Fitness vault</.link>
        <.link navigate={~p"/admin/fitness/block"} class="adm-btn">Block report</.link>
      </:actions>
    </.page_head>

    <.tabs label="Day of the week">
      <:tab
        :for={slug <- @p["day_order"]}
        patch={~p"/admin/fitness/fueling?day=#{slug}"}
        active={@selected_slug == slug}
        count={@p["days"][slug]["kcal"]}
      >
        {@p["days"][slug]["short"]}
      </:tab>
    </.tabs>

    <.panel
      id="fueling-day-summary"
      title={"#{@day["name"]} — #{@day["sessions"]}"}
      count={"#{@day["kcal"]} kcal target"}
    >
      <div class="adm-stats">
        <.stat value={"#{@day["kcal"]} kcal"} label="Daily calories" tone="act" />
        <.stat value={@day["protein"]} label="Protein floor" />
        <.stat value={@day["carbs"]} label="Carbohydrate target" />
        <.stat value={@day["fiber"]} label="Fiber goal" />
        <.stat value={@day["fat"]} label="Fat target" />
        <.stat value={@day["water"]} label="Water target" />
        <.stat value={@day["sodium"]} label="Sodium target" note={@day["ph_tabs"]} />
      </div>
    </.panel>

    <.panel
      id="fueling-slots"
      title="Meals and snacks"
      count={"#{length(@day["slots"] || [])} feedings"}
    >
      <div class="adm-table-wrap">
        <table class="adm-table">
          <thead>
            <tr>
              <th>Slot</th>
              <th>What</th>
              <th class="adm-cell-num">kcal</th>
              <th class="adm-cell-num">Protein</th>
              <th class="adm-cell-num">Carbs</th>
              <th class="adm-cell-num">Fat</th>
              <th class="adm-cell-num">Fiber</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={slot <- @day["slots"] || []}>
              <td class="adm-cell-title">
                <div>{slot["slot"]}</div>
                <div class="adm-help">{slot["window"]}</div>
              </td>
              <td>{slot["food"]}</td>
              <td class="adm-cell-num">{slot["kcal"]}</td>
              <td class="adm-cell-num">{slot["protein"]}</td>
              <td class="adm-cell-num">{slot["carbs"]}</td>
              <td class="adm-cell-num">{slot["fat"]}</td>
              <td class="adm-cell-num">{slot["fiber"]}</td>
            </tr>
            <tr :if={totals = @day["totals"]}>
              <td class="adm-cell-title">Menu total</td>
              <td class="adm-help">{@p["totals_note"]}</td>
              <td class="adm-cell-num"><strong>{totals["kcal"]}</strong></td>
              <td class="adm-cell-num"><strong>{totals["protein"]}</strong></td>
              <td class="adm-cell-num"><strong>{totals["carbs"]}</strong></td>
              <td class="adm-cell-num"><strong>{totals["fat"]}</strong></td>
              <td class="adm-cell-num"><strong>{totals["fiber"]}</strong></td>
            </tr>
          </tbody>
        </table>
      </div>
    </.panel>

    <.supplements
      id="fueling-supplements-morning"
      title={@p["morning_title"] || "Morning supplements"}
      items={@p["morning_supplements"]}
    />
    <.supplements
      id="fueling-supplements-evening"
      title={@p["evening_title"] || "Evening supplements"}
      items={@p["evening_supplements"]}
    />

    <.panel
      id="fueling-staples"
      title="Staples quick-reference"
      count={length(@p["staples"])}
    >
      <div class="adm-table-wrap">
        <table class="adm-table">
          <thead>
            <tr>
              <th>Item</th>
              <th>Serving</th>
              <th class="adm-cell-num">kcal</th>
              <th class="adm-cell-num">Protein</th>
              <th class="adm-cell-num">Carbs</th>
              <th class="adm-cell-num">Fat</th>
              <th class="adm-cell-num">Fiber</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={s <- @p["staples"]}>
              <td class="adm-cell-title">{s["item"]}</td>
              <td>{s["serving"]}</td>
              <td class="adm-cell-num">{s["kcal"]}</td>
              <td class="adm-cell-num">{s["protein"]}</td>
              <td class="adm-cell-num">{s["carbs"]}</td>
              <td class="adm-cell-num">{s["fat"]}</td>
              <td class="adm-cell-num">{s["fiber"]}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </.panel>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :items, :list, required: true

  defp supplements(assigns) do
    ~H"""
    <.panel id={@id} title={@title} count={length(@items)}>
      <.rows id={"#{@id}-rows"} rows={@items}>
        <:col :let={item} label="Supplement" class="adm-cell-title">
          <a
            :if={item["url"]}
            href={item["url"]}
            target="_blank"
            rel="noopener noreferrer"
            class="adm-link"
          >
            {item["name"]}
          </a>
          <span :if={!item["url"]}>{item["name"]}</span>
        </:col>
        <:col :let={item} label="Dose">{item["dose"]}</:col>
        <:col :let={item} label="At-home protocol">{item["how"]}</:col>
      </.rows>
    </.panel>
    """
  end
end
