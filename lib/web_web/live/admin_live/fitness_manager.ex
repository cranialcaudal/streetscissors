defmodule WebWeb.AdminLive.FitnessManager do
  @moduledoc """
  The fitness vault's editor: the exercise wiki and the regimen's days, each
  a markdown file under `content/fitness/` (`Web.Fitness.Vault`), so the vault
  in Obsidian and this page write the same files.

  Which list is showing is in the URL (`?tab=wiki|regimen|log`). Editing opens in
  the page rather than over it — fields on the left, the markdown on the
  right with a preview a click away — and a name filter narrows the wiki.

  The third tab is the training log (`Web.Fitness.log_exercise/2`): what the
  Log buttons on `/fitness` wrote, an entry form for a day that was missed,
  and one exercise's history at `?tab=log&exercise=<slug>`. It is in the
  database, not the vault, and no public page shows it.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Fitness
  alias Web.Fitness.Vault

  @tabs ~w(wiki regimen log)

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
         preview: false,
         log_exercise: nil,
         logs: [],
         logged: Fitness.logged_exercises()
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "wiki"
    socket = assign(socket, tab: tab, editor_mode: nil, editing_item: nil)

    if tab == "log" do
      exercise = if params["exercise"] in Vault.exercise_slugs(), do: params["exercise"]
      {:noreply, socket |> assign(:log_exercise, exercise) |> load_logs()}
    else
      {:noreply, socket}
    end
  end

  # --- The training log ---

  def handle_event("add_log", %{"log" => params}, socket) do
    case Fitness.log_exercise(params["slug"] || "", params) do
      {:ok, log} ->
        {:noreply,
         socket
         |> put_flash(:info, "Logged #{exercise_name(socket.assigns.exercises, log.slug)}.")
         |> load_logs()}

      {:error, :unknown_exercise} ->
        {:noreply, put_flash(socket, :error, "Choose an exercise from the wiki.")}

      {:error, %Ecto.Changeset{errors: [{:base, _} | _]}} ->
        {:noreply, put_flash(socket, :error, "Enter at least one value to log.")}

      {:error, %Ecto.Changeset{errors: [{field, _} | _]}} ->
        {:noreply, put_flash(socket, :error, "That #{field} doesn't look right.")}
    end
  end

  def handle_event("delete_log", %{"id" => id}, socket) do
    Fitness.delete_exercise_log(id)
    {:noreply, socket |> put_flash(:info, "Entry deleted.") |> load_logs()}
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

  defp load_logs(socket) do
    opts = if slug = socket.assigns.log_exercise, do: [slug: slug], else: [limit: 200]

    assign(socket,
      logs: Fitness.list_exercise_logs(opts),
      logged: Fitness.logged_exercises()
    )
  end

  defp exercise_name(exercises, slug) do
    Enum.find_value(exercises, slug, fn {_group, list} ->
      Enum.find_value(list, &(&1.slug == slug && &1.name))
    end)
  end

  defp log_count(logged), do: logged |> Enum.map(&elem(&1, 1)) |> Enum.sum()

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
      <.page_head slug="Write / Fitness" title="Fitness">
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
          <.link :if={@tab == "log"} href={~p"/fitness/export/csv"} class="adm-btn adm-btn--quiet">
            Download CSV
          </.link>
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
        <:tab patch={~p"/admin/fitness?tab=log"} active={@tab == "log"} count={log_count(@logged)}>
          Training log
        </:tab>
      </.tabs>

      <%= case @tab do %>
        <% "wiki" -> %>
          {render_exercises(assigns)}
        <% "regimen" -> %>
          {render_days(assigns)}
        <% "log" -> %>
          {render_log(assigns)}
      <% end %>
    <% end %>
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
      <.rows id={"exercises-#{group}"} rows={exercises}>
        <:col :let={ex} label="Exercise" class="adm-cell-title adm-w-name">{ex.name}</:col>
        <:col :let={ex} label="Category" class="adm-w-mid">{ex.functional_category || "—"}</:col>
        <:col :let={ex} label="Anatomy">{ex.anatomy || "—"}</:col>
        <:action :let={ex}>
          <button phx-click="edit_exercise" phx-value-slug={ex.slug} class="adm-link">Edit</button>
        </:action>
        <:action :let={ex}>
          <button
            phx-click="delete_exercise"
            phx-value-slug={ex.slug}
            phx-value-group={group}
            data-confirm={"Delete #{ex.name} from the wiki? The file goes too."}
            class="adm-link adm-link--danger"
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
    <.rows id="days" rows={@days}>
      <:col :let={day} label="Day" class="adm-cell-title">{day.title}</:col>
      <:col :let={day} label="Tab">{day.tab}</:col>
      <:col :let={day} label="File">{day.slug}.md</:col>
      <:action :let={day}>
        <button phx-click="edit_day" phx-value-slug={day.slug} class="adm-link">Edit</button>
      </:action>
      <:empty>No days in the regimen yet.</:empty>
    </.rows>
    """
  end

  defp render_log(assigns) do
    assigns =
      assign(assigns,
        today: Web.Clock.local_today(),
        best: assigns.log_exercise && Fitness.best_weight(assigns.log_exercise)
      )

    ~H"""
    <.panel title="Add an entry" id="log-entry">
      <%!-- Keyed on the newest entry, so a saved form comes back empty. --%>
      <form
        phx-submit="add_log"
        id={"log-form-#{@logs |> List.first() |> then(&(&1 && &1.id))}"}
        class="adm-log-form"
      >
        <div class="adm-form-row">
          <.field label="Exercise">
            <select name="log[slug]" class="adm-input" required>
              <option value="">Choose…</option>
              <optgroup :for={{group, exercises} <- @exercises} label={group}>
                <option :for={ex <- exercises} value={ex.slug} selected={ex.slug == @log_exercise}>
                  {ex.name}
                </option>
              </optgroup>
            </select>
          </.field>
          <.field label="Date">
            <input type="date" name="log[date]" value={@today} max={@today} class="adm-input" />
          </.field>
        </div>
        <div class="adm-form-row">
          <.field label="Weight (lb)">
            <input
              type="number"
              name="log[weight]"
              step="any"
              min="0"
              inputmode="decimal"
              class="adm-input"
            />
          </.field>
          <.field label="Sets">
            <input type="number" name="log[sets]" min="1" inputmode="numeric" class="adm-input" />
          </.field>
          <.field label="Reps">
            <input type="number" name="log[reps]" min="1" inputmode="numeric" class="adm-input" />
          </.field>
        </div>
        <div class="adm-form-row">
          <.field label="Distance">
            <input name="log[distance]" class="adm-input" placeholder="2 miles" />
          </.field>
          <.field label="Time">
            <input name="log[time]" class="adm-input" placeholder="8:26 pace" />
          </.field>
          <.field label="Result">
            <input name="log[result]" class="adm-input" placeholder="30 inches, to failure" />
          </.field>
        </div>
        <.field label="Note">
          <input name="log[note]" class="adm-input" />
        </.field>
        <div class="adm-form-actions">
          <button type="submit" class="adm-btn adm-btn--primary">Add entry</button>
        </div>
      </form>
    </.panel>

    <nav :if={@logged != []} class="adm-log-filter" aria-label="Exercises with entries">
      <.link
        patch={~p"/admin/fitness?tab=log"}
        class="adm-link"
        aria-current={@log_exercise == nil && "page"}
      >
        All
      </.link>
      <.link
        :for={{slug, count} <- @logged}
        patch={~p"/admin/fitness?tab=log&exercise=#{slug}"}
        class="adm-link"
        aria-current={@log_exercise == slug && "page"}
      >
        {exercise_name(@exercises, slug)}<span class="adm-count">{count}</span>
      </.link>
    </nav>

    <div :if={@log_exercise && @logs != []} class="adm-stats">
      <.stat value={length(@logs)} label="Entries" />
      <.stat
        :if={@best}
        value={Fitness.format_weight(@best) <> " lb"}
        label="Heaviest"
        tone="live"
      />
      <.stat
        value={Fitness.describe_log(hd(@logs))}
        label="Last time"
        note={stamp(hd(@logs).date)}
      />
    </div>

    <.rows id="training-log" rows={@logs} row_id={&"log-#{&1.id}"}>
      <:col :let={log} label="Date" class="adm-w-mid">{stamp(log.date)}</:col>
      <:col :let={log} label="Exercise" class="adm-cell-title adm-w-name">
        <.link patch={~p"/admin/fitness?tab=log&exercise=#{log.slug}"} class="adm-link">
          {exercise_name(@exercises, log.slug)}
        </.link>
      </:col>
      <:col :let={log} label="Done">{Fitness.describe_log(log)}</:col>
      <:col :let={log} label="Note">{log.note}</:col>
      <:action :let={log}>
        <button
          phx-click="delete_log"
          phx-value-id={log.id}
          data-confirm="Delete this entry?"
          class="adm-link adm-link--danger"
        >
          Delete
        </button>
      </:action>
      <:empty>
        {if @log_exercise,
          do: "Nothing logged for this exercise yet.",
          else:
            "Nothing logged yet. The Log buttons on /fitness write here, and so does the form above."}
      </:empty>
    </.rows>
    """
  end

  defp render_editor(assigns) do
    ~H"""
    <.page_head
      slug={"Write / Fitness / " <> if(@editor_mode == :exercise, do: "Exercise", else: "Day")}
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

  defp presence(nil), do: nil
  defp presence(value), do: if(String.trim(value) == "", do: nil, else: value)

  defp new_title(:exercise), do: "New exercise"
  defp new_title(:day), do: "New day"
end
