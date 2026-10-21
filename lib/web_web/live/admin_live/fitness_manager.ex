defmodule WebWeb.AdminLive.FitnessManager do
  @moduledoc """
  The fitness vault's editor: the exercise wiki and the regimen's days, each
  a markdown file under `content/fitness/` (`Web.Fitness.Vault`), so the vault
  in Obsidian and this page write the same files.

  Which list is showing is in the URL (`?tab=wiki|regimen|progress|checkin`):
  the progress tab is the training block's charts (`WebWeb.FitnessCharts`),
  the check-in tab a day's answers to the checks `content/fitness/checkins.md`
  lists (`Web.Fitness.Checks`), which the guardrails read
  (`Web.Fitness.Guardrails`), with the recent history. Today's check-in can
  also be made on the day page itself (`/fitness`). Editing opens in
  the page rather than over it — fields on the left, the markdown on the
  right with a preview a click away — and a name filter narrows the wiki.

  ## How this file is laid out

  1. **Opening the page** (`mount/3`, `handle_params/3`): the tab in the
     address (`?tab=`), and what each tab loads.
  2. **Buttons** (`handle_event/3`): saving a check-in, and editing the
     week's days and the wiki's exercises (both written back to the vault's
     markdown files).
  3. **Helpers**, then **the page itself** (`render/1`).
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents
  import WebWeb.DocumentEditor, only: [document_editor: 1]

  alias Web.Fitness
  alias WebWeb.DocumentEditor
  alias Web.Fitness.{Block, Checks, Guardrails, SourceCheck, Training, Vault}
  alias Web.SourceFile

  @tabs ~w(wiki regimen progress checkin files)

  # ── Opening the page ──────────────────────────────────────────────────────

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
       )
       |> DocumentEditor.attach()}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "wiki"

    socket =
      socket
      |> assign(tab: tab, editor_mode: nil, editing_item: nil)
      |> assign_progress(tab)

    {:noreply, if(tab == "files", do: assign_source(socket, params["file"]), else: socket)}
  end

  # The Files tab: one of the vault's hand-written files, whole, as it is on
  # disk, with its revision (Web.SourceFile) and what its parser reads in it
  # (Web.Fitness.SourceCheck).
  defp assign_source(socket, id) do
    files = SourceCheck.files()
    file = SourceCheck.file(id || "week") || hd(files)
    {:ok, %{content: content, revision: revision}} = SourceFile.read(file.path)

    assign(socket,
      source_files: files,
      source: file,
      source_text: content,
      source_revision: revision,
      source_check: SourceCheck.check(file.id, content),
      source_conflict: nil
    )
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

    checks = Checks.all()

    standing =
      recent
      |> Guardrails.today(today, checks)
      |> Enum.map_join(" · ", fn {label, answer, _} -> "#{label}: #{answer}" end)

    assign(socket,
      checks: checks,
      checkins: recent,
      checkin_form:
        to_form(Fitness.change_checkin(todays || %Fitness.Checkin{date: today}), as: :checkin),
      guard: if(standing == "", do: nil, else: standing)
    )
  end

  # ── Buttons: check-ins, days and exercises ────────────────────────────────

  def handle_event("save_checkin", %{"checkin" => params}, socket) do
    params = Map.update(params, "date", nil, &parse_date/1)

    case Fitness.save_checkin(params, socket.assigns.checks) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Check-in saved.") |> assign_checkins()}

      {:error, changeset} ->
        {:noreply, assign(socket, checkin_form: to_form(changeset, as: :checkin))}
    end
  end

  # --- The Files tab ---

  # Checked as it is typed: the parser's reading of the text, before saving.
  def handle_event("check_source", %{"source" => %{"content" => content}}, socket) do
    {:noreply,
     assign(socket,
       source_text: content,
       source_check: SourceCheck.check(socket.assigns.source.id, content)
     )}
  end

  # Saved only when its parser reads all of it, and only over the revision it
  # was opened at; "save anyway" keeps the version on disk in the vault's
  # .trash/ first.
  def handle_event("save_source", %{"source" => %{"content" => content}} = params, socket) do
    %{source: file, source_revision: revision} = socket.assigns

    case SourceCheck.check(file.id, content) do
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(source_text: content, source_check: {:error, reason})
         |> put_flash(:error, "Not saved: #{reason}")}

      {:ok, _} ->
        trash = Path.join(Path.dirname(Vault.base_path()), ".trash")
        force? = params["force"] == "true"

        case SourceFile.write(file.path, content, revision, force: force?, trash: trash) do
          {:ok, new_revision} ->
            {:noreply,
             socket
             |> assign(source_text: content, source_revision: new_revision, source_conflict: nil)
             |> put_flash(:info, "Saved #{Path.basename(file.path)}.")}

          {:error, :conflict, on_disk} ->
            {:noreply,
             socket
             |> assign(source_text: content, source_conflict: on_disk)
             |> put_flash(:error, "#{Path.basename(file.path)} changed on disk since it was opened.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Not saved: #{inspect(reason)}")}
        end
    end
  end

  # Take the version on disk instead, dropping the edit here.
  def handle_event("take_disk", _params, socket) do
    socket = assign_source(socket, socket.assigns.source.id)

    {:noreply,
     DocumentEditor.set(socket, source_editor_id(socket.assigns.source), socket.assigns.source_text)}
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

  # ── Helpers ───────────────────────────────────────────────────────────────

  # Opening an item again while it is open reloads it, so the editor is told.
  defp open_editor(socket, mode, item, form) do
    socket
    |> assign(editor_mode: mode, editing_item: item, form_data: form, preview: false)
    |> DocumentEditor.set(wiki_editor_id(mode, item), form["content"] || "")
  end

  # Each file and item gets its own editor id, so moving to another one mounts
  # a fresh editor over its text (the editor is never patched in place).
  defp source_editor_id(%{id: id}), do: "source-" <> String.replace(id, ~r/[^\w-]/, "-")

  defp wiki_editor_id(mode, item), do: "wiki-#{mode}-#{(item && item.slug) || "new"}"

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

  # ── The page itself (render) ──────────────────────────────────────────────

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
        <:tab patch={~p"/admin/fitness?tab=files"} active={@tab == "files"}>
          Files
        </:tab>
      </.tabs>

      {case @tab do
        "wiki" -> render_exercises(assigns)
        "regimen" -> render_days(assigns)
        "progress" -> render_progress(assigns)
        "checkin" -> render_checkin(assigns)
        "files" -> render_files(assigns)
      end}
    <% end %>
    """
  end

  defp render_files(assigns) do
    ~H"""
    <section class="adm-fit-files" id="fitness-files">
      <nav class="adm-fit-files-list" aria-label="Files">
        <.link
          :for={file <- @source_files}
          patch={~p"/admin/fitness?tab=files&file=#{file.id}"}
          class={["adm-btn adm-btn--quiet adm-btn--small", file.id == @source.id && "is-on"]}
          aria-current={file.id == @source.id && "page"}
        >
          {file.label}
        </.link>
      </nav>

      <form id="source-form" phx-change="check_source" phx-submit="save_source">
        <.document_editor
          id={source_editor_id(@source)}
          name="source[content]"
          value={@source_text}
          label={@source.label}
        />

        <p
          id="source-check"
          class={["adm-help", match?({:error, _}, @source_check) && "adm-error"]}
          role="status"
        >
          {case @source_check do
            {:ok, summary} -> "Reads as: #{summary}."
            {:error, reason} -> "Will not be saved: #{reason}"
          end}
        </p>

        <div :if={@source_conflict} class="adm-fit-conflict" id="source-conflict" role="alert">
          <p>
            The file changed on disk since it was opened (Obsidian, most likely). Take the version
            on disk, or save this one over it; the version on disk is then kept in the vault's
            .trash first.
          </p>
          <button type="button" phx-click="take_disk" class="adm-btn adm-btn--small">
            Take the version on disk
          </button>
          <button
            type="submit"
            name="force"
            value="true"
            class="adm-btn adm-btn--small adm-btn--danger"
          >
            Save this one over it
          </button>
        </div>

        <div>
          <button type="submit" class="adm-btn adm-btn--primary" phx-disable-with="Saving…">
            Save
          </button>
        </div>
      </form>
    </section>
    """
  end

  defp render_checkin(%{checks: []} = assigns) do
    ~H"""
    <.empty>
      No checks are defined. A check-in asks what <code>content/fitness/checkins.md</code>
      lists, one section per check.
    </.empty>
    """
  end

  defp render_checkin(assigns) do
    assigns = assign(assigns, :answers, assigns.checkin_form[:answers].value || %{})

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

        <%!-- A state check is one tap: its states as a row of choices, the
              first the good one. A number check is a measurement. --%>
        <fieldset :for={check <- @checks} class="adm-fit-check" id={"check-#{check.id}"}>
          <legend class="adm-label">{check.label}</legend>
          <%= if check.kind == :state do %>
            <div class="adm-fit-states">
              <label
                :for={state <- check.states}
                class={["adm-fit-state", "adm-fit-state--#{Checks.level(check, state)}"]}
              >
                <input
                  type="radio"
                  name={"checkin[answers][#{check.id}]"}
                  value={state}
                  checked={@answers[check.id] == state}
                />
                <span>{state}</span>
              </label>
              <label class="adm-fit-state adm-fit-state--skip">
                <input
                  type="radio"
                  name={"checkin[answers][#{check.id}]"}
                  value=""
                  checked={is_nil(@answers[check.id])}
                />
                <span>skip</span>
              </label>
            </div>
          <% else %>
            <input
              type="text"
              inputmode="decimal"
              name={"checkin[answers][#{check.id}]"}
              value={@answers[check.id]}
              class="adm-input"
              placeholder={check.unit}
            />
          <% end %>
        </fieldset>

        <.field label="Note">
          <input
            type="text"
            name="checkin[note]"
            value={@checkin_form[:note].value}
            class="adm-input"
          />
        </.field>
        <p :for={{field, error} <- @checkin_form.errors} class="adm-error">
          {if field != :answers, do: Phoenix.Naming.humanize(field)} {WebWeb.CoreComponents.translate_error(
            error
          )}
        </p>
        <div>
          <button type="submit" class="adm-btn adm-btn--primary">Save check-in</button>
        </div>
      </.form>

      <.rows :if={@checkins != []} id="checkins" rows={@checkins}>
        <:col :let={c} label="Day">{Calendar.strftime(c.date, "%a %-d %b")}</:col>
        <:col :let={c} :for={check <- @checks} label={check.label}>
          {c.answers[check.id]}{if check.unit && c.answers[check.id], do: " #{check.unit}"}
        </:col>
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
        · <.link navigate={~p"/admin/fitness/block"} class="adm-link">Block report</.link>
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
        <%!-- The editor stays in the form while previewing, or the save
              would go out without the body. The preview is the vault's own
              rendering, so [[wiki]] links show as the public page has them. --%>
        <.document_editor
          id={wiki_editor_id(@editor_mode, @editing_item)}
          name={"#{@editor_mode}[content]"}
          value={@form_data["content"]}
          complete="fitness"
          hidden={@preview}
          label="Markdown"
        />
        <div :if={@preview} class="adm-prose">
          {raw(Vault.render_markdown(@form_data["content"] || ""))}
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
