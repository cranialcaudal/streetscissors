defmodule WebWeb.AdminLive.BlogManager do
  use WebWeb, :live_view

  alias Web.Blog
  import WebWeb.AdminComponents

  @moduledoc """
  Admin for the blog: typed work only.

  Markdown keeps its batch drop, because a `.md` file already carries its own
  metadata in frontmatter — including `keywords:`, authored in the vault. The
  archive flags any post that arrived without keywords and can write them
  into the file (`Blog.set_keywords/2`), so the vault file stays the source
  of truth either way.

  The image library lives here rather than in a general hub: it exists to
  produce markdown image links for posts.

  `?filter=missing` narrows the list to posts without keywords — the ones the
  public filters can't reach — which is where the overview's "no keywords"
  row points.
  """

  @images_dir Path.join(["priv", "static", "images", "uploads"])

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Blog | Admin")
     |> assign(:uploaded, [])
     |> assign(:keyword_edit, nil)
     |> assign(:filter, "all")
     |> load_posts()
     |> assign(:images, list_images())
     |> allow_upload(:markdown,
       accept: ~w(.md),
       max_entries: 10,
       max_file_size: 20_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )
     |> allow_upload(:image,
       accept: ~w(.jpg .jpeg .png .gif .webp),
       max_entries: 10,
       max_file_size: 50_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  def handle_params(params, _uri, socket) do
    filter = if params["filter"] == "missing", do: "missing", else: "all"
    {:noreply, assign(socket, :filter, filter)}
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
    case Path.safe_relative(name) do
      {:ok, safe} -> File.rm(Path.join(@images_dir, safe))
      :error -> :ok
    end

    {:noreply, socket |> assign(:images, list_images()) |> put_flash(:info, "Image deleted.")}
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
          ext = meta.client_name |> Path.extname() |> String.downcase()
          base = meta.client_name |> Path.basename(ext) |> Web.Keywords.slugify()
          name = "#{base}-#{System.unique_integer([:positive])}#{ext}"

          File.mkdir_p!(@images_dir)
          File.cp!(path, Path.join(@images_dir, name))

          {:ok, {:image, "/images/uploads/#{name}"}}
        end)

      {:noreply,
       socket
       |> assign(:images, list_images())
       |> assign(:uploaded, results ++ socket.assigns.uploaded)}
    else
      {:noreply, socket}
    end
  end

  defp load_posts(socket), do: assign(socket, :posts, Blog.list_posts())

  defp list_images do
    File.mkdir_p!(@images_dir)

    case File.ls(@images_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.match?(&1, ~r/\.(jpg|jpeg|png|gif|webp)$/i))
        |> Enum.map(fn name ->
          %{
            name: name,
            path: "/images/uploads/#{name}",
            mtime: File.stat!(Path.join(@images_dir, name)).mtime
          }
        end)
        |> Enum.sort_by(& &1.mtime, :desc)

      _ ->
        []
    end
  end

  defp upload_error_message(:too_large), do: "File is too large."
  defp upload_error_message(:not_accepted), do: "That file type is not accepted."
  defp upload_error_message(:too_many_files), do: "Too many files at once."
  defp upload_error_message(error), do: to_string(error)

  defp shown(posts, "missing"), do: Enum.filter(posts, &(&1.keywords == []))
  defp shown(posts, _all), do: posts

  def render(assigns) do
    assigns =
      assigns
      |> assign(:shown, shown(assigns.posts, assigns.filter))
      |> assign(:missing_count, Enum.count(assigns.posts, &(&1.keywords == [])))

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
        <:tab
          patch={~p"/admin/blog?filter=missing"}
          active={@filter == "missing"}
          count={@missing_count}
        >
          No keywords
        </:tab>
      </.tabs>

      <.empty :if={@shown == []}>
        {if @filter == "missing", do: "Every post has keywords.", else: "No posts yet."}
      </.empty>

      <div :if={@shown != []} class="adm-list" id="posts">
        <article :for={post <- @shown} id={"post-#{post.slug}"} class="adm-item">
          <div class="adm-item-main">
            <h2 class="adm-item-title">{post.title}</h2>
            <div class="adm-item-meta">
              <span>{Calendar.strftime(post.date, "%Y-%m-%d")}</span>
              <span>{post.word_count} words</span>
              <span>/blog/{post.slug}</span>
            </div>

            <div :if={@keyword_edit != post.slug} class="adm-item-meta">
              <.keyword_chips keywords={post.keywords} />
              <.pill :if={post.keywords == []} tone="held">no keywords</.pill>
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
            <.link href={~p"/blog/#{post.slug}"} target="_blank" class="adm-link">
              View <.icon name="hero-arrow-top-right-on-square" class="size-4" />
            </.link>
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
            <button
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
