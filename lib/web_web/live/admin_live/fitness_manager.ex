defmodule WebWeb.AdminLive.FitnessManager do
  @moduledoc """
  The fitness vault's editor: the exercise wiki and the regimen's days, each
  a markdown file under `content/fitness/` (`Web.Fitness.Vault`), so the vault
  in Obsidian and this page write the same files.

  Which list is showing is in the URL (`?tab=wiki|regimen|progress|checkin`):
  the progress tab is the training block's charts (`WebWeb.FitnessCharts`),
  the check-in tab the day's pain, sleep, soreness and energy, which the
  guardrails read (`Web.Fitness.Guardrails`). Editing opens in
  the page rather than over it — fields on the left, the markdown on the
  right with a preview a click away — and a name filter narrows the wiki.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Fitness
  alias Web.Fitness.{Block, Guardrails, Training, Vault}

  @tabs ~w(wiki regimen progress checkin)

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok,
       assign(socket,
         page_title: "Fitness | Admin",
         tab: "wiki",
         query: "",
         days: Vault.list_days(),
         exercises: Vault.list_all_exercises(),
         muscle_groups: Vault.list_muscle_groups(),
         editor_mode: nil,
         editing_item: nil,
         form_data: %{},
         preview: false
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "wiki"

    {:noreply,
     socket
     |> assign(tab: tab, editor_mode: nil, editing_item: nil)
     |> assign_progress(tab)}
  end

  # The block's figures are read only for the tab that shows them.
  defp assign_progress(socket, "progress") do
    today = Web.Clock.local_today()

    case Block.latest(today) do
      nil ->
        assign(socket, block: nil)

      block ->
        assign(socket,
          block: block,
          entries: Training.all_entries(block),
          weeks: Training.weeks_so_far(block, today),
          started?: Date.compare(today, block.start) != :lt
        )
    end
  end

  defp assign_progress(socket, "checkin"), do: assign_checkins(socket)
  defp assign_progress(socket, _tab), do: socket

  defp assign_checkins(socket) do
    today = Web.Clock.local_today()
    recent = Fitness.recent_checkins(today)
    todays = Enum.find(recent, &(&1.date == today))

    assign(socket,
      checkins: recent,
      checkin_form:
        to_form(Fitness.change_checkin(todays || %Fitness.Checkin{date: today}), as: :checkin),
      guard: Guardrails.line(Guardrails.state(nil, recent, [], today))
    )
  end

  def handle_event("save_checkin", %{"checkin" => params}, socket) do
    params = Map.update(params, "date", nil, &parse_date/1)

    case Fitness.save_checkin(params) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Check-in saved.") |> assign_checkins()}

      {:error, changeset} ->
        {:noreply, assign(socket, checkin_form: to_form(changeset, as: :checkin))}
    end
  end

  # --- The lists ---

  def handle_event("filter", %{"query" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  def handle_event("new_item", %{"type" => "day"}, socket) do
    form = %{"slug" => "", "title" => "", "description" => "", "tab" => "", "content" => ""}
    {:noreply, open_editor(socket, :day, nil, form)}
  end

  def handle_event("new_item", %{"type" => "exercise"}, socket) do
    form = %{
      "slug" => "",
      "title" => "",
      "muscle_group" => "",
      "anatomy" => "",
      "functional_category" => "",
      "short_description" => "",
      "content" => ""
    }

    {:noreply, open_editor(socket, :exercise, nil, form)}
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

        {:noreply, open_editor(socket, :day, %{slug: slug}, form)}

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

        {:noreply, open_editor(socket, :exercise, %{slug: slug}, form)}

      :error ->
        {:noreply, put_flash(socket, :error, "Exercise not found.")}
    end
  end

  def handle_event("delete_exercise", %{"slug" => slug, "group" => group}, socket) do
    Vault.delete_exercise(slug, group)

    {:noreply,
     socket
     |> put_flash(:info, "Exercise deleted.")
     |> assign(exercises: Vault.list_all_exercises())}
  end

  # --- The editor ---

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, editor_mode: nil, editing_item: nil)}
  end

  # Keeps @form_data in step with the fields so the preview shows what is
  # typed, not what was loaded.
  def handle_event("editor_change", params, socket) do
    case params[to_string(socket.assigns.editor_mode)] do
      %{} = fields -> {:noreply, update(socket, :form_data, &Map.merge(&1, fields))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_preview", _params, socket) do
    {:noreply, update(socket, :preview, &(!&1))}
  end

  def handle_event("save_day", %{"day" => params}, socket) do
    slug = String.trim(params["slug"] || "")

    if slug == "" do
      {:noreply, put_flash(socket, :error, "A day needs a slug — it is the file's name.")}
    else
      Vault.update_day(slug, params)

      {:noreply,
       socket
       |> put_flash(:info, "Saved #{slug}.md.")
       |> assign(editor_mode: nil, days: Vault.list_days())}
    end
  end

  def handle_event("save_exercise", %{"exercise" => params}, socket) do
    slug = String.trim(params["slug"] || "")

    if slug == "" do
      {:noreply, put_flash(socket, :error, "An exercise needs a slug — it is the file's name.")}
    else
      Vault.update_exercise(slug, params["original_muscle_group"], params)

      {:noreply,
       socket
       |> put_flash(:info, "Saved #{slug}.md.")
       |> assign(
         editor_mode: nil,
         exercises: Vault.list_all_exercises(),
         muscle_groups: Vault.list_muscle_groups()
       )}
    end
  end

  defp open_editor(socket, mode, item, form) do
    assign(socket, editor_mode: mode, editing_item: item, form_data: form, preview: false)
  end

  defp filtered(exercises, ""), do: exercises

  defp filtered(exercises, query) do
    needle = String.downcase(String.trim(query))

    exercises
    |> Enum.map(fn {group, list} ->
      {group, Enum.filter(list, &String.contains?(String.downcase(&1.name || ""), needle))}
    end)
    |> Enum.reject(fn {_group, list} -> list == [] end)
  end

  defp exercise_count(exercises),
    do: exercises |> Enum.map(fn {_, list} -> length(list) end) |> Enum.sum()

  # --- Rendering ---

  def render(assigns) do
    ~H"""
    <%= if @editor_mode do %>
      {render_editor(assigns)}
    <% else %>
      <.page_head slug="Training / Fitness" title="Fitness">
        <:lede>
          The exercise wiki and the regimen's days, as markdown in the vault. The public side is <.link
            href={~p"/fitness"}
            target="_blank"
            class="adm-link"
          >/fitness</.link>. The week as calendar events is <.link
            href={~p"/admin/fitness/calendar"}
            class="adm-link"
          >here</.link>.
        </:lede>
        <:actions>
          <button
            :if={@tab == "wiki"}
            phx-click="new_item"
            phx-value-type="exercise"
            class="adm-btn adm-btn--primary"
          >
            <.icon name="hero-plus" class="size-4" /> New exercise
          </button>
          <button
            :if={@tab == "regimen"}
            phx-click="new_item"
            phx-value-type="day"
            class="adm-btn adm-btn--primary"
          >
            <.icon name="hero-plus" class="size-4" /> New day
          </button>
        </:actions>
      </.page_head>

      <.tabs label="Vault">
        <:tab
          patch={~p"/admin/fitness?tab=wiki"}
          active={@tab == "wiki"}
          count={exercise_count(@exercises)}
        >
          Exercise wiki
        </:tab>
        <:tab patch={~p"/admin/fitness?tab=regimen"} active={@tab == "regimen"} count={length(@days)}>
          Regimen
        </:tab>
        <:tab patch={~p"/admin/fitness?tab=progress"} active={@tab == "progress"}>
          Progress
        </:tab>
        <:tab patch={~p"/admin/fitness?tab=checkin"} active={@tab == "checkin"}>
          Check-in
        </:tab>
      </.tabs>

      {case @tab do
        "wiki" -> render_exercises(assigns)
        "regimen" -> render_days(assigns)
        "progress" -> render_progress(assigns)
        "checkin" -> render_checkin(assigns)
      end}
    <% end %>
    """
  end

  defp render_checkin(assigns) do
    ~H"""
    <section class="adm-fit-checkin" id="fitness-checkin">
      <p :if={@guard} class="adm-fit-guard" id="checkin-guard">{@guard}</p>
      <.form
        for={@checkin_form}
        id="checkin-form"
        phx-submit="save_checkin"
        class="adm-fit-checkin-form"
      >
        <.field label="Day">
          <input
            type="date"
            name="checkin[date]"
            value={@checkin_form[:date].value}
            class="adm-input"
            required
          />
        </.field>
        <.field label="Pain, Achilles or worst joint (0–10)">
          <input
            type="number"
            min="0"
            max="10"
            name="checkin[pain]"
            value={@checkin_form[:pain].value}
            class="adm-input"
          />
        </.field>
        <.field label="Sleep (hours)">
          <input
            type="number"
            min="0"
            max="24"
            step="0.25"
            name="checkin[sleep_hours]"
            value={@checkin_form[:sleep_hours].value}
            class="adm-input"
          />
        </.field>
        <.field label="Soreness (0–10)">
          <input
            type="number"
            min="0"
            max="10"
            name="checkin[soreness]"
            value={@checkin_form[:soreness].value}
            class="adm-input"
          />
        </.field>
        <.field label="Energy (0–10)">
          <input
            type="number"
            min="0"
            max="10"
            name="checkin[energy]"
            value={@checkin_form[:energy].value}
            class="adm-input"
          />
        </.field>
        <.field label="Note">
          <input
            type="text"
            name="checkin[note]"
            value={@checkin_form[:note].value}
            class="adm-input"
          />
        </.field>
        <p :for={{field, error} <- @checkin_form.errors} class="adm-error">
          {Phoenix.Naming.humanize(field)} {WebWeb.CoreComponents.translate_error(error)}
        </p>
        <div>
          <button type="submit" class="adm-btn adm-btn--primary">Save check-in</button>
        </div>
      </.form>

      <.rows :if={@checkins != []} id="checkins" rows={@checkins}>
        <:col :let={c} label="Day">{Calendar.strftime(c.date, "%a %-d %b")}</:col>
        <:col :let={c} label="Pain">{c.pain}</:col>
        <:col :let={c} label="Sleep">{c.sleep_hours}</:col>
        <:col :let={c} label="Soreness">{c.soreness}</:col>
        <:col :let={c} label="Energy">{c.energy}</:col>
        <:col :let={c} label="Note">{c.note}</:col>
      </.rows>
    </section>
    """
  end

  defp render_progress(%{block: nil} = assigns) do
    ~H"""
    <.empty>
      No training block in the vault. A block is a file in <code>content/fitness/blocks/</code>.
    </.empty>
    """
  end

  defp render_progress(assigns) do
    ~H"""
    <section class="adm-fit-progress" id="fitness-progress">
      <p class="adm-fit-block">
        <strong>{@block.title}</strong>
        <%= if @started? do %>
          · Week {@block.week} of {@block.weeks} — {@block.phase}
        <% else %>
          · begins {Calendar.strftime(@block.start, "%-d %B %Y")}
        <% end %>
      </p>
      <WebWeb.FitnessCharts.block_charts block={@block} entries={@entries} weeks={@weeks} />
    </section>
    """
  end

  defp render_exercises(assigns) do
    assigns = assign(assigns, :shown, filtered(assigns.exercises, assigns.query))

    ~H"""
    <form phx-change="filter" id="exercise-filter" class="adm-inline-form adm-filter" role="search">
      <input
        type="search"
        name="query"
        value={@query}
        class="adm-input"
        placeholder="Filter by name"
        aria-label="Filter exercises by name"
        phx-debounce="150"
        autocomplete="off"
      />
    </form>

    <.empty :if={@shown == []}>
      {if @query == "", do: "The wiki is empty.", else: "No exercise matches “#{@query}”."}
    </.empty>

    <section :for={{group, exercises} <- @shown} class="adm-panel">
      <h2 class="adm-group-title">{group}<span class="adm-count">{length(exercises)}</span></h2>
      <.rows id={"exercises-#{group}"} class="adm-rows--grid" rows={exercises}>
        <:col :let={ex} label="Exercise" class="adm-cell-title adm-w-name">{ex.name}</:col>
        <:col :let={ex} label="Category" class="adm-w-mid">{ex.functional_category || "—"}</:col>
        <:col :let={ex} label="Anatomy">{ex.anatomy || "—"}</:col>
        <:action :let={ex}>
          <button
            phx-click="edit_exercise"
            phx-value-slug={ex.slug}
            class="adm-btn adm-btn--small adm-btn--quiet"
          >
            Edit
          </button>
        </:action>
        <:action :let={ex}>
          <button
            phx-click="delete_exercise"
            phx-value-slug={ex.slug}
            phx-value-group={group}
            data-confirm={"Delete #{ex.name} from the wiki? The file goes too."}
            class="adm-btn adm-btn--small adm-btn--quiet adm-act-danger"
          >
            Delete
          </button>
        </:action>
      </.rows>
    </section>
    """
  end

  defp render_days(assigns) do
    ~H"""
    <.rows id="days" class="adm-rows--grid" rows={@days}>
      <:col :let={day} label="Day" class="adm-cell-title">{day.title}</:col>
      <:col :let={day} label="Tab">{day.tab}</:col>
      <:col :let={day} label="File">{day.slug}.md</:col>
      <:action :let={day}>
        <button
          phx-click="edit_day"
          phx-value-slug={day.slug}
          class="adm-btn adm-btn--small adm-btn--quiet"
        >
          Edit
        </button>
      </:action>
      <:empty>No days in the regimen yet.</:empty>
    </.rows>
    """
  end

  defp render_editor(assigns) do
    ~H"""
    <.page_head
      slug={"Training / Fitness / " <> if(@editor_mode == :exercise, do: "Exercise", else: "Day")}
      title={presence(@form_data["title"]) || new_title(@editor_mode)}
    >
      <:actions>
        <button type="button" phx-click="cancel_edit" class="adm-btn adm-btn--quiet">Cancel</button>
        <button form="editor-form" type="submit" class="adm-btn adm-btn--primary">Save</button>
      </:actions>
    </.page_head>

    <form
      id="editor-form"
      class="adm-editor"
      phx-submit={"save_#{@editor_mode}"}
      phx-change="editor_change"
    >
      <div class="adm-sheet">
        <.field label="Slug (the file's name)">
          <input
            name={"#{@editor_mode}[slug]"}
            value={@form_data["slug"]}
            class="adm-input"
            required
            readonly={@editing_item != nil}
          />
        </.field>
        <.field label="Title">
          <input
            name={"#{@editor_mode}[title]"}
            value={@form_data["title"]}
            class="adm-input"
            required
          />
        </.field>

        <%= if @editor_mode == :exercise do %>
          <.field label="Muscle group (folder)">
            <input
              name="exercise[muscle_group]"
              value={@form_data["muscle_group"]}
              list="muscle-groups"
              class="adm-input"
              placeholder="e.g. chest"
              required
            />
            <datalist id="muscle-groups">
              <option :for={group <- @muscle_groups} value={group}></option>
            </datalist>
            <input
              type="hidden"
              name="exercise[original_muscle_group]"
              value={@form_data["original_muscle_group"]}
            />
          </.field>
          <.field label="Anatomy">
            <input
              name="exercise[anatomy]"
              value={@form_data["anatomy"]}
              class="adm-input"
              placeholder="e.g. Pectoralis Major"
            />
          </.field>
          <.field label="Functional category">
            <input
              name="exercise[functional_category]"
              value={@form_data["functional_category"]}
              class="adm-input"
              placeholder="e.g. Absolute Strength"
            />
          </.field>
          <.field label="Thumbnail URL">
            <input
              name="exercise[thumbnail_url]"
              value={@form_data["thumbnail_url"]}
              class="adm-input"
            />
          </.field>
          <.field label="Video URL">
            <input name="exercise[video_url]" value={@form_data["video_url"]} class="adm-input" />
          </.field>
          <.field label="Short description">
            <textarea name="exercise[short_description]" class="adm-input adm-input--prose" rows="3">{@form_data["short_description"]}</textarea>
          </.field>
        <% end %>

        <%= if @editor_mode == :day do %>
          <.field label="Tab name">
            <input name="day[tab]" value={@form_data["tab"]} class="adm-input" required />
          </.field>
          <.field label="Description">
            <textarea name="day[description]" class="adm-input adm-input--prose" rows="3">{@form_data["description"]}</textarea>
          </.field>
        <% end %>
      </div>

      <div class="adm-editor-body">
        <div class="adm-tabs" role="tablist" aria-label="Markdown">
          <button
            type="button"
            class="adm-tab"
            role="tab"
            aria-selected={to_string(!@preview)}
            aria-current={!@preview && "page"}
            phx-click={@preview && "toggle_preview"}
          >
            Write
          </button>
          <button
            type="button"
            class="adm-tab"
            role="tab"
            aria-selected={to_string(@preview)}
            aria-current={@preview && "page"}
            phx-click={!@preview && "toggle_preview"}
          >
            Preview
          </button>
        </div>
        <%!-- The textarea stays in the form while previewing, or the save
              would go out without the body. --%>
        <textarea
          name={"#{@editor_mode}[content]"}
          class="adm-input adm-input--code"
          hidden={@preview}
          phx-debounce="400"
          aria-label="Markdown"
        >{@form_data["content"]}</textarea>
        <div :if={@preview} class="adm-prose">
          {raw(Earmark.as_html!(@form_data["content"] || "", gfm: true))}
        </div>
      </div>
    </form>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp field(assigns) do
    ~H"""
    <label class="adm-field">
      <span class="adm-label">{@label}</span>
      {render_slot(@inner_block)}
    </label>
    """
  end

  defp parse_date(text) do
    case Date.from_iso8601(text || "") do
      {:ok, date} -> date
      _ -> nil
    end
  end

  defp presence(nil), do: nil
  defp presence(value), do: if(String.trim(value) == "", do: nil, else: value)

  defp new_title(:exercise), do: "New exercise"
  defp new_title(:day), do: "New day"
end
