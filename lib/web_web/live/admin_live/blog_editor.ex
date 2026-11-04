defmodule WebWeb.AdminLive.BlogEditor do
  @moduledoc """
  One post's file, edited in the admin with the page it will make beside it.

  What is edited is the **whole file**, frontmatter included — the same text
  Obsidian shows. There is no form of fields standing between the author and
  the file: the title, the date, the keywords and `draft: true` are lines in
  it, and the line above the preview reads them back the way the site will
  (`Blog.preview/2`), so a typo in the frontmatter shows before it is saved.

  **Saving never silently wins.** The editor remembers the revision the file
  was at when it was opened (`Blog.read_source/1`). If the file has changed on
  disk since — an edit made in Obsidian while this tab sat open — the save is
  refused and both versions are put on the table: take the one on disk, or
  save this one over it, in which case the replaced version goes to the
  vault's `.trash/` first. Either way neither edit is destroyed.

  The text is edited in `WebWeb.DocumentEditor` (CodeMirror over the file's
  own text, so nothing untyped changes): ⌘S / Ctrl+S saves, `[[` and `![[`
  offer posts, logs, rolls, frames and rides, and leaving with unsaved text
  asks first (the form's `data-dirty`). When the server changes the text
  itself (publishing edits the `draft:` line; taking the version on disk), it
  tells the editor with `DocumentEditor.set/3`.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents
  import WebWeb.DocumentEditor, only: [document_editor: 1]

  alias Web.Blog
  alias Web.Blog.Outline
  alias Web.Zotero
  alias WebWeb.DocumentEditor

  def mount(%{"slug" => slug}, session, socket) do
    if session["admin_user"] do
      case Blog.read_source(slug) do
        {:ok, %{content: content, revision: revision}} ->
          {:ok,
           socket
           |> assign(
             page_title: "#{slug}.md | Admin",
             slug: slug,
             revision: revision,
             saved: content,
             conflict: nil,
             show_beats: false,
             zotero_open: false,
             zotero_configured: Zotero.configured?(),
             zotero_root_target: Zotero.root_collection_target(),
             zotero_collections: [],
             zotero_selected_collection: nil,
             zotero_items: [],
             zotero_query: "",
             zotero_error: nil
           )
           |> DocumentEditor.attach()
           |> put_content(content)}

        _ ->
          {:ok,
           socket
           |> put_flash(:error, "There is no #{slug}.md in the blog.")
           |> push_navigate(to: ~p"/admin/blog")}
      end
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_event("change", %{"content" => content}, socket) do
    {:noreply, put_content(socket, content)}
  end

  def handle_event("toggle_beats", _params, socket) do
    show_beats = not socket.assigns.show_beats
    html = preview_html(socket.assigns.post, show_beats)
    {:noreply, assign(socket, show_beats: show_beats, html: html)}
  end

  def handle_event("seed_beat", %{"beat" => beat_title}, socket) do
    updated = Outline.seed_beat_thoughts(socket.assigns.content, beat_title)

    socket =
      if updated == socket.assigns.content do
        socket
      else
        socket
        |> DocumentEditor.set("post-source", updated)
        |> put_content(updated)
      end

    {:noreply, socket}
  end

  def handle_event("zotero_toggle", _params, socket) do
    open? = not socket.assigns.zotero_open
    configured? = Zotero.configured?()

    socket =
      socket
      |> assign(
        zotero_open: open?,
        zotero_configured: configured?,
        zotero_root_target: Zotero.root_collection_target(),
        zotero_error: nil
      )
      |> then(fn s ->
        if open? and configured? and s.assigns.zotero_collections == [] and
             s.assigns.zotero_items == [] do
          load_zotero(s, "")
        else
          s
        end
      end)

    {:noreply, socket}
  end

  def handle_event("zotero_select_collection", %{"key" => key}, socket) do
    selected = if key == "", do: nil, else: key

    {:noreply,
     socket
     |> assign(:zotero_selected_collection, selected)
     |> load_zotero_items(socket.assigns.zotero_query, selected)}
  end

  def handle_event("zotero_search", %{"q" => q}, socket) do
    {:noreply, load_zotero(socket, q)}
  end

  def handle_event("zotero_create_folder", %{"name" => name}, socket) do
    parent = socket.assigns.zotero_selected_collection || :root

    case Zotero.create_collection(name, parent) do
      {:ok, col} ->
        cols = refresh_zotero_collections()

        {:noreply,
         socket
         |> assign(
           zotero_collections: cols,
           zotero_selected_collection: col.key,
           zotero_error: nil
         )
         |> load_zotero_items(socket.assigns.zotero_query, col.key)
         |> put_flash(:info, "Opened Zotero folder “#{col.path}”.")}

      {:error, :blank_name} ->
        {:noreply, assign(socket, :zotero_error, "Enter a folder name.")}

      {:error, _} ->
        {:noreply, assign(socket, :zotero_error, "Could not create that folder in Zotero.")}
    end
  end

  def handle_event("zotero_create_item", params, socket) do
    target_col =
      socket.assigns.zotero_selected_collection ||
        case Zotero.find_root_collection(socket.assigns.zotero_collections) do
          %{key: k} -> k
          nil -> nil
        end

    case Zotero.create_item(params, target_col) do
      {:ok, item} ->
        updated = Outline.insert_reading_items(socket.assigns.content, [item])
        cols = refresh_zotero_collections()

        {:noreply,
         socket
         |> assign(zotero_collections: cols, zotero_error: nil)
         |> DocumentEditor.set("post-source", updated)
         |> put_content(updated)
         |> load_zotero_items(socket.assigns.zotero_query, target_col)
         |> put_flash(:info, "Added “#{item.title}” to Zotero and the reading list.")}

      {:error, :blank_title} ->
        {:noreply, assign(socket, :zotero_error, "Document title is required.")}

      {:error, _} ->
        {:noreply, assign(socket, :zotero_error, "Could not add that document to Zotero.")}
    end
  end

  def handle_event("zotero_push_reading_list", _params, socket) do
    target_col =
      socket.assigns.zotero_selected_collection ||
        case Zotero.find_root_collection(socket.assigns.zotero_collections) do
          %{key: k} -> k
          nil -> nil
        end

    if is_nil(target_col) do
      {:noreply, assign(socket, :zotero_error, "Select or create a Zotero folder first.")}
    else
      items = socket.assigns.post.outline.research.items

      case Zotero.sync_reading_list(items, target_col) do
        {:ok, %{created: created, skipped: skipped}} ->
          cols = refresh_zotero_collections()

          msg =
            "Pushed #{length(created)} reading list #{if length(created) == 1, do: "item", else: "items"} to Zotero" <>
              if(skipped > 0, do: " (#{skipped} already in folder).", else: ".")

          {:noreply,
           socket
           |> assign(zotero_collections: cols, zotero_error: nil)
           |> load_zotero_items(socket.assigns.zotero_query, target_col)
           |> put_flash(:info, msg)}

        {:error, _} ->
          {:noreply, assign(socket, :zotero_error, "Could not push the reading list to Zotero.")}
      end
    end
  end

  def handle_event("zotero_import_item", %{"key" => key}, socket) do
    case Zotero.fetch_item_with_notes(key) do
      {:ok, item} ->
        updated = Outline.insert_reading_items(socket.assigns.content, [item])

        {:noreply,
         socket
         |> DocumentEditor.set("post-source", updated)
         |> put_content(updated)
         |> put_flash(:info, "Added “#{item.title}” to the reading list.")}

      {:error, _} ->
        {:noreply, assign(socket, :zotero_error, "Could not fetch that item from Zotero.")}
    end
  end

  def handle_event("zotero_import_collection", %{"key" => key}, socket) do
    case Zotero.fetch_collection_with_notes(key) do
      {:ok, items} ->
        updated = Outline.insert_reading_items(socket.assigns.content, items)

        {:noreply,
         socket
         |> DocumentEditor.set("post-source", updated)
         |> put_content(updated)
         |> put_flash(:info, "Imported #{length(items)} Zotero items into the reading list.")}

      {:error, _} ->
        {:noreply, assign(socket, :zotero_error, "Could not fetch that collection from Zotero.")}
    end
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
    socket =
      if content == typed, do: socket, else: DocumentEditor.set(socket, "post-source", content)

    {:noreply, socket |> put_content(content) |> save([])}
  end

  def handle_event("take_disk", _params, socket) do
    %{content: content, revision: revision} = socket.assigns.conflict

    {:noreply,
     socket
     |> assign(revision: revision, saved: content, conflict: nil)
     |> put_content(content)
     |> DocumentEditor.set("post-source", content)
     |> put_flash(:info, "Loaded the file as it is on disk.")}
  end

  def handle_event("save_over", _params, socket) do
    {:noreply, save(socket, force: true)}
  end

  def handle_event("keep_editing", _params, socket) do
    {:noreply, assign(socket, :conflict, nil)}
  end

  defp save(socket, opts) do
    %{slug: slug, content: content, revision: revision} = socket.assigns

    case Blog.write_source(slug, content, revision, opts) do
      {:ok, revision} ->
        message =
          if opts[:force],
            do: "Saved. The version it replaced is in the vault's .trash folder.",
            else: "Saved #{slug}.md."

        socket
        |> assign(revision: revision, saved: content, conflict: nil)
        |> put_flash(:info, message)

      {:error, :conflict, on_disk} ->
        socket
        |> assign(:conflict, on_disk)
        |> put_flash(:error, "Not saved: #{slug}.md changed on disk since you opened it.")

      _ ->
        put_flash(socket, :error, "Could not write #{slug}.md.")
    end
  end

  defp put_content(socket, content) do
    post = Blog.preview(socket.assigns.slug, content)
    show_beats = Map.get(socket.assigns, :show_beats, false)
    assign(socket, content: content, post: post, html: preview_html(post, show_beats))
  end

  defp preview_html(post, true), do: Outline.render_with_beats(post.raw_body)
  defp preview_html(post, false), do: Blog.to_html(post.body)

  defp refresh_zotero_collections do
    case Zotero.list_collections() do
      {:ok, list} -> list
      _ -> []
    end
  end

  defp default_selected_collection(collections, slug, title) do
    slug_down = String.downcase(to_string(slug))
    title_down = String.downcase(to_string(title))

    matching_sub =
      Enum.find(collections, fn c ->
        c.in_root? and not c.is_root? and
          (String.downcase(c.name) == slug_down or String.downcase(c.name) == title_down)
      end)

    cond do
      matching_sub != nil ->
        matching_sub.key

      root = Enum.find(collections, & &1.is_root?) ->
        root.key

      true ->
        nil
    end
  end

  defp load_zotero(socket, q) do
    collections =
      if socket.assigns.zotero_collections == [] do
        refresh_zotero_collections()
      else
        socket.assigns.zotero_collections
      end

    selected =
      socket.assigns.zotero_selected_collection ||
        default_selected_collection(collections, socket.assigns.slug, socket.assigns.post.title)

    socket
    |> assign(
      zotero_collections: collections,
      zotero_selected_collection: selected
    )
    |> load_zotero_items(q, selected)
  end

  defp load_zotero_items(socket, q, selected_collection) do
    case Zotero.search_items(q: q, collection: selected_collection) do
      {:ok, items} ->
        assign(socket,
          zotero_items: items,
          zotero_query: q,
          zotero_error: nil
        )

      {:error, :auth_failed} ->
        assign(socket,
          zotero_error: "Zotero rejected ZOTERO_USER_ID or ZOTERO_API_KEY."
        )

      {:error, _} ->
        assign(socket,
          zotero_error: "Could not reach api.zotero.org."
        )
    end
  end

  defp lf(text), do: String.replace(text, "\r\n", "\n")

  def render(assigns) do
    # A browser sends \n where the file may have \r\n (Web.SourceFile puts
    # them back on save), so line endings alone are not unsaved work.
    assigns =
      assigns
      |> assign(:dirty, lf(assigns.content) != lf(assigns.saved))
      |> assign(
        :active_zotero_col,
        Enum.find(assigns.zotero_collections, &(&1.key == assigns.zotero_selected_collection))
      )

    ~H"""
    <.page_head slug="Writing / Blog / Edit" title={@post.title}>
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

    <section :if={@conflict} id="post-conflict" class="adm-conflict" role="alert">
      <h2 class="adm-conflict-title">This file changed on disk while you had it open</h2>
      <p>
        Someone, most likely you in Obsidian, saved <code>{@slug}.md</code>
        after this page loaded it. Nothing has been written. Your text is still in the editor.
      </p>
      <div class="adm-form-actions">
        <button type="button" phx-click="take_disk" class="adm-btn">
          Take the version on disk
        </button>
        <button
          type="button"
          phx-click="save_over"
          class="adm-btn adm-btn--danger"
          data-confirm="Save your text over the version on disk? That version is moved to the vault's .trash folder first."
        >
          Save mine over it
        </button>
        <button type="button" phx-click="keep_editing" class="adm-btn adm-btn--quiet">
          Keep editing
        </button>
      </div>
      <details class="adm-conflict-disk">
        <summary>What is on disk now</summary>
        <pre>{@conflict.content}</pre>
      </details>
    </section>

    <section :if={@zotero_open} id="post-zotero" class="adm-zotero" aria-label="Zotero reading list">
      <div class="adm-zotero-head">
        <div class="adm-zotero-head-left">
          <h2 class="adm-zotero-title">
            Zotero ·
            <span>{if @active_zotero_col, do: @active_zotero_col.path, else: "All library"}</span>
          </h2>
        </div>
        <div class="adm-zotero-head-actions">
          <button
            :if={@active_zotero_col}
            type="button"
            id="zotero-import-folder"
            phx-click="zotero_import_collection"
            phx-value-key={@active_zotero_col.key}
            class="adm-btn adm-btn--small adm-btn--quiet"
          >
            Pull folder into reading list (<span class="adm-figure">{@active_zotero_col.item_count}</span>)
          </button>
          <button
            :if={@active_zotero_col && @post.outline.research.total > 0}
            type="button"
            id="zotero-push-reading-list"
            phx-click="zotero_push_reading_list"
            class="adm-btn adm-btn--small"
          >
            Push reading list to folder (<span class="adm-figure">{@post.outline.research.total}</span>)
          </button>
          <button
            type="button"
            phx-click="zotero_toggle"
            class="adm-btn adm-btn--small adm-btn--quiet"
          >
            Close
          </button>
        </div>
      </div>

      <p :if={!@zotero_configured} class="adm-help">
        Set <code>ZOTERO_USER_ID</code>
        and <code>ZOTERO_API_KEY</code>
        in <code>.env</code>
        to connect your <code>{@zotero_root_target}</code>
        folder in Zotero.
      </p>

      <div :if={@zotero_configured} class="adm-zotero-body">
        <p :if={@zotero_error} class="adm-zotero-error" role="alert">{@zotero_error}</p>

        <div :if={@zotero_collections != []} class="adm-zotero-collections">
          <span class="adm-zotero-label">Folders:</span>
          <button
            type="button"
            phx-click="zotero_select_collection"
            phx-value-key=""
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
          <form id="zotero-search-form" phx-submit="zotero_search" class="adm-inline-form">
            <input
              type="search"
              name="q"
              value={@zotero_query}
              class="adm-input"
              placeholder="Search folder by author, title, year or note…"
              aria-label="Search Zotero library"
            />
            <button type="submit" class="adm-btn adm-btn--small">Search</button>
          </form>

          <form id="zotero-folder-form" phx-submit="zotero_create_folder" class="adm-inline-form">
            <input
              type="text"
              name="name"
              value=""
              class="adm-input"
              placeholder={"New subfolder in #{if @active_zotero_col, do: @active_zotero_col.name, else: @zotero_root_target}…"}
              aria-label="New Zotero subfolder name"
            />
            <button type="submit" class="adm-btn adm-btn--small adm-btn--quiet">
              + New folder
            </button>
            <button
              type="button"
              id="zotero-folder-for-post"
              phx-click="zotero_create_folder"
              phx-value-name={@slug}
              class="adm-btn adm-btn--small adm-btn--quiet"
              title={"Create or open #{@zotero_root_target} / #{@slug}"}
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
          <form id="zotero-item-form" phx-submit="zotero_create_item" class="adm-zotero-doc-form">
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
              <label class="adm-field">
                <span>Title</span>
                <input
                  type="text"
                  name="title"
                  required
                  class="adm-input"
                  placeholder="The Future of Nostalgia"
                />
              </label>
              <label class="adm-field">
                <span>Author(s)</span>
                <input
                  type="text"
                  name="authors"
                  class="adm-input"
                  placeholder="Boym, Svetlana"
                />
              </label>
              <label class="adm-field">
                <span>Publisher / Journal</span>
                <input
                  type="text"
                  name="publication"
                  class="adm-input"
                  placeholder="Basic Books"
                />
              </label>
              <label class="adm-field">
                <span>Year</span>
                <input type="text" name="year" class="adm-input" placeholder="2001" />
              </label>
              <label class="adm-field">
                <span>Call number</span>
                <input
                  type="text"
                  name="call_number"
                  class="adm-input"
                  placeholder="PN56.N6 B69 2001"
                />
              </label>
              <label class="adm-field">
                <span>URL / DOI</span>
                <input
                  type="url"
                  name="url"
                  class="adm-input"
                  placeholder="https://..."
                />
              </label>
              <label class="adm-field">
                <span>Your note / phrasing</span>
                <input
                  type="text"
                  name="note"
                  class="adm-input"
                  placeholder="What you thought about this source…"
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
          <li :for={item <- @zotero_items} id={"zotero-item-#{item.key}"} class="adm-zotero-item">
            <div class="adm-zotero-item-main">
              <strong class="adm-zotero-item-title">{item.title}</strong>
              <span class="adm-zotero-item-meta">
                {item.authors}{if item.year, do: " (#{item.year})"}
                <span :if={item.call_number} class="adm-figure"> · {item.call_number}</span>
              </span>
            </div>
            <button
              type="button"
              phx-click="zotero_import_item"
              phx-value-key={item.key}
              class="adm-btn adm-btn--small"
            >
              Add to reading list
            </button>
          </li>
        </ul>
      </div>
    </section>

    <form
      id="post-editor"
      class="adm-editor adm-editor--post"
      phx-change="change"
      phx-submit="save"
      data-dirty={to_string(@dirty)}
    >
      <div class="adm-editor-body">
        <p class="adm-editor-bar">
          <span>Source</span>
          <.pill :if={@dirty} tone="held">unsaved</.pill>
          <.pill :if={!@dirty} tone="quiet">saved</.pill>
        </p>
        <.document_editor
          id="post-source"
          name="content"
          value={@content}
          complete="blog"
          media
          debounce="300"
          label={"Source of #{@slug}.md"}
        />
      </div>

      <div class="adm-editor-body" id="post-preview">
        <p class="adm-editor-bar">
          <span>As the site reads it</span>
          <span class="adm-editor-bar-right">
            <button
              type="button"
              id="toggle-zotero"
              phx-click="zotero_toggle"
              aria-pressed={to_string(@zotero_open)}
              class="adm-btn adm-btn--small adm-btn--quiet"
            >
              Zotero
            </button>
            <button
              :if={@post.outline.has_outline?}
              type="button"
              id="toggle-beats"
              phx-click="toggle_beats"
              aria-pressed={to_string(@show_beats)}
              class="adm-btn adm-btn--small adm-btn--quiet"
            >
              {if @show_beats, do: "Prose only", else: "Show beats"}
            </button>
            <.pill :if={@post.draft} tone="draft">draft</.pill>
            <.pill :if={!@post.draft} tone="live">published</.pill>
          </span>
        </p>
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
              <.pill :if={!@post.described} tone="held">none: the first paragraph stands in</.pill>
            </dd>
          </div>
        </dl>

        <section
          :if={@post.outline.has_outline?}
          id="post-outline-progress"
          class="adm-outline-strip"
          aria-label="Outline progress"
        >
          <div class="adm-outline-head">
            <span class="adm-outline-label">Outline</span>
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
          </div>

          <details :if={@post.outline.research.total > 0} class="adm-outline-sections">
            <summary>
              Reading list ({@post.outline.research.checked}/{@post.outline.research.total} read, {@post.outline.research.with_thoughts} with thoughts)
            </summary>
            <ul class="adm-outline-list adm-reading-list">
              <li
                :for={item <- @post.outline.research.items}
                class={["adm-reading-item", item.done? && "is-done"]}
              >
                <div class="adm-reading-row">
                  <.pill tone={if(item.done?, do: "live", else: "quiet")}>
                    {if item.done?, do: "read", else: "to read"}
                  </.pill>
                  <span class="adm-reading-source">{Web.Markdown.to_text(item.text)}</span>
                </div>
                <p :for={thought <- item.thoughts} class="adm-reading-thought">
                  “{thought}”
                </p>
              </li>
            </ul>
          </details>

          <details :if={@post.outline.sections != []} class="adm-outline-sections" open={@post.draft}>
            <summary>Sections and beats ({length(@post.outline.sections)})</summary>
            <ol class="adm-outline-list">
              <li :for={section <- @post.outline.sections} class="adm-outline-section">
                <div class="adm-outline-section-row">
                  <span class="adm-outline-section-title">{section.title}</span>
                  <span class="adm-figure adm-outline-section-words">
                    {section.drafted_words}{if section.target_words,
                      do: " / #{section.target_words}"}w
                  </span>
                </div>
                <ul :if={section.beats != []} class="adm-outline-beats">
                  <li
                    :for={beat <- section.beats}
                    class={["adm-outline-beat", beat.drafted? && "is-done"]}
                  >
                    <.pill tone={if(beat.drafted?, do: "live", else: "quiet")}>
                      {if beat.drafted?, do: "✓ #{beat.title}", else: beat.title}
                    </.pill>
                    <button
                      :if={beat.thoughts != [] and not beat.drafted?}
                      type="button"
                      phx-click="seed_beat"
                      phx-value-beat={beat.title}
                      class="adm-btn adm-btn--small adm-btn--quiet adm-seed-btn"
                      title="Drop this beat's thoughts beneath the beat as draft text"
                    >
                      Use my phrasings ({length(beat.thoughts)})
                    </button>
                  </li>
                </ul>
              </li>
            </ol>
          </details>
        </section>

        <div class="adm-prose">{raw(@html)}</div>
      </div>
    </form>
    """
  end
end
