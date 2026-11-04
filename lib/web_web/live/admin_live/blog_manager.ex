defmodule WebWeb.AdminLive.BlogManager do
  use WebWeb, :live_view

  alias Web.Blog
  alias Web.Blog.Images
  alias Web.Blog.Outline
  alias Web.Zotero
  import WebWeb.AdminComponents

  @moduledoc """
  Admin for the blog (`Writing / Blog`):

    * **Four-Panel Essay Pipeline Workbench** (`1. Articles & Zotero`,
      `2. Outline & Phrasings`, `3. Draft`, `4. Preview`) at the top of
      `/admin/blog`, loaded automatically with the active outlined essay draft.
    * **New post / blueprint importer**, batch `.md` drop, the **Posts**
      archive, and the **Image library** below.
  """

  def mount(_params, _session, socket) do
    configured? = Zotero.configured?()

    socket =
      socket
      |> assign(:page_title, "Blog | Admin")
      |> assign(:uploaded, [])
      |> assign(:keyword_edit, nil)
      |> assign(:filter, "all")
      |> assign(:wb_slug, nil)
      |> assign(:wb_content, "")
      |> assign(:wb_saved, "")
      |> assign(:wb_revision, nil)
      |> assign(:wb_post, nil)
      |> assign(:wb_html, "")
      |> assign(:wb_show_beats, false)
      |> assign(:zotero_configured, configured?)
      |> assign(:zotero_root_target, Zotero.root_collection_target())
      |> assign(:zotero_collections, [])
      |> assign(:zotero_selected_collection, nil)
      |> assign(:zotero_items, [])
      |> assign(:zotero_query, "")
      |> assign(:zotero_error, nil)
      |> load_posts()
      |> then(fn s ->
        if configured?, do: load_zotero(s, ""), else: s
      end)
      |> assign(:images, Images.list())
      |> allow_upload(:markdown,
        accept: ~w(.md),
        max_entries: 10,
        max_file_size: 20_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )
      |> allow_upload(:image,
        accept: Images.extensions(),
        max_entries: 10,
        max_file_size: 50_000_000,
        auto_upload: true,
        progress: &handle_progress/3
      )

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    filter = if params["filter"] in ~w(missing drafts), do: params["filter"], else: "all"
    {:noreply, assign(socket, :filter, filter)}
  end

  # ── Workbench events (Articles/Zotero, Outline, Draft, Preview) ───────

  def handle_event("wb_select_post", %{"slug" => slug}, socket) do
    {:noreply,
     socket
     |> load_workbench(slug)
     |> then(fn s ->
       if s.assigns.zotero_configured do
         selected =
           default_selected_collection(
             s.assigns.zotero_collections,
             slug,
             s.assigns.wb_post && s.assigns.wb_post.title
           )

         s
         |> assign(:zotero_selected_collection, selected)
         |> load_zotero_items(s.assigns.zotero_query, selected)
       else
         s
       end
     end)}
  end

  def handle_event("wb_change", %{"content" => content}, socket) do
    {:noreply, put_wb_content(socket, content)}
  end

  def handle_event("wb_save", %{"content" => typed} = params, socket) do
    content =
      case params["then"] do
        "publish" -> Blog.mark_draft(typed, false)
        "unpublish" -> Blog.mark_draft(typed, true)
        _ -> typed
      end

    {:noreply, socket |> put_wb_content(content) |> save_wb()}
  end

  def handle_event("wb_toggle_beats", _params, socket) do
    show = not socket.assigns.wb_show_beats
    html = wb_preview_html(socket.assigns.wb_post, show)
    {:noreply, assign(socket, wb_show_beats: show, wb_html: html)}
  end

  def handle_event("wb_seed_beat", %{"beat" => beat_title}, socket) do
    updated = Outline.seed_beat_thoughts(socket.assigns.wb_content, beat_title)
    {:noreply, socket |> put_wb_content(updated) |> save_wb()}
  end

  def handle_event("wb_add_beat_thought", %{"beat" => beat_title, "thought" => thought}, socket) do
    updated = Outline.add_beat_thought(socket.assigns.wb_content, beat_title, thought)
    {:noreply, socket |> put_wb_content(updated) |> save_wb()}
  end

  def handle_event("wb_add_reading_thought", %{"index" => idx_str, "thought" => thought}, socket) do
    case Integer.parse(to_string(idx_str)) do
      {idx, ""} ->
        updated = Outline.add_reading_thought(socket.assigns.wb_content, idx, thought)
        {:noreply, socket |> put_wb_content(updated) |> save_wb()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("wb_toggle_reading_item", %{"index" => idx_str}, socket) do
    case Integer.parse(to_string(idx_str)) do
      {idx, ""} ->
        updated = Outline.toggle_reading_item(socket.assigns.wb_content, idx)
        {:noreply, socket |> put_wb_content(updated) |> save_wb()}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("zotero_refresh", _params, socket) do
    configured? = Zotero.configured?()

    socket =
      socket
      |> assign(
        zotero_configured: configured?,
        zotero_root_target: Zotero.root_collection_target(),
        zotero_error: nil
      )
      |> then(fn s ->
        if configured?, do: load_zotero(s, s.assigns.zotero_query), else: s
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
        cols = refresh_zotero_collections()

        socket =
          if socket.assigns.wb_slug do
            updated = Outline.insert_reading_items(socket.assigns.wb_content, [item])
            socket |> put_wb_content(updated) |> save_wb()
          else
            socket
          end

        {:noreply,
         socket
         |> assign(zotero_collections: cols, zotero_error: nil)
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

    if is_nil(target_col) or is_nil(socket.assigns.wb_post) do
      {:noreply, assign(socket, :zotero_error, "Select or create a Zotero folder first.")}
    else
      items = socket.assigns.wb_post.outline.research.items

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
    if is_nil(socket.assigns.wb_slug) do
      {:noreply, assign(socket, :zotero_error, "Start or select a draft first.")}
    else
      case Zotero.fetch_item_with_notes(key) do
        {:ok, item} ->
          updated = Outline.insert_reading_items(socket.assigns.wb_content, [item])

          {:noreply,
           socket
           |> put_wb_content(updated)
           |> save_wb()
           |> put_flash(:info, "Added “#{item.title}” to the reading list.")}

        {:error, _} ->
          {:noreply, assign(socket, :zotero_error, "Could not fetch that item from Zotero.")}
      end
    end
  end

  def handle_event("zotero_import_collection", %{"key" => key}, socket) do
    if is_nil(socket.assigns.wb_slug) do
      {:noreply, assign(socket, :zotero_error, "Start or select a draft first.")}
    else
      case Zotero.fetch_collection_with_notes(key) do
        {:ok, items} ->
          updated = Outline.insert_reading_items(socket.assigns.wb_content, items)

          {:noreply,
           socket
           |> put_wb_content(updated)
           |> save_wb()
           |> put_flash(:info, "Imported #{length(items)} Zotero items into the reading list.")}

        {:error, _} ->
          {:noreply,
           assign(socket, :zotero_error, "Could not fetch that collection from Zotero.")}
      end
    end
  end

  # ── Standard blog manager events ──────────────────────────────────────

  def handle_event("new_post", %{"title" => title}, socket) do
    case Blog.create_draft(title) do
      {:ok, slug} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/blog/#{slug}/edit")}

      {:error, :exists} ->
        {:noreply,
         put_flash(socket, :error, "There is already a #{Web.Keywords.slugify(title)}.md.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "A post needs a title to be filed under.")}
    end
  end

  def handle_event("new_from_outline", %{"blueprint" => blueprint}, socket) do
    case Blog.create_from_blueprint(blueprint) do
      {:ok, slug} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/blog/#{slug}/edit")}

      {:error, :exists} ->
        {:noreply,
         put_flash(socket, :error, "A post with that outline's title is already in the blog.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Paste a markdown outline with a title to start.")}
    end
  end

  def handle_event("set_draft", %{"slug" => slug, "draft" => draft}, socket) do
    draft? = draft == "true"

    case Blog.set_draft(slug, draft?) do
      :ok ->
        message =
          if draft?,
            do: "#{slug}.md is a draft again, and off the site.",
            else: "Published /blog/#{slug}."

        {:noreply, socket |> load_posts() |> put_flash(:info, message)}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not write to #{slug}.md.")}
    end
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("edit_keywords", %{"slug" => slug}, socket) do
    {:noreply, assign(socket, :keyword_edit, slug)}
  end

  def handle_event("cancel_keywords", _params, socket) do
    {:noreply, assign(socket, :keyword_edit, nil)}
  end

  def handle_event("save_keywords", %{"slug" => slug, "keywords" => keywords}, socket) do
    case Blog.set_keywords(slug, keywords) do
      :ok ->
        {:noreply,
         socket
         |> assign(:keyword_edit, nil)
         |> load_posts()
         |> put_flash(:info, "Keywords written into #{slug}.md.")}

      _ ->
        {:noreply, put_flash(socket, :error, "Could not write to #{slug}.md.")}
    end
  end

  def handle_event("delete_post", %{"slug" => slug}, socket) do
    Blog.delete_post(slug)
    {:noreply, socket |> load_posts() |> put_flash(:info, "Deleted #{slug}.md.")}
  end

  def handle_event("delete_image", %{"name" => name}, socket) do
    Images.delete(name)
    {:noreply, socket |> assign(:images, Images.list()) |> put_flash(:info, "Image deleted.")}
  end

  defp handle_progress(:markdown, entry, socket) do
    if entry.done? do
      results =
        consume_uploaded_entries(socket, :markdown, fn %{path: path}, meta ->
          slug = meta.client_name |> Path.basename(".md") |> Web.Keywords.slugify()
          Blog.create_post(slug, File.read!(path))
          {:ok, {:post, slug}}
        end)

      {:noreply, socket |> load_posts() |> assign(:uploaded, results ++ socket.assigns.uploaded)}
    else
      {:noreply, socket}
    end
  end

  defp handle_progress(:image, entry, socket) do
    if entry.done? do
      results =
        consume_uploaded_entries(socket, :image, fn %{path: path}, meta ->
          {:ok, {:image, Images.store(path, meta.client_name)}}
        end)

      {:noreply,
       socket
       |> assign(:images, Images.list())
       |> assign(:uploaded, results ++ socket.assigns.uploaded)}
    else
      {:noreply, socket}
    end
  end

  defp load_posts(socket) do
    posts = Blog.list_all_posts()
    current_wb = socket.assigns[:wb_slug]

    chosen_slug =
      cond do
        is_binary(current_wb) and Enum.any?(posts, &(&1.slug == current_wb)) ->
          current_wb

        outlined = Enum.find(posts, &(&1.draft and &1.outline.has_outline?)) ->
          outlined.slug

        any_outlined = Enum.find(posts, & &1.outline.has_outline?) ->
          any_outlined.slug

        draft = Enum.find(posts, & &1.draft) ->
          draft.slug

        first = List.first(posts) ->
          first.slug

        true ->
          nil
      end

    socket
    |> assign(:posts, posts)
    |> assign(:readers, Web.Analytics.post_readers())
    |> load_workbench(chosen_slug)
  end

  defp load_workbench(socket, nil) do
    assign(socket,
      wb_slug: nil,
      wb_content: "",
      wb_saved: "",
      wb_revision: nil,
      wb_post: nil,
      wb_html: ""
    )
  end

  defp load_workbench(socket, slug) when is_binary(slug) do
    case Blog.read_source(slug) do
      {:ok, %{content: content, revision: revision}} ->
        socket
        |> assign(wb_slug: slug, wb_saved: content, wb_revision: revision)
        |> put_wb_content(content)

      _ ->
        load_workbench(socket, nil)
    end
  end

  defp put_wb_content(socket, content) do
    case socket.assigns.wb_slug do
      nil ->
        socket

      slug ->
        post = Blog.preview(slug, content)
        show_beats = Map.get(socket.assigns, :wb_show_beats, false)

        assign(socket,
          wb_content: content,
          wb_post: post,
          wb_html: wb_preview_html(post, show_beats)
        )
    end
  end

  defp wb_preview_html(nil, _show_beats), do: ""
  defp wb_preview_html(post, true), do: Outline.render_with_beats(post.raw_body)
  defp wb_preview_html(post, false), do: Blog.to_html(post.body)

  defp save_wb(socket) do
    %{wb_slug: slug, wb_content: content, wb_revision: revision} = socket.assigns

    if is_binary(slug) and is_binary(revision) do
      case Blog.write_source(slug, content, revision, force: true) do
        {:ok, new_rev} ->
          socket
          |> assign(wb_revision: new_rev, wb_saved: content)
          |> assign(:posts, Blog.list_all_posts())
          |> put_flash(:info, "Saved #{slug}.md.")

        _ ->
          put_flash(socket, :error, "Could not write #{slug}.md.")
      end
    else
      socket
    end
  end

  defp refresh_zotero_collections do
    case Zotero.list_collections() do
      {:ok, list} -> list
      _ -> []
    end
  end

  defp default_selected_collection(collections, slug, title) do
    slug_down = String.downcase(to_string(slug || ""))
    title_down = String.downcase(to_string(title || ""))

    matching_sub =
      Enum.find(collections, fn c ->
        c.in_root? and not c.is_root? and slug_down != "" and
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
        default_selected_collection(
          collections,
          socket.assigns.wb_slug,
          socket.assigns.wb_post && socket.assigns.wb_post.title
        )

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

  defp upload_error_message(:too_large), do: "File is too large."
  defp upload_error_message(:not_accepted), do: "That file type is not accepted."
  defp upload_error_message(:too_many_files), do: "Too many files at once."
  defp upload_error_message(error), do: to_string(error)

  defp lf(text), do: String.replace(text || "", "\r\n", "\n")

  # A draft without keywords is not missing them yet: the filters it cannot
  # be reached through do not list it either.
  defp shown(posts, "missing"), do: Enum.filter(posts, &(&1.keywords == [] and not &1.draft))
  defp shown(posts, "drafts"), do: Enum.filter(posts, & &1.draft)
  defp shown(posts, _all), do: posts

  def render(assigns) do
    assigns =
      assigns
      |> assign(:shown, shown(assigns.posts, assigns.filter))
      |> assign(:missing_count, length(shown(assigns.posts, "missing")))
      |> assign(:draft_count, length(shown(assigns.posts, "drafts")))
      |> assign(:wb_dirty, lf(assigns.wb_content) != lf(assigns.wb_saved))
      |> assign(
        :active_zotero_col,
        Enum.find(assigns.zotero_collections, &(&1.key == assigns.zotero_selected_collection))
      )

    ~H"""
    <.page_head slug="Writing / Blog" title="Blog">
      <:lede>
        Typed work, as markdown files in the vault; this page writes the same files. Spoken pieces
        live in <.link navigate={~p"/admin/logs"} class="adm-link">Videostream</.link>.
      </:lede>
      <:actions>
        <.link
          :if={@wb_slug}
          navigate={~p"/admin/blog/#{@wb_slug}/edit"}
          class="adm-btn adm-btn--primary"
        >
          Open {@wb_slug}.md in full editor
        </.link>
        <.link href={~p"/blog"} target="_blank" class="adm-btn adm-btn--quiet">
          <.icon name="hero-arrow-top-right-on-square" class="size-4" /> View the blog
        </.link>
      </:actions>
    </.page_head>

    <div :if={@posts != []} id="wb-selector" class="adm-wb-bar">
      <div class="adm-wb-bar-left">
        <span class="adm-outline-label">Active essay in pipeline:</span>
        <button
          :for={p <- Enum.take(@posts, 8)}
          type="button"
          id={"wb-pick-#{p.slug}"}
          phx-click="wb_select_post"
          phx-value-slug={p.slug}
          class={[
            "adm-btn adm-btn--small adm-btn--quiet",
            @wb_slug == p.slug && "is-active"
          ]}
        >
          {p.title}
          <span :if={p.outline.has_outline?} class="adm-figure">
            ({p.outline.beats_done}/{p.outline.beats_total})
          </span>
        </button>
      </div>
    </div>

    <div :if={@wb_post} id="pipeline-panels" class="adm-pipeline-grid">
      <.panel
        title="1. Articles & Zotero"
        id="panel-articles"
        count={@wb_post.outline.research.total}
      >
        <:actions>
          <button
            type="button"
            phx-click="zotero_refresh"
            class="adm-btn adm-btn--small adm-btn--quiet"
          >
            Sync Zotero
          </button>
          <button
            :if={@active_zotero_col}
            type="button"
            phx-click="zotero_import_collection"
            phx-value-key={@active_zotero_col.key}
            class="adm-btn adm-btn--small adm-btn--quiet"
          >
            Pull folder (<span class="adm-figure">{@active_zotero_col.item_count}</span>)
          </button>
          <button
            :if={@active_zotero_col && @wb_post.outline.research.total > 0}
            type="button"
            phx-click="zotero_push_reading_list"
            class="adm-btn adm-btn--small"
          >
            Push reading list (<span class="adm-figure">{@wb_post.outline.research.total}</span>)
          </button>
        </:actions>

        <div class="adm-zotero-body">
          <div :if={@wb_post.outline.research.total > 0} class="adm-reading-block">
            <div class="adm-outline-head">
              <span class="adm-outline-label">
                Top Reading List (<span class="adm-figure">{@wb_post.outline.research.checked}/{@wb_post.outline.research.total}</span>
                read · <span class="adm-figure">{@wb_post.outline.research.with_thoughts}</span>
                with thoughts)
              </span>
            </div>
            <ul class="adm-outline-list adm-reading-list">
              <li
                :for={{item, idx} <- Enum.with_index(@wb_post.outline.research.items)}
                class={["adm-reading-item", item.done? && "is-done"]}
              >
                <div class="adm-reading-row">
                  <button
                    type="button"
                    phx-click="wb_toggle_reading_item"
                    phx-value-index={idx}
                    class="adm-btn adm-btn--small adm-btn--quiet adm-reading-toggle"
                  >
                    <.pill tone={if(item.done?, do: "live", else: "quiet")}>
                      {if item.done?, do: "✓ read", else: "to read"}
                    </.pill>
                  </button>
                  <span class="adm-reading-source">{Web.Markdown.to_text(item.text)}</span>
                </div>
                <p :for={thought <- item.thoughts} class="adm-reading-thought">
                  “{thought}”
                </p>
                <form
                  phx-submit="wb_add_reading_thought"
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

          <div :if={@zotero_configured} class="adm-zotero-subpanel">
            <p :if={@zotero_error} class="adm-zotero-error" role="alert">{@zotero_error}</p>

            <div :if={@zotero_collections != []} class="adm-zotero-collections">
              <span class="adm-zotero-label">Zotero folders:</span>
              <button
                type="button"
                phx-click="zotero_select_collection"
                phx-value-key=""
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
                phx-click="zotero_select_collection"
                phx-value-key={col.key}
                class={[
                  "adm-btn adm-btn--small adm-btn--quiet",
                  @zotero_selected_collection == col.key && "is-active"
                ]}
              >
                {col.path} (<span class="adm-figure">{col.item_count}</span>)
              </button>
            </div>

            <div class="adm-zotero-bars">
              <form phx-submit="zotero_search" class="adm-inline-form">
                <input
                  type="search"
                  name="q"
                  value={@zotero_query}
                  class="adm-input"
                  placeholder="Search Zotero folder…"
                  aria-label="Search Zotero library"
                />
                <button type="submit" class="adm-btn adm-btn--small">Search</button>
              </form>

              <form phx-submit="zotero_create_folder" class="adm-inline-form">
                <input
                  type="text"
                  name="name"
                  value=""
                  class="adm-input"
                  placeholder={"New subfolder in #{@zotero_root_target}…"}
                  aria-label="New Zotero subfolder name"
                />
                <button type="submit" class="adm-btn adm-btn--small adm-btn--quiet">
                  + New folder
                </button>
              </form>
            </div>

            <details class="adm-outline-sections">
              <summary>
                + Add a document to {if @active_zotero_col,
                  do: @active_zotero_col.path,
                  else: @zotero_root_target} &amp; reading list
              </summary>
              <form phx-submit="zotero_create_item" class="adm-zotero-doc-form">
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
              <li :for={item <- @zotero_items} class="adm-zotero-item">
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
        </div>
      </.panel>

      <.panel
        title="2. Outline & Phrasings"
        id="panel-outline"
        count={@wb_post.outline.beats_total}
      >
        <:actions>
          <div class="adm-outline-pills">
            <.pill
              :if={@wb_post.outline.beats_total > 0}
              tone={
                if(@wb_post.outline.beats_done == @wb_post.outline.beats_total,
                  do: "live",
                  else: "draft"
                )
              }
            >
              <span class="adm-figure">
                {@wb_post.outline.beats_done}/{@wb_post.outline.beats_total}
              </span>
              beats
            </.pill>
            <.pill
              :if={@wb_post.outline.target_words}
              tone="quiet"
            >
              <span class="adm-figure">
                {@wb_post.word_count} / {@wb_post.outline.target_words}
              </span>
              words
            </.pill>
          </div>
        </:actions>

        <ol :if={@wb_post.outline.sections != []} class="adm-outline-list">
          <li :for={section <- @wb_post.outline.sections} class="adm-outline-section">
            <div class="adm-outline-section-row">
              <span class="adm-outline-section-title">{section.title}</span>
              <span class="adm-figure adm-outline-section-words">
                {section.drafted_words}{if section.target_words,
                  do: " / #{section.target_words}"}w
              </span>
            </div>
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
                    phx-click="wb_seed_beat"
                    phx-value-beat={beat.title}
                    class="adm-btn adm-btn--small adm-btn--quiet adm-seed-btn"
                  >
                    Use my phrasings ({length(beat.thoughts)})
                  </button>
                </div>
                <p :if={beat.prompt != ""} class="adm-outline-beat-prompt">
                  {Web.Markdown.to_text(beat.prompt)}
                </p>
                <p :for={thought <- beat.thoughts} class="adm-reading-thought">
                  “{thought}”
                </p>
                <form phx-submit="wb_add_beat_thought" class="adm-inline-form adm-thought-form">
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
      </.panel>

      <.panel title="3. Draft" id="panel-draft">
        <:actions>
          <.pill :if={@wb_dirty} tone="held">unsaved</.pill>
          <.pill :if={!@wb_dirty} tone="quiet">saved</.pill>
          <.link
            navigate={~p"/admin/blog/#{@wb_slug}/edit"}
            class="adm-btn adm-btn--small adm-btn--quiet"
          >
            CodeMirror editor
          </.link>
          <button
            form="wb-editor-form"
            type="submit"
            class="adm-btn adm-btn--small adm-btn--primary"
          >
            Save
          </button>
        </:actions>

        <form id="wb-editor-form" phx-change="wb_change" phx-submit="wb_save">
          <textarea
            name="content"
            class="adm-input adm-input--code adm-wb-textarea"
            rows="22"
            phx-debounce="250"
            aria-label={"Draft source of #{@wb_slug}.md"}
          >{@wb_content}</textarea>
        </form>
      </.panel>

      <.panel title="4. Preview" id="panel-preview">
        <:actions>
          <button
            :if={@wb_post.outline.has_outline?}
            type="button"
            phx-click="wb_toggle_beats"
            aria-pressed={to_string(@wb_show_beats)}
            class="adm-btn adm-btn--small adm-btn--quiet"
          >
            {if @wb_show_beats, do: "Prose only", else: "Show beats"}
          </button>
          <.pill :if={@wb_post.draft} tone="draft">draft</.pill>
          <.pill :if={!@wb_post.draft} tone="live">published</.pill>
        </:actions>

        <h2 class="adm-preview-title">{@wb_post.title}</h2>
        <p class="adm-help">
          <span class="adm-figure">{@wb_post.word_count}</span>
          <span :if={@wb_post.outline.target_words}>
            / <span class="adm-figure">{@wb_post.outline.target_words}</span>
          </span>
          words · <span class="adm-figure">{@wb_post.read_min}</span>
          min read
        </p>
        <div class="adm-prose">{raw(@wb_html)}</div>
      </.panel>
    </div>

    <.panel title="New post">
      <form id="new-post-form" phx-submit="new_post" class="adm-inline-form">
        <input
          type="text"
          name="title"
          class="adm-input"
          placeholder="A title to file it under"
          autocomplete="off"
          aria-label="Title of the new post"
          required
        />
        <button type="submit" class="adm-btn adm-btn--primary">
          <.icon name="hero-plus" class="size-4" /> Start a draft
        </button>
      </form>
      <p class="adm-help">
        Makes a file from the vault's blog template, dated today and marked <code>draft: true</code>, and opens it in the editor. It stays off the site until published.
      </p>

      <details class="adm-outline-import">
        <summary>Or start from an outline</summary>
        <form id="new-outline-form" phx-submit="new_from_outline" class="adm-outline-form">
          <textarea
            name="blueprint"
            class="adm-input adm-input--code"
            rows="6"
            placeholder="Paste a markdown essay blueprint (Working Title, section headers with (~250 words), bulleted beats, and Research Checklist)…"
            aria-label="Markdown essay blueprint"
            required
          ></textarea>
          <div>
            <button type="submit" class="adm-btn adm-btn--primary">
              <.icon name="hero-plus" class="size-4" /> Build draft from outline
            </button>
          </div>
        </form>
      </details>
    </.panel>

    <.panel title="Add posts">
      <form id="markdown-upload-form" phx-change="validate">
        <.drop_zone
          upload={@uploads.markdown}
          title="Drop .md files here"
          hint="Up to 10 at a time. Frontmatter carries title, description, date and keywords (tags: works too); anything missing falls back to the filename and the file's date."
          error_message={&upload_error_message/1}
        />
      </form>

      <ul :if={@uploaded != []} class="adm-results">
        <li :for={result <- @uploaded}>
          <%= case result do %>
            <% {:post, slug} -> %>
              ✓ posted <code>{slug}.md</code>
            <% {:image, path} -> %>
              ✓ image at <code>{path}</code>
          <% end %>
        </li>
      </ul>
    </.panel>

    <.panel title="Posts" count={length(@posts)}>
      <.tabs label="Posts">
        <:tab patch={~p"/admin/blog"} active={@filter == "all"} count={length(@posts)}>All</:tab>
        <:tab patch={~p"/admin/blog?filter=drafts"} active={@filter == "drafts"} count={@draft_count}>
          Drafts
        </:tab>
        <:tab
          patch={~p"/admin/blog?filter=missing"}
          active={@filter == "missing"}
          count={@missing_count}
        >
          No keywords
        </:tab>
      </.tabs>

      <.empty :if={@shown == []}>
        {case @filter do
          "missing" -> "Every published post has keywords."
          "drafts" -> "No drafts."
          _ -> "No posts yet."
        end}
      </.empty>

      <div :if={@shown != []} class="adm-list adm-list--desk" id="posts">
        <article :for={post <- @shown} id={"post-#{post.slug}"} class="adm-item">
          <div class="adm-item-main">
            <h2 class="adm-item-title">{post.title}</h2>
            <div class="adm-item-meta">
              <.pill :if={post.draft} tone="draft">draft</.pill>
              <.pill :if={!post.draft} tone="live">published</.pill>
              <.pill :if={post.keywords == [] and not post.draft} tone="held">no keywords</.pill>
              <span class="adm-figure">{Calendar.strftime(post.date, "%Y-%m-%d")}</span>
              <span>
                <span class="adm-figure">{post.word_count}</span>
                <span :if={post.draft and post.outline.target_words}>
                  / <span class="adm-figure">{post.outline.target_words}</span>
                </span>
                words
              </span>
              <span :if={post.draft and post.outline.beats_total > 0}>
                <span class="adm-figure">
                  {post.outline.beats_done}/{post.outline.beats_total}
                </span>
                beats
              </span>
              <span>
                <span class="adm-figure">{readers = Map.get(@readers, post.slug, 0)}</span> {if readers ==
                                                                                                  1,
                                                                                                do:
                                                                                                  "reader",
                                                                                                else:
                                                                                                  "readers"}
              </span>
              <span class="adm-figure">/blog/{post.slug}</span>
            </div>

            <div :if={@keyword_edit != post.slug and post.keywords != []} class="adm-item-meta">
              <.keyword_chips keywords={post.keywords} />
            </div>

            <form
              :if={@keyword_edit == post.slug}
              phx-submit="save_keywords"
              class="adm-inline-form"
            >
              <input type="hidden" name="slug" value={post.slug} />
              <input
                type="text"
                name="keywords"
                class="adm-input"
                value={Enum.join(post.keywords, ", ")}
                placeholder="film, ferry, nyc"
                autocomplete="off"
                aria-label={"Keywords for #{post.title}"}
                phx-mounted={JS.focus()}
              />
              <button type="submit" class="adm-btn adm-btn--small">Write</button>
              <button
                type="button"
                phx-click="cancel_keywords"
                class="adm-btn adm-btn--small adm-btn--quiet"
              >
                Cancel
              </button>
            </form>
          </div>

          <div class="adm-item-actions">
            <.link navigate={~p"/admin/blog/#{post.slug}/edit"} class="adm-btn adm-btn--small">
              Edit
            </.link>
            <.link
              href={~p"/blog/#{post.slug}"}
              target="_blank"
              class="adm-btn adm-btn--small adm-btn--quiet"
            >
              {if post.draft, do: "See the draft", else: "View"}
              <.icon name="hero-arrow-top-right-on-square" class="size-4" />
            </.link>
            <button
              phx-click="set_draft"
              phx-value-slug={post.slug}
              phx-value-draft={to_string(!post.draft)}
              class="adm-btn adm-btn--small adm-btn--quiet"
              data-confirm={!post.draft && "Take /blog/#{post.slug} off the site? The file stays."}
            >
              {if post.draft, do: "Publish", else: "Unpublish"}
            </button>
            <button
              :if={@keyword_edit != post.slug}
              phx-click="edit_keywords"
              phx-value-slug={post.slug}
              class="adm-btn adm-btn--small adm-btn--quiet"
            >
              Keywords
            </button>
            <button
              phx-click="delete_post"
              phx-value-slug={post.slug}
              class="adm-btn adm-btn--small adm-btn--quiet adm-act-danger"
              data-confirm={"Delete #{post.slug}.md from the vault? This cannot be undone."}
            >
              Delete
            </button>
          </div>
        </article>
      </div>
    </.panel>

    <.panel title="Image library" count={length(@images)}>
      <p class="adm-help">Images for embedding in posts. Copy a card's markdown into the post.</p>

      <form id="image-upload-form" phx-change="validate">
        <.drop_zone
          upload={@uploads.image}
          title="Drop images here"
          hint=".jpg .jpeg .png .gif .webp"
          error_message={&upload_error_message/1}
          class="adm-drop--spaced"
        />
      </form>

      <.empty :if={@images == []}>No images uploaded.</.empty>

      <div :if={@images != []} class="adm-images">
        <div :for={{image, index} <- Enum.with_index(@images)} class="adm-image">
          <img src={image.path} alt={image.name} loading="lazy" />
          <div class="adm-image-body">
            <.copy_field
              id={"image-md-#{index}"}
              value={"![#{Path.rootname(image.name)}](#{image.path})"}
            />
            <%!-- An image from the old folder is served from the release's
                  own copy, which deleting the file here would not touch. --%>
            <button
              :if={!image.legacy}
              phx-click="delete_image"
              phx-value-name={image.name}
              class="adm-btn adm-btn--small adm-btn--quiet adm-act-danger"
              data-confirm="Delete this image? Posts that embed it will show a broken image."
            >
              Delete
            </button>
          </div>
        </div>
      </div>
    </.panel>
    """
  end
end
