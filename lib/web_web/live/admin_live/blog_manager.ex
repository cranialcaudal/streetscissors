defmodule WebWeb.AdminLive.BlogManager do
  use WebWeb, :live_view

  alias Web.Blog
  alias Web.Blog.Images
  import WebWeb.AdminComponents

  @moduledoc """
  Admin for the blog: typed work only.

  Markdown keeps its batch drop, because a `.md` file already carries its own
  metadata in frontmatter — including `keywords:`, authored in the vault. The
  archive flags any post that arrived without keywords and can write them
  into the file (`Blog.set_keywords/2`), so the vault file stays the source
  of truth either way.

  The image library (`Web.Blog.Images`) lives here rather than in a general
  hub: it exists to produce markdown image links for posts.

  `?filter=missing` narrows the list to posts without keywords — the ones the
  public filters can't reach — which is where the overview's "no keywords"
  row points. `?filter=drafts` is the posts whose frontmatter says
  `draft: true`: on disk, off the site.

  A post is written in `WebWeb.AdminLive.BlogEditor`. "New post" here starts
  one from the vault's own template, as a draft, and opens it there.
  """

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Blog | Admin")
     |> assign(:uploaded, [])
     |> assign(:keyword_edit, nil)
     |> assign(:filter, "all")
     |> load_posts()
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
     )}
  end

  def handle_params(params, _uri, socket) do
    filter = if params["filter"] in ~w(missing drafts), do: params["filter"], else: "all"
    {:noreply, assign(socket, :filter, filter)}
  end

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

  defp load_posts(socket), do: assign(socket, :posts, Blog.list_all_posts())

  defp upload_error_message(:too_large), do: "File is too large."
  defp upload_error_message(:not_accepted), do: "That file type is not accepted."
  defp upload_error_message(:too_many_files), do: "Too many files at once."
  defp upload_error_message(error), do: to_string(error)

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

    ~H"""
    <.page_head slug="Write / Blog" title="Blog">
      <:lede>
        Typed work, as markdown files in the vault; this page writes the same files. Spoken pieces
        live in <.link navigate={~p"/admin/logs"} class="adm-link">Captain's Logs</.link>.
      </:lede>
      <:actions>
        <.link href={~p"/blog"} target="_blank" class="adm-btn adm-btn--quiet">
          <.icon name="hero-arrow-top-right-on-square" class="size-4" /> View the blog
        </.link>
      </:actions>
    </.page_head>

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

      <div :if={@shown != []} class="adm-list" id="posts">
        <article :for={post <- @shown} id={"post-#{post.slug}"} class="adm-item">
          <div class="adm-item-main">
            <h2 class="adm-item-title">{post.title}</h2>
            <div class="adm-item-meta">
              <.pill :if={post.draft} tone="draft">draft</.pill>
              <span>{Calendar.strftime(post.date, "%Y-%m-%d")}</span>
              <span>{post.word_count} words</span>
              <span>/blog/{post.slug}</span>
            </div>

            <div :if={@keyword_edit != post.slug} class="adm-item-meta">
              <.keyword_chips keywords={post.keywords} />
              <.pill :if={post.keywords == [] and not post.draft} tone="held">no keywords</.pill>
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
              <button type="button" phx-click="cancel_keywords" class="adm-link adm-link--quiet">
                Cancel
              </button>
            </form>
          </div>

          <div class="adm-item-actions">
            <.link navigate={~p"/admin/blog/#{post.slug}/edit"} class="adm-link">Edit</.link>
            <.link href={~p"/blog/#{post.slug}"} target="_blank" class="adm-link">
              {if post.draft, do: "See the draft", else: "View"}
              <.icon name="hero-arrow-top-right-on-square" class="size-4" />
            </.link>
            <button
              phx-click="set_draft"
              phx-value-slug={post.slug}
              phx-value-draft={to_string(!post.draft)}
              class="adm-link"
              data-confirm={!post.draft && "Take /blog/#{post.slug} off the site? The file stays."}
            >
              {if post.draft, do: "Publish", else: "Unpublish"}
            </button>
            <button
              :if={@keyword_edit != post.slug}
              phx-click="edit_keywords"
              phx-value-slug={post.slug}
              class="adm-link"
            >
              Keywords
            </button>
            <button
              phx-click="delete_post"
              phx-value-slug={post.slug}
              class="adm-link adm-link--danger"
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
              class="adm-link adm-link--danger"
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
