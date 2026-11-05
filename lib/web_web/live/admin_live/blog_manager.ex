defmodule WebWeb.AdminLive.BlogManager do
  use WebWeb, :live_view

  alias Web.Blog
  alias Web.Blog.Images
  import WebWeb.AdminComponents

  @moduledoc """
  Admin for the blog (`Writing / Blog`): the writing desk, new posts, the archive and the image library.

    * **The desk**: `WebWeb.AdminLive.Workbench` over the active essay (an
      outlined draft first), with a picker for the others.
    * **New post / blueprint importer**, batch `.md` drop, the **Posts**
      archive, and the **Image library** below.
  """

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Blog | Admin")
      |> assign(:uploaded, [])
      |> assign(:keyword_edit, nil)
      |> assign(:filter, "all")
      |> assign(:new_post, to_form(%{"title" => "", "kind" => "essay"}, as: :post))
      |> load_posts()
      |> then(&assign(&1, :wb_slug, desk_slug(&1.assigns.posts)))
      |> WebWeb.AdminLive.Workbench.attach()
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

  def handle_event("new_post", %{"post" => %{"title" => title} = params}, socket) do
    kinds = ["blank" | Enum.map(Web.Writing.kinds(), &elem(&1, 0))]
    kind = if params["kind"] in kinds, do: params["kind"], else: "essay"

    case Blog.create_draft(title, kind) do
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

  # The workbench saved: the archive and the picker show its new counts.
  def handle_info({:workbench_saved, _slug}, socket), do: {:noreply, load_posts(socket)}

  defp load_posts(socket) do
    socket
    |> assign(:posts, Blog.list_all_posts())
    |> assign(:readers, Web.Analytics.post_readers())
  end

  # An outlined draft first, then any outlined post, any draft, the newest.
  defp desk_slug(posts) do
    post =
      Enum.find(posts, &(&1.draft and &1.outline.has_outline?)) ||
        Enum.find(posts, & &1.outline.has_outline?) ||
        Enum.find(posts, & &1.draft) ||
        List.first(posts)

    post && post.slug
  end

  defp upload_error_message(:too_large), do: "File is too large."
  defp upload_error_message(:not_accepted), do: "That file type is not accepted."
  defp upload_error_message(:too_many_files), do: "Too many files at once."
  defp upload_error_message(error), do: to_string(error)

  defp shown(posts, "missing"), do: Enum.filter(posts, &(&1.keywords == [] and not &1.draft))
  defp shown(posts, "drafts"), do: Enum.filter(posts, & &1.draft)
  defp shown(posts, _all), do: posts

  def render(assigns) do
    assigns =
      assigns
      |> assign(:shown, shown(assigns.posts, assigns.filter))
      |> assign(:missing_count, length(shown(assigns.posts, "missing")))
      |> assign(:draft_count, length(shown(assigns.posts, "drafts")))

    ~H"""
    <.page_head slug="Writing / Blog" title="Blog">
      <:lede>
        Typed work, as markdown files in the vault; this page writes the same files. Spoken pieces
        live in <.link navigate={~p"/admin/logs"} class="adm-link">Videostream</.link>.
      </:lede>
      <:actions>
        <.link href={~p"/blog"} target="_blank" class="adm-btn adm-btn--quiet">
          <.icon name="hero-arrow-top-right-on-square" class="size-4" /> View the blog
        </.link>
      </:actions>
    </.page_head>

    <.live_component
      :if={@wb_slug}
      module={WebWeb.AdminLive.Workbench}
      id="workbench"
      slug={@wb_slug}
      mode="desk"
      posts={@posts}
    />

    <.panel title="New post">
      <.form for={@new_post} id="new-post-form" phx-submit="new_post" class="adm-inline-form">
        <.input
          field={@new_post[:title]}
          type="text"
          class="adm-input"
          placeholder="A title to file it under"
          autocomplete="off"
          aria-label="Title of the new post"
          required
        />
        <.input
          field={@new_post[:kind]}
          type="select"
          class="adm-select"
          aria-label="What the draft starts with"
          options={
            Enum.map(Web.Writing.kinds(), fn {kind, label} -> {label, kind} end) ++
              [{"Blank (the vault's template)", "blank"}]
          }
        />
        <button type="submit" class="adm-btn adm-btn--primary">
          <.icon name="hero-plus" class="size-4" /> Start a draft
        </button>
      </.form>
      <p class="adm-help">
        Makes a file dated today and marked <code>draft: true</code>, with the vault template's frontmatter and the outline of the kind you pick already in it: an empty reading list, sections with word goals, and beats. It opens in the editor and stays off the site until published.
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
