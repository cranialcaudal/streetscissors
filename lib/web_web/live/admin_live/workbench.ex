defmodule WebWeb.AdminLive.Workbench do
  @moduledoc """
  The writing workbench: one draft's file across four collapsible panels, shared by the blog's desk (`/admin/blog`) and its editor (`/admin/blog/:slug/edit`).

    1. **Articles & Zotero** (`#post-zotero`): the author's Zotero folders and
       documents beside the draft's top reading list, with read/to-read
       toggles, `> [!thought]` notes, citation keys and **Cite**, which types
       `[@key]` at the editor's cursor (`Web.Writing.Citations`).
    2. **Outline** (`#post-outline-progress`): section word targets, beats,
       paired phrasings, and **Use my phrasings**.
    3. **Draft** (`#panel-draft`): `WebWeb.DocumentEditor` over the whole file.
    4. **Preview** (`#post-preview`): the post as the site renders it,
       citations and References included, with beat cards on demand.

  **Every write is a save the author asks for.** Panel actions (a thought, a
  toggle, a Zotero import, a key) change the text in the editor and leave it
  unsaved; Save goes through `Web.Blog.write_source/4`, which refuses to write
  over a file that changed on disk and puts both versions on the table.

  The host LiveView calls `attach/1` in `mount/3` and handles
  `{:workbench_saved, slug}`, sent after each save. Attributes: `slug`
  (read on first render; later changes come from the desk's own picker),
  `mode` (`"editor"` renders a post's page head, `"desk"` a picker over
  `posts`, `"paper"` a paper's page head), `store` (`Web.Blog`, the
  default, or `Web.Writing.Papers`): where the file is read, saved and
  previewed.

  **Sources and beats.** Each beat lists the sources it leans on (cited in
  its prompt, its phrasings, or the prose under it); each source lists the
  beats that use it, and a thought on a source can be carried **To beat**,
  cited. Each section shows its first drafted sentence beside its beats, a
  reverse outline. **Export** sends the saved file through Pandoc
  (`Web.Writing.Export`).
  """

  use WebWeb, :live_component

  import WebWeb.AdminComponents
  import WebWeb.DocumentEditor, only: [document_editor: 1]

  alias Web.Blog
  alias Web.Writing.Outline
  alias Web.Writing.{Citations, Document, Export}
  alias Web.Writing.Zotero
  alias WebWeb.DocumentEditor

  @editor "post-source"
  @panels ~w(articles outline draft preview)

  @doc """
  Readies a host LiveView for the workbench, in its `mount/3`: the editor's
  completions (`WebWeb.DocumentEditor.attach/1`) and the workbench's flash
  messages, which the layout shows.
  """
  def attach(socket) do
    socket
    |> DocumentEditor.attach()
    |> Phoenix.LiveView.attach_hook(:workbench_flash, :handle_info, fn
      {:workbench_flash, kind, message}, socket ->
        {:halt, Phoenix.LiveView.put_flash(socket, kind, message)}

      _other, socket ->
        {:cont, socket}
    end)
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(:mode, Map.get(assigns, :mode, "editor"))
      |> assign(:store, Map.get(assigns, :store, Blog))
      |> assign(:posts, Map.get(assigns, :posts, []))
      |> assign(:id, assigns.id)

    if Map.has_key?(socket.assigns, :slug) do
      {:ok, socket}
    else
      configured? = Zotero.configured?()

      {:ok,
       socket
       |> assign(
         show_beats: false,
         collapsed_panels: MapSet.new(),
         conflict: nil,
         zotero_configured: configured?,
         zotero_root_target: Zotero.root_collection_target(),
         zotero_collections: [],
         zotero_selected_collection: nil,
         zotero_items: [],
         zotero_query: "",
         zotero_error: nil
       )
       |> open(assigns.slug)
       |> then(fn s -> if configured?, do: load_zotero(s, ""), else: s end)}
    end
  end

  # ── The file ──────────────────────────────────────────────────────────

  defp open(socket, slug) do
    case socket.assigns.store.read_source(slug) do
      {:ok, %{content: content, revision: revision}} ->
        socket
        |> assign(slug: slug, revision: revision, saved: content, conflict: nil)
        |> put_content(content)

      _ ->
        socket
        |> assign(slug: slug, revision: nil, saved: "", conflict: nil)
        |> put_content("")
    end
  end

  @impl true
  def handle_event("toggle_panel", %{"panel" => panel}, socket) when panel in @panels do
    collapsed = socket.assigns.collapsed_panels

    next =
      if MapSet.member?(collapsed, panel),
        do: MapSet.delete(collapsed, panel),
        else: MapSet.put(collapsed, panel)

    {:noreply, assign(socket, :collapsed_panels, next)}
  end

  def handle_event("select_post", %{"slug" => slug}, socket) do
    socket = socket |> open(slug) |> assign(:zotero_selected_collection, nil)
    socket = DocumentEditor.set(socket, @editor, socket.assigns.content)

    socket = if socket.assigns.zotero_configured, do: load_zotero(socket, ""), else: socket
    {:noreply, socket}
  end

  def handle_event("change", %{"content" => content}, socket) do
    {:noreply, put_content(socket, content)}
  end

  # The submitter says what the save is for: plain, or publishing with it.
  def handle_event("save", %{"content" => typed} = params, socket) do
    content =
      case params["then"] do
        "publish" -> Blog.mark_draft(typed, false)
        "unpublish" -> Blog.mark_draft(typed, true)
        _ -> typed
      end

    # Publishing rewrote the draft line: the editor is shown the new text.
    socket = if content == typed, do: socket, else: DocumentEditor.set(socket, @editor, content)

    {:noreply, socket |> put_content(content) |> save([])}
  end

  def handle_event("take_disk", _params, socket) do
    %{content: content, revision: revision} = socket.assigns.conflict

    {:noreply,
     socket
     |> assign(revision: revision, saved: content, conflict: nil)
     |> put_content(content)
     |> DocumentEditor.set(@editor, content)
     |> flash(:info, "Loaded the file as it is on disk.")}
  end

  def handle_event("save_over", _params, socket), do: {:noreply, save(socket, force: true)}

  def handle_event("keep_editing", _params, socket),
    do: {:noreply, assign(socket, :conflict, nil)}

  # ── Outline and reading list ──────────────────────────────────────────

  def handle_event("toggle_beats", _params, socket) do
    show_beats = not socket.assigns.show_beats

    {:noreply,
     assign(socket,
       show_beats: show_beats,
       html: preview_html(socket.assigns.store, socket.assigns.post, show_beats)
     )}
  end

  def handle_event("seed_beat", %{"beat" => beat}, socket) do
    {:noreply, edit(socket, &Outline.seed_beat_thoughts(&1, beat))}
  end

  def handle_event("add_beat_thought", %{"beat" => beat, "thought" => thought}, socket) do
    {:noreply, edit(socket, &Outline.add_beat_thought(&1, beat, thought))}
  end

  def handle_event("add_reading_thought", %{"index" => index, "thought" => thought}, socket) do
    {:noreply, with_index(socket, index, &Outline.add_reading_thought(&1, &2, thought))}
  end

  def handle_event("toggle_reading_item", %{"index" => index}, socket) do
    {:noreply, with_index(socket, index, &Outline.toggle_reading_item/2)}
  end

  def handle_event("key_reading_items", _params, socket) do
    {:noreply, edit(socket, &Outline.key_reading_items/1)}
  end

  # The key is written first (if the source had none), then `[@key]` is typed
  # at the cursor; the editor keeps its cursor through the first change.
  def handle_event("cite_reading_item", %{"index" => index}, socket) do
    case Integer.parse(to_string(index)) do
      {i, ""} ->
        {text, key} = Outline.ensure_reading_key(socket.assigns.content, i)
        {:noreply, socket |> apply_text(text) |> cite(key)}

      _ ->
        {:noreply, socket}
    end
  end

  # A reading's thought, carried to the beat it serves with its citation, so
  # the beat shows the source and the phrasing is ready to seed.
  def handle_event(
        "thought_to_beat",
        %{"index" => index, "thought" => thought, "beat" => beat},
        socket
      ) do
    with {i, ""} <- Integer.parse(to_string(index)),
         {t, ""} <- Integer.parse(to_string(thought)),
         %{thoughts: thoughts} <- Enum.at(socket.assigns.post.outline.research.items, i),
         text when is_binary(text) <- Enum.at(thoughts, t),
         true <- beat != "" do
      {keyed, key} = Outline.ensure_reading_key(socket.assigns.content, i)
      updated = Outline.add_beat_thought(keyed, beat, "#{text} [@#{key}]")

      {:noreply, socket |> apply_text(updated) |> flash(:info, "Carried to “#{beat}”.")}
    else
      _ -> {:noreply, socket}
    end
  end

  # ── Zotero ────────────────────────────────────────────────────────────

  def handle_event("zotero_toggle", _params, socket) do
    configured? = Zotero.configured?()

    socket =
      socket
      |> assign(
        collapsed_panels: MapSet.delete(socket.assigns.collapsed_panels, "articles"),
        zotero_configured: configured?,
        zotero_root_target: Zotero.root_collection_target(),
        zotero_error: nil,
        zotero_collections: []
      )

    {:noreply,
     if(configured?, do: load_zotero(socket, socket.assigns.zotero_query), else: socket)}
  end

  def handle_event("zotero_select_collection", %{"key" => key}, socket) do
    selected = if key == "", do: nil, else: key

    {:noreply,
     socket
     |> assign(:zotero_selected_collection, selected)
     |> load_zotero_items(socket.assigns.zotero_query, selected)}
  end

  def handle_event("zotero_search", %{"q" => q}, socket), do: {:noreply, load_zotero(socket, q)}

  def handle_event("zotero_create_folder", %{"name" => name}, socket) do
    parent = socket.assigns.zotero_selected_collection || :root

    case Zotero.create_collection(name, parent) do
      {:ok, col} ->
        {:noreply,
         socket
         |> assign(
           zotero_collections: refresh_zotero_collections(),
           zotero_selected_collection: col.key,
           zotero_error: nil
         )
         |> load_zotero_items(socket.assigns.zotero_query, col.key)
         |> flash(:info, "Opened Zotero folder “#{col.path}”.")}

      {:error, :blank_name} ->
        {:noreply, assign(socket, :zotero_error, "Enter a folder name.")}

      {:error, _} ->
        {:noreply, assign(socket, :zotero_error, "Could not create that folder in Zotero.")}
    end
  end

  def handle_event("zotero_create_item", params, socket) do
    target = target_collection(socket)

    case Zotero.create_item(params, target) do
      {:ok, item} ->
        {:noreply,
         socket
         |> edit(&Outline.insert_reading_items(&1, [item]))
         |> assign(zotero_collections: refresh_zotero_collections(), zotero_error: nil)
         |> load_zotero_items(socket.assigns.zotero_query, target)
         |> flash(:info, "Added “#{item.title}” to Zotero and the reading list.")}

      {:error, :blank_title} ->
        {:noreply, assign(socket, :zotero_error, "Document title is required.")}

      {:error, _} ->
        {:noreply, assign(socket, :zotero_error, "Could not add that document to Zotero.")}
    end
  end

  def handle_event("zotero_push_reading_list", _params, socket) do
    case target_collection(socket) do
      nil ->
        {:noreply, assign(socket, :zotero_error, "Select or create a Zotero folder first.")}

      target ->
        case Zotero.sync_reading_list(socket.assigns.post.outline.research.items, target) do
          {:ok, %{created: created, skipped: skipped}} ->
            noun = if length(created) == 1, do: "item", else: "items"

            msg =
              "Pushed #{length(created)} reading list #{noun} to Zotero" <>
                if(skipped > 0, do: " (#{skipped} already in folder).", else: ".")

            {:noreply,
             socket
             |> assign(zotero_collections: refresh_zotero_collections(), zotero_error: nil)
             |> load_zotero_items(socket.assigns.zotero_query, target)
             |> flash(:info, msg)}

          {:error, _} ->
            {:noreply,
             assign(socket, :zotero_error, "Could not push the reading list to Zotero.")}
        end
    end
  end

  def handle_event("zotero_import_item", %{"key" => key}, socket) do
    case Zotero.fetch_item_with_notes(key) do
      {:ok, item} ->
        {:noreply,
         socket
         |> edit(&Outline.insert_reading_items(&1, [item]))
         |> flash(:info, "Added “#{item.title}” to the reading list.")}

      {:error, _} ->
        {:noreply, assign(socket, :zotero_error, "Could not fetch that item from Zotero.")}
    end
  end

  # Into the reading list if it is not there yet, then cited at the cursor.
  def handle_event("zotero_cite_item", %{"key" => key}, socket) do
    case Zotero.fetch_item_with_notes(key) do
      {:ok, item} ->
        added = Outline.insert_reading_items(socket.assigns.content, [item])
        {text, cite_key} = Outline.reading_key_for_title(added, item.title)
        {:noreply, socket |> apply_text(text) |> cite(cite_key)}

      {:error, _} ->
        {:noreply, assign(socket, :zotero_error, "Could not fetch that item from Zotero.")}
    end
  end

  def handle_event("zotero_import_collection", %{"key" => key}, socket) do
    case Zotero.fetch_collection_with_notes(key) do
      {:ok, items} ->
        {:noreply,
         socket
         |> edit(&Outline.insert_reading_items(&1, items))
         |> flash(:info, "Imported #{length(items)} Zotero items into the reading list.")}

      {:error, _} ->
        {:noreply, assign(socket, :zotero_error, "Could not fetch that collection from Zotero.")}
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────

  # Flash is the layout's, so the host LiveView puts it (attach/1).
  defp flash(socket, kind, message) do
    send(self(), {:workbench_flash, kind, message})
    socket
  end

  defp with_index(socket, index, fun) do
    case Integer.parse(to_string(index)) do
      {i, ""} -> edit(socket, &fun.(&1, i))
      _ -> socket
    end
  end

  defp edit(socket, fun), do: apply_text(socket, fun.(socket.assigns.content))

  defp apply_text(socket, text) do
    if text == socket.assigns.content do
      socket
    else
      socket |> DocumentEditor.set(@editor, text) |> put_content(text)
    end
  end

  defp cite(socket, nil), do: flash(socket, :error, "That source is not in the reading list.")

  defp cite(socket, key) do
    push_event(socket, "editor:insert", %{id: @editor, text: "[@#{key}]"})
  end

  defp save(socket, opts) do
    %{slug: slug, content: content, revision: revision} = socket.assigns

    case socket.assigns.store.write_source(slug, content, revision, opts) do
      {:ok, revision} ->
        send(self(), {:workbench_saved, slug})

        message =
          if opts[:force],
            do: "Saved. The version it replaced is in the vault's .trash folder.",
            else: "Saved #{slug}.md."

        socket
        |> assign(revision: revision, saved: content, conflict: nil)
        |> flash(:info, message)

      {:error, :conflict, on_disk} ->
        socket
        |> assign(:conflict, on_disk)
        |> flash(:error, "Not saved: #{slug}.md changed on disk since you opened it.")

      _ ->
        flash(socket, :error, "Could not write #{slug}.md.")
    end
  end

  defp put_content(socket, content) do
    store = socket.assigns.store
    post = store.preview(socket.assigns.slug, content)
    show_beats = Map.get(socket.assigns, :show_beats, false)

    assign(socket,
      content: content,
      post: post,
      html: preview_html(store, post, show_beats),
      cites: Citations.check(Outline.strip(post.raw_body), post.outline.research.items)
    )
  end

  defp preview_html(store, post, true),
    do: Outline.render_with_beats(post.raw_body, &store.to_html/1)

  defp preview_html(store, post, false), do: store.to_html(post.body)

  defp target_collection(socket) do
    socket.assigns.zotero_selected_collection ||
      case Zotero.find_root_collection(socket.assigns.zotero_collections) do
        %{key: k} -> k
        nil -> nil
      end
  end

  defp refresh_zotero_collections do
    case Zotero.list_collections() do
      {:ok, list} -> list
      _ -> []
    end
  end

  # The folder the piece names (`zotero:`), else a subfolder named for it
  # (slug or title), else the root folder.
  defp default_selected_collection(collections, slug, post) do
    project = Document.project(Map.get(post, :meta, %{}))
    named = project.zotero && Zotero.find_collection(collections, project.zotero)
    names = [slug, post.title] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.map(&String.downcase/1)

    match =
      Enum.find(collections, fn c ->
        c.in_root? and not c.is_root? and String.downcase(c.name) in names
      end)

    cond do
      named -> named.key
      match -> match.key
      root = Enum.find(collections, & &1.is_root?) -> root.key
      true -> nil
    end
  end

  defp load_zotero(socket, q) do
    collections =
      if socket.assigns.zotero_collections == [],
        do: refresh_zotero_collections(),
        else: socket.assigns.zotero_collections

    selected =
      socket.assigns.zotero_selected_collection ||
        default_selected_collection(collections, socket.assigns.slug, socket.assigns.post)

    socket
    |> assign(zotero_collections: collections, zotero_selected_collection: selected)
    |> load_zotero_items(q, selected)
  end

  defp load_zotero_items(socket, q, collection) do
    case Zotero.search_items(q: q, collection: collection) do
      {:ok, items} ->
        assign(socket, zotero_items: items, zotero_query: q, zotero_error: nil)

      {:error, :auth_failed} ->
        assign(socket, zotero_error: "Zotero rejected ZOTERO_USER_ID or ZOTERO_API_KEY.")

      {:error, _} ->
        assign(socket, zotero_error: "Could not reach api.zotero.org.")
    end
  end

  defp lf(text), do: String.replace(text || "", "\r\n", "\n")

  # Read aloud for a video: about 150 words a minute, against the 200 the
  # site counts for reading on the page.
  @aloud_wpm 150
  defp aloud_min(words) when is_integer(words) and words > 0,
    do: max(1, round(words / @aloud_wpm))

  defp aloud_min(_), do: 0

  defp export_path(Web.Writing.Papers, slug, format),
    do: ~p"/admin/writing/#{slug}/export/#{format}"

  defp export_path(_blog, slug, format), do: ~p"/admin/blog/#{slug}/export/#{format}"

  # ── Render ────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:dirty, lf(assigns.content) != lf(assigns.saved))
      |> assign(
        :active_zotero_col,
        Enum.find(assigns.zotero_collections, &(&1.key == assigns.zotero_selected_collection))
      )
      |> assign(:unkeyed, Enum.count(assigns.post.outline.research.items, &is_nil(&1.key)))
      |> assign(
        :beat_titles,
        assigns.post.outline.sections |> Enum.flat_map(& &1.beats) |> Enum.map(& &1.title)
      )

    ~H"""
    <div id={@id} class="adm-workbench">
      <.page_head :if={@mode == "editor"} slug="Writing / Blog / Edit" title={@post.title}>
        <:lede>
          <code>{@slug}.md</code>, the file itself. Saving writes it back to the vault.
        </:lede>
        <:actions>
          <.link navigate={~p"/admin/blog"} class="adm-btn adm-btn--quiet">Back to the blog</.link>
          <.link href={~p"/blog/#{@slug}"} target="_blank" class="adm-btn adm-btn--quiet">
            <.icon name="hero-arrow-top-right-on-square" class="size-4" />
            {if @post.draft, do: "See the draft", else: "View"}
          </.link>
          <button
            form="post-editor"
            type="submit"
            name="then"
            value={if @post.draft, do: "publish", else: "unpublish"}
            class="adm-btn"
          >
            {if @post.draft, do: "Save and publish", else: "Save as a draft"}
          </button>
          <button form="post-editor" type="submit" class="adm-btn adm-btn--primary">Save</button>
        </:actions>
      </.page_head>

      <.page_head :if={@mode == "paper"} slug="Writing / Papers / Edit" title={@post.title}>
        <:lede>
          <code>{@slug}.md</code> in the writing folder. Never published; export it to send it.
        </:lede>
        <:actions>
          <.link navigate={~p"/admin/writing"} class="adm-btn adm-btn--quiet">
            Back to writing
          </.link>
          <button form="post-editor" type="submit" class="adm-btn adm-btn--primary">Save</button>
        </:actions>
      </.page_head>

      <section :if={@conflict} id="post-conflict" class="adm-conflict" role="alert">
        <h2 class="adm-conflict-title">This file changed on disk while you had it open</h2>
        <p>
          Someone, most likely you in Obsidian, saved <code>{@slug}.md</code>
          after this page loaded it. Nothing has been written. Your text is still in the editor.
        </p>
        <div class="adm-form-actions">
          <button type="button" phx-click="take_disk" phx-target={@myself} class="adm-btn">
            Take the version on disk
          </button>
          <button
            type="button"
            phx-click="save_over"
            phx-target={@myself}
            class="adm-btn adm-btn--danger"
            data-confirm="Save your text over the version on disk? That version is moved to the vault's .trash folder first."
          >
            Save mine over it
          </button>
          <button
            type="button"
            phx-click="keep_editing"
            phx-target={@myself}
            class="adm-btn adm-btn--quiet"
          >
            Keep editing
          </button>
        </div>
        <details class="adm-conflict-disk">
          <summary>What is on disk now</summary>
          <pre>{@conflict.content}</pre>
        </details>
      </section>

      <div id="wb-selector" class="adm-wb-bar">
        <div :if={@mode == "desk"} class="adm-wb-bar-left">
          <span class="adm-outline-label">Active essay:</span>
          <button
            :for={p <- Enum.take(@posts, 8)}
            type="button"
            id={"wb-pick-#{p.slug}"}
            phx-click="select_post"
            phx-value-slug={p.slug}
            phx-target={@myself}
            data-confirm={@dirty && p.slug != @slug && "Leave #{@slug}.md without saving?"}
            class={["adm-btn adm-btn--small adm-btn--quiet", @slug == p.slug && "is-active"]}
          >
            {p.title}
            <span :if={p.outline.has_outline?} class="adm-figure">
              ({p.outline.beats_done}/{p.outline.beats_total})
            </span>
          </button>
          <.link
            navigate={~p"/admin/blog/#{@slug}/edit"}
            class="adm-btn adm-btn--small adm-btn--primary"
            data-confirm={@dirty && "Leave #{@slug}.md without saving?"}
          >
            Open {@slug}.md in full editor
          </.link>
        </div>
        <div class="adm-wb-bar-right">
          <span class="adm-zotero-label">Panels:</span>
          <button
            :for={
              {key, label} <- [
                {"articles", "1. Articles & Zotero"},
                {"outline", "2. Outline"},
                {"draft", "3. Draft"},
                {"preview", "4. Preview"}
              ]
            }
            type="button"
            phx-click="toggle_panel"
            phx-value-panel={key}
            phx-target={@myself}
            aria-pressed={to_string(!MapSet.member?(@collapsed_panels, key))}
            class={[
              "adm-btn adm-btn--small adm-btn--quiet",
              !MapSet.member?(@collapsed_panels, key) && "is-active"
            ]}
          >
            {label}
          </button>
        </div>
      </div>

      <div id="pipeline-panels" class="adm-pipeline-1x4">
        <%!-- 1. Articles & Zotero --%>
        <section
          id="post-zotero"
          class="adm-panel adm-pipeline-col"
          data-collapsed={to_string(MapSet.member?(@collapsed_panels, "articles"))}
          aria-label="Zotero reading list"
        >
          <.fold_rail
            :if={MapSet.member?(@collapsed_panels, "articles")}
            panel="articles"
            target={@myself}
            label={"1. Articles & Zotero (#{@post.outline.research.total})"}
          />

          <%= if !MapSet.member?(@collapsed_panels, "articles") do %>
            <div class="adm-panel-head">
              <h2 class="adm-panel-title">
                1. Articles &amp; Zotero<span class="adm-count">{@post.outline.research.total}</span>
              </h2>
              <div class="adm-panel-actions">
                <button
                  type="button"
                  id="toggle-zotero"
                  phx-click="zotero_toggle"
                  phx-target={@myself}
                  class="adm-btn adm-btn--small adm-btn--quiet"
                >
                  Sync Zotero
                </button>
                <button
                  :if={@active_zotero_col}
                  type="button"
                  id="zotero-import-folder"
                  phx-click="zotero_import_collection"
                  phx-value-key={@active_zotero_col.key}
                  phx-target={@myself}
                  class="adm-btn adm-btn--small adm-btn--quiet"
                >
                  Pull (<span class="adm-figure">{@active_zotero_col.item_count}</span>)
                </button>
                <button
                  :if={@active_zotero_col && @post.outline.research.total > 0}
                  type="button"
                  id="zotero-push-reading-list"
                  phx-click="zotero_push_reading_list"
                  phx-target={@myself}
                  class="adm-btn adm-btn--small"
                >
                  Push (<span class="adm-figure">{@post.outline.research.total}</span>)
                </button>
                <.fold_button panel="articles" target={@myself} />
              </div>
            </div>

            <div class="adm-pipeline-col-body adm-zotero-body">
              <p :if={!@zotero_configured} class="adm-help">
                Set <code>ZOTERO_USER_ID</code>
                and <code>ZOTERO_API_KEY</code>
                in <code>.env</code>
                to connect your <code>{@zotero_root_target}</code>
                folder in Zotero.
              </p>

              <div :if={@zotero_configured} class="adm-zotero-subpanel">
                <p :if={@zotero_error} class="adm-zotero-error" role="alert">{@zotero_error}</p>

                <div :if={@zotero_collections != []} class="adm-zotero-collections">
                  <span class="adm-zotero-label">Zotero folders:</span>
                  <button
                    type="button"
                    phx-click="zotero_select_collection"
                    phx-value-key=""
                    phx-target={@myself}
                    aria-pressed={to_string(is_nil(@zotero_selected_collection))}
                    class={[
                      "adm-btn adm-btn--small adm-btn--quiet",
                      is_nil(@zotero_selected_collection) && "is-active"
                    ]}
                  >
                    All library
                  </button>
                  <button
                    :for={
                      col <-
                        Enum.filter(@zotero_collections, & &1.in_root?)
                        |> then(fn r -> if r != [], do: r, else: @zotero_collections end)
                    }
                    type="button"
                    id={"zotero-col-#{col.key}"}
                    phx-click="zotero_select_collection"
                    phx-value-key={col.key}
                    phx-target={@myself}
                    aria-pressed={to_string(@zotero_selected_collection == col.key)}
                    class={[
                      "adm-btn adm-btn--small adm-btn--quiet",
                      @zotero_selected_collection == col.key && "is-active"
                    ]}
                    title={"Open #{col.path}"}
                  >
                    {col.path} (<span class="adm-figure">{col.item_count}</span>)
                  </button>
                </div>

                <div class="adm-zotero-bars">
                  <form
                    id="zotero-search-form"
                    phx-submit="zotero_search"
                    phx-target={@myself}
                    class="adm-inline-form"
                  >
                    <input
                      type="search"
                      name="q"
                      value={@zotero_query}
                      class="adm-input adm-input--small"
                      placeholder="Search Zotero…"
                      aria-label="Search Zotero library"
                    />
                    <button type="submit" class="adm-btn adm-btn--small">Search</button>
                  </form>

                  <form
                    id="zotero-folder-form"
                    phx-submit="zotero_create_folder"
                    phx-target={@myself}
                    class="adm-inline-form"
                  >
                    <input
                      type="text"
                      name="name"
                      value=""
                      class="adm-input adm-input--small"
                      placeholder={"New folder in #{@zotero_root_target}…"}
                      aria-label="New Zotero subfolder name"
                    />
                    <button type="submit" class="adm-btn adm-btn--small adm-btn--quiet">
                      + Folder
                    </button>
                    <button
                      type="button"
                      id="zotero-folder-for-post"
                      phx-click="zotero_create_folder"
                      phx-value-name={@slug}
                      phx-target={@myself}
                      class="adm-btn adm-btn--small adm-btn--quiet"
                    >
                      Folder for {@slug}
                    </button>
                  </form>
                </div>

                <details id="zotero-add-doc" class="adm-outline-sections">
                  <summary>
                    + Add a document to {if @active_zotero_col,
                      do: @active_zotero_col.path,
                      else: @zotero_root_target} &amp; reading list
                  </summary>
                  <form
                    id="zotero-item-form"
                    phx-submit="zotero_create_item"
                    phx-target={@myself}
                    class="adm-zotero-doc-form"
                  >
                    <div class="adm-zotero-doc-grid">
                      <label class="adm-field">
                        <span>Type</span>
                        <select name="item_type" class="adm-select">
                          <option value="book">Book</option>
                          <option value="journalArticle">Journal article</option>
                          <option value="webpage">Webpage / article</option>
                          <option value="newspaperArticle">Newspaper article</option>
                          <option value="report">Report</option>
                        </select>
                      </label>
                      <label
                        :for={
                          {name, label, type, placeholder} <- [
                            {"title", "Title", "text", "The Future of Nostalgia"},
                            {"authors", "Author(s)", "text", "Last, First"},
                            {"publication", "Publisher / Journal", "text", "Basic Books"},
                            {"year", "Year", "text", "2001"},
                            {"call_number", "Call number", "text", "PN56.N6 B69 2001"},
                            {"url", "URL / DOI", "url", "https://…"},
                            {"note", "Your note / phrasing", "text", "What you thought about it…"}
                          ]
                        }
                        class="adm-field"
                      >
                        <span>{label}</span>
                        <input
                          type={type}
                          name={name}
                          required={name == "title"}
                          class="adm-input adm-input--small"
                          placeholder={placeholder}
                        />
                      </label>
                    </div>
                    <div class="adm-form-actions">
                      <button type="submit" class="adm-btn adm-btn--small adm-btn--primary">
                        Save to Zotero &amp; reading list
                      </button>
                    </div>
                  </form>
                </details>

                <ul :if={@zotero_items != []} class="adm-zotero-items">
                  <li
                    :for={item <- @zotero_items}
                    id={"zotero-item-#{item.key}"}
                    class="adm-zotero-item"
                  >
                    <div class="adm-zotero-item-main">
                      <strong class="adm-zotero-item-title">{item.title}</strong>
                      <span class="adm-zotero-item-meta">
                        {item.authors}{if item.year, do: " (#{item.year})"}
                        <span :if={item.call_number} class="adm-figure"> · {item.call_number}</span>
                      </span>
                    </div>
                    <div class="adm-zotero-item-actions">
                      <button
                        type="button"
                        phx-click="zotero_import_item"
                        phx-value-key={item.key}
                        phx-target={@myself}
                        class="adm-btn adm-btn--small"
                      >
                        Add to reading list
                      </button>
                      <button
                        type="button"
                        phx-click="zotero_cite_item"
                        phx-value-key={item.key}
                        phx-target={@myself}
                        class="adm-btn adm-btn--small adm-btn--quiet"
                        title="Add to the reading list and type [@key] at the cursor"
                      >
                        Cite
                      </button>
                    </div>
                  </li>
                </ul>
              </div>

              <div
                :if={@post.outline.research.total > 0}
                id="post-citations"
                class="adm-reading-block"
              >
                <div class="adm-outline-head">
                  <span class="adm-outline-label">
                    Citations: <span class="adm-figure">{length(@cites.cited)}</span>
                    cited · <span class="adm-figure">{length(@cites.uncited)}</span>
                    never cited
                  </span>
                  <button
                    :if={@unkeyed > 0}
                    type="button"
                    id="key-reading-items"
                    phx-click="key_reading_items"
                    phx-target={@myself}
                    class="adm-btn adm-btn--small adm-btn--quiet"
                    title="Adds ^key to the end of each source's line"
                  >
                    Give {@unkeyed} {if @unkeyed == 1, do: "source", else: "sources"} a key
                  </button>
                </div>
                <p :if={@cites.unknown != []} class="adm-zotero-error" role="alert">
                  No source for <code :for={key <- @cites.unknown} class="adm-cite-key">@{key}</code>
                </p>
              </div>

              <div :if={@post.outline.research.total > 0} class="adm-reading-block">
                <div class="adm-outline-head">
                  <span class="adm-outline-label">
                    Top Reading List (<span class="adm-figure">{@post.outline.research.checked}/{@post.outline.research.total}</span>
                    read · <span class="adm-figure">{@post.outline.research.with_thoughts}</span>
                    with thoughts)
                  </span>
                </div>
                <ul class="adm-outline-list adm-reading-list">
                  <li
                    :for={{item, idx} <- Enum.with_index(@post.outline.research.items)}
                    id={"reading-#{idx}"}
                    class={["adm-reading-item", item.done? && "is-done"]}
                  >
                    <div class="adm-reading-row">
                      <button
                        type="button"
                        phx-click="toggle_reading_item"
                        phx-value-index={idx}
                        phx-target={@myself}
                        class="adm-btn adm-btn--small adm-btn--quiet adm-reading-toggle"
                        title="Toggle read / to read"
                      >
                        <.pill tone={if(item.done?, do: "live", else: "quiet")}>
                          {if item.done?, do: "✓ read", else: "to read"}
                        </.pill>
                      </button>
                      <span class="adm-reading-source">{Web.Markdown.to_text(item.text)}</span>
                    </div>
                    <div class="adm-reading-cite">
                      <code
                        :if={item.key}
                        class={["adm-cite-key", item.key in @cites.uncited && "is-uncited"]}
                      >
                        @{item.key}
                      </code>
                      <button
                        type="button"
                        phx-click="cite_reading_item"
                        phx-value-index={idx}
                        phx-target={@myself}
                        class="adm-btn adm-btn--small adm-btn--quiet"
                        title="Type [@key] at the cursor in the draft"
                      >
                        Cite
                      </button>
                    </div>
                    <p :if={item.key} class="adm-reading-used">
                      <%= if item.used_in == [] do %>
                        No beat leans on it yet.
                      <% else %>
                        For: {Enum.join(item.used_in, " · ")}
                      <% end %>
                    </p>
                    <div
                      :for={{thought, t} <- Enum.with_index(item.thoughts)}
                      class="adm-reading-thought-row"
                    >
                      <p class="adm-reading-thought">“{thought}”</p>
                      <form
                        :if={@beat_titles != []}
                        id={"to-beat-#{idx}-#{t}"}
                        phx-submit="thought_to_beat"
                        phx-target={@myself}
                        class="adm-inline-form adm-to-beat"
                      >
                        <input type="hidden" name="index" value={idx} />
                        <input type="hidden" name="thought" value={t} />
                        <select
                          name="beat"
                          class="adm-select adm-select--small"
                          aria-label="The beat this thought serves"
                        >
                          <option :for={title <- @beat_titles} value={title}>{title}</option>
                        </select>
                        <button
                          type="submit"
                          class="adm-btn adm-btn--small adm-btn--quiet"
                          title="Adds the thought to the beat, cited"
                        >
                          To beat
                        </button>
                      </form>
                    </div>
                    <form
                      phx-submit="add_reading_thought"
                      phx-target={@myself}
                      class="adm-inline-form adm-thought-form"
                    >
                      <input type="hidden" name="index" value={idx} />
                      <input
                        type="text"
                        name="thought"
                        value=""
                        class="adm-input adm-input--small"
                        placeholder="What did you think about this source? (adds > [!thought])…"
                        aria-label={"Add thought for source #{idx + 1}"}
                      />
                      <button type="submit" class="adm-btn adm-btn--small adm-btn--quiet">
                        + Thought
                      </button>
                    </form>
                  </li>
                </ul>
              </div>
            </div>
          <% end %>
        </section>

        <%!-- 2. Outline & phrasings --%>
        <section
          id="post-outline-progress"
          class="adm-panel adm-pipeline-col"
          data-collapsed={to_string(MapSet.member?(@collapsed_panels, "outline"))}
          aria-label="Outline progress"
        >
          <.fold_rail
            :if={MapSet.member?(@collapsed_panels, "outline")}
            panel="outline"
            target={@myself}
            label={"2. Outline (#{@post.outline.beats_done}/#{@post.outline.beats_total})"}
          />

          <%= if !MapSet.member?(@collapsed_panels, "outline") do %>
            <div class="adm-panel-head">
              <h2 class="adm-panel-title">
                2. Outline<span class="adm-count">{@post.outline.beats_total}</span>
              </h2>
              <div class="adm-panel-actions">
                <div class="adm-outline-pills">
                  <.pill
                    :if={@post.outline.beats_total > 0}
                    tone={
                      if(@post.outline.beats_done == @post.outline.beats_total,
                        do: "live",
                        else: "draft"
                      )
                    }
                  >
                    <span class="adm-figure">
                      {@post.outline.beats_done}/{@post.outline.beats_total}
                    </span>
                    beats
                  </.pill>
                  <.pill
                    :if={@post.outline.research.total > 0}
                    tone={
                      if(@post.outline.research.checked == @post.outline.research.total,
                        do: "live",
                        else: "quiet"
                      )
                    }
                  >
                    <span class="adm-figure">
                      {@post.outline.research.checked}/{@post.outline.research.total}
                    </span>
                    sources
                    <span :if={@post.outline.research.with_thoughts > 0}>
                      · <span class="adm-figure">{@post.outline.research.with_thoughts}</span> notes
                    </span>
                  </.pill>
                </div>
                <.fold_button panel="outline" target={@myself} />
              </div>
            </div>

            <div class="adm-pipeline-col-body">
              <.empty :if={!@post.outline.has_outline?}>
                Add <code>&gt; [!beat] Title</code>
                blocks or section word targets <code>(~250 words)</code>
                in the draft to track outline progress here.
              </.empty>

              <ol :if={@post.outline.sections != []} class="adm-outline-list">
                <li :for={section <- @post.outline.sections} class="adm-outline-section">
                  <div class="adm-outline-section-row">
                    <span class="adm-outline-section-title">{section.title}</span>
                    <span class="adm-figure adm-outline-section-words">
                      {section.drafted_words}{if section.target_words,
                        do: " / #{section.target_words}"}w
                    </span>
                  </div>
                  <p :if={section.first_sentence} class="adm-outline-says">
                    <span class="adm-outline-label">Says:</span> {section.first_sentence}
                  </p>
                  <ul :if={section.beats != []} class="adm-outline-beats-cards">
                    <li
                      :for={beat <- section.beats}
                      class={["adm-outline-beat-card", beat.drafted? && "is-done"]}
                    >
                      <div class="adm-outline-beat-top">
                        <.pill tone={if(beat.drafted?, do: "live", else: "quiet")}>
                          {if beat.drafted?, do: "✓ #{beat.title}", else: beat.title}
                        </.pill>
                        <button
                          :if={beat.thoughts != [] and not beat.drafted?}
                          type="button"
                          phx-click="seed_beat"
                          phx-value-beat={beat.title}
                          phx-target={@myself}
                          class="adm-btn adm-btn--small adm-btn--quiet adm-seed-btn"
                          title="Drop this beat's thoughts beneath the beat as draft text"
                        >
                          Use my phrasings ({length(beat.thoughts)})
                        </button>
                      </div>
                      <p :if={beat.prompt != ""} class="adm-outline-beat-prompt">
                        {Web.Markdown.to_text(beat.prompt)}
                      </p>
                      <p class="adm-outline-beat-sources">
                        <code
                          :for={key <- beat.cites}
                          class={["adm-cite-key", key in @cites.unknown && "is-unknown"]}
                        >
                          @{key}
                        </code>
                        <span :if={beat.cites == []} class="adm-outline-label">No source yet</span>
                      </p>
                      <p :for={thought <- beat.thoughts} class="adm-reading-thought">
                        “{thought}”
                      </p>
                      <form
                        phx-submit="add_beat_thought"
                        phx-target={@myself}
                        class="adm-inline-form adm-thought-form"
                      >
                        <input type="hidden" name="beat" value={beat.title} />
                        <input
                          type="text"
                          name="thought"
                          value=""
                          class="adm-input adm-input--small"
                          placeholder="Put your phrasing / thought alongside this beat…"
                          aria-label={"Add phrasing to #{beat.title}"}
                        />
                        <button type="submit" class="adm-btn adm-btn--small adm-btn--quiet">
                          + Phrasing
                        </button>
                      </form>
                    </li>
                  </ul>
                </li>
              </ol>
            </div>
          <% end %>
        </section>

        <%!-- 3. Draft: hidden rather than removed when collapsed, so the
              editor keeps its text, cursor and undo history. --%>
        <section
          id="panel-draft"
          class="adm-panel adm-pipeline-col"
          data-collapsed={to_string(MapSet.member?(@collapsed_panels, "draft"))}
        >
          <.fold_rail
            :if={MapSet.member?(@collapsed_panels, "draft")}
            panel="draft"
            target={@myself}
            label={"3. Draft (#{@slug}.md)"}
          />

          <div class="adm-panel-head" hidden={MapSet.member?(@collapsed_panels, "draft")}>
            <h2 class="adm-panel-title">3. Draft</h2>
            <div class="adm-panel-actions">
              <.pill :if={@dirty} tone="held">unsaved</.pill>
              <.pill :if={!@dirty} tone="quiet">saved</.pill>
              <button
                :if={@mode == "desk"}
                form="post-editor"
                type="submit"
                class="adm-btn adm-btn--small adm-btn--primary"
              >
                Save
              </button>
              <details :if={Export.available?()} id="post-export" class="adm-export">
                <summary class="adm-btn adm-btn--small adm-btn--quiet">Export</summary>
                <div class="adm-export-menu">
                  <p :if={@dirty} class="adm-help">Exports the saved file: save first.</p>
                  <a
                    :for={{format, label} <- Export.formats()}
                    id={"export-#{format}"}
                    href={export_path(@store, @slug, format)}
                    class="adm-btn adm-btn--small adm-btn--quiet"
                    download
                  >
                    {label}
                  </a>
                </div>
              </details>
              <.fold_button panel="draft" target={@myself} />
            </div>
          </div>

          <form
            id="post-editor"
            class="adm-pipeline-col-body"
            phx-change="change"
            phx-submit="save"
            phx-target={@myself}
            data-dirty={to_string(@dirty)}
            hidden={MapSet.member?(@collapsed_panels, "draft")}
          >
            <.document_editor
              id="post-source"
              name="content"
              value={@content}
              complete="blog"
              media
              debounce="300"
              label={"Source of #{@slug}.md"}
            />
          </form>
        </section>

        <%!-- 4. Preview --%>
        <section
          id="post-preview"
          class="adm-panel adm-pipeline-col"
          data-collapsed={to_string(MapSet.member?(@collapsed_panels, "preview"))}
        >
          <.fold_rail
            :if={MapSet.member?(@collapsed_panels, "preview")}
            panel="preview"
            target={@myself}
            label={"4. Preview (#{@post.word_count}w)"}
          />

          <%= if !MapSet.member?(@collapsed_panels, "preview") do %>
            <div class="adm-panel-head">
              <h2 class="adm-panel-title">4. Preview</h2>
              <div class="adm-panel-actions">
                <button
                  :if={@post.outline.has_outline?}
                  type="button"
                  id="toggle-beats"
                  phx-click="toggle_beats"
                  phx-target={@myself}
                  aria-pressed={to_string(@show_beats)}
                  class="adm-btn adm-btn--small adm-btn--quiet"
                >
                  {if @show_beats, do: "Prose only", else: "Show beats"}
                </button>
                <.pill :if={@post.draft} tone="draft">draft</.pill>
                <.pill :if={!@post.draft} tone="live">published</.pill>
                <.fold_button panel="preview" target={@myself} />
              </div>
            </div>

            <div class="adm-pipeline-col-body">
              <h2 class="adm-preview-title">{@post.title}</h2>
              <dl class="adm-facts">
                <div>
                  <dt>Date</dt>
                  <dd class="adm-figure">{stamp(@post.date)}</dd>
                </div>
                <div>
                  <dt>Length</dt>
                  <dd>
                    <span class="adm-figure">{@post.word_count}</span>
                    <span :if={@post.outline.target_words}>
                      / <span class="adm-figure">{@post.outline.target_words}</span>
                    </span>
                    words, <span class="adm-figure">{@post.read_min}</span>
                    min
                  </dd>
                </div>
                <div id="post-aloud">
                  <dt>Aloud</dt>
                  <dd>
                    <span class="adm-figure">{aloud_min(@post.word_count)}</span>
                    min read aloud<span :if={@post.outline.target_words}>,
                    <span class="adm-figure">{aloud_min(@post.outline.target_words)}</span>
                    at the goal</span>
                  </dd>
                </div>
                <div>
                  <dt>Keywords</dt>
                  <dd>
                    <.keyword_chips keywords={@post.keywords} />
                    <.pill :if={@post.keywords == []} tone="held">none</.pill>
                  </dd>
                </div>
                <div>
                  <dt>Description</dt>
                  <dd>
                    <span :if={@post.described}>{@post.excerpt}</span>
                    <.pill :if={!@post.described} tone="held">
                      none: the first paragraph stands in
                    </.pill>
                  </dd>
                </div>
              </dl>

              <div class="adm-prose">{raw(@html)}</div>
            </div>
          <% end %>
        </section>
      </div>
    </div>
    """
  end

  attr :panel, :string, required: true
  attr :target, :any, required: true
  attr :label, :string, required: true

  defp fold_rail(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_panel"
      phx-value-panel={@panel}
      phx-target={@target}
      class="adm-pipeline-rail-btn"
      title={"Expand #{@label}"}
    >
      <span>+</span>
      <span class="adm-pipeline-rail-label">{@label}</span>
    </button>
    """
  end

  attr :panel, :string, required: true
  attr :target, :any, required: true

  defp fold_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="toggle_panel"
      phx-value-panel={@panel}
      phx-target={@target}
      class="adm-btn adm-btn--small adm-btn--quiet"
      title="Collapse panel"
    >
      −
    </button>
    """
  end
end
