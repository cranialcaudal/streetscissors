defmodule WebWeb.AdminLive.BlogManager do
  use WebWeb, :live_view

  alias Web.Blog
  import WebWeb.CmsStyles

  @moduledoc """
  Admin for the blog: typed work only.

  Markdown keeps its batch drop, because a `.md` file already carries its own
  metadata in frontmatter — including `keywords:`, authored in the vault. The
  archive flags any post that arrived without keywords and can write them
  into the file (`Blog.set_keywords/2`), so the vault file stays the source
  of truth either way.

  The image library lives here rather than in a general hub: it exists to
  produce markdown image links for posts.
  """

  @images_dir Path.join(["priv", "static", "images", "uploads"])

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Blog | Admin")
     |> assign(:uploaded, [])
     |> assign(:keyword_edit, nil)
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
    {:noreply, socket |> load_posts() |> put_flash(:info, "Redacted.")}
  end

  def handle_event("delete_image", %{"name" => name}, socket) do
    case Path.safe_relative(name) do
      {:ok, safe} -> File.rm(Path.join(@images_dir, safe))
      :error -> :ok
    end

    {:noreply, socket |> assign(:images, list_images()) |> put_flash(:info, "Image purged.")}
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

  def render(assigns) do
    ~H"""
    <div class="cms">
      <h1 class="cms-title">Blog</h1>
      <p class="cms-lede">
        Typed work only — spoken pieces live in <.link navigate={~p"/admin/logs"} class="cms-link">Captain's Logs</.link>.
      </p>

      <section class="cms-panel">
        <h2>Post markdown</h2>
        <p class="cms-hint">
          Frontmatter carries the metadata: <code>title</code>, <code>description</code>, <code>date</code>, and
          <code>keywords</code>
          (<code>tags</code> reads too, for
          Obsidian's native key). Anything missing falls back to the filename and mtime.
        </p>

        <form id="markdown-upload-form" phx-change="validate">
          <div class="cms-drop" phx-drop-target={@uploads.markdown.ref}>
            <div class="cms-drop-title">DROP .MD FILES HERE</div>
            <p class="cms-hint">Up to 10 at a time</p>
            <label class="cms-browse">
              BROWSE FILES <.live_file_input upload={@uploads.markdown} class="cms-file-input" />
            </label>

            <div :for={entry <- @uploads.markdown.entries} class="cms-entry">
              {entry.client_name}
              <div class="cms-progress">
                <div class="cms-progress-bar" style={"width: #{entry.progress}%"}></div>
              </div>
              <p :for={err <- upload_errors(@uploads.markdown, entry)} class="cms-error">
                {upload_error_message(err)}
              </p>
            </div>
          </div>
        </form>

        <ul :if={@uploaded != []} class="cms-results">
          <li :for={result <- @uploaded}>
            <%= case result do %>
              <% {:post, slug} -> %>
                ✓ posted <code>{slug}.md</code>
              <% {:image, path} -> %>
                ✓ image at <code>{path}</code>
            <% end %>
          </li>
        </ul>
      </section>

      <section class="cms-panel">
        <h2>Archive ({length(@posts)})</h2>

        <div :if={@posts == []} class="cms-empty">No posts yet.</div>

        <div class="cms-list">
          <div :for={post <- @posts} class="cms-item">
            <div class="cms-item-head">
              <div style="min-width: 0;">
                <h3 class="cms-item-title">{post.title}</h3>
                <div class="cms-item-meta">
                  <span>{Calendar.strftime(post.date, "%Y-%m-%d")}</span>
                  <span>{post.word_count} words</span>
                  <span>/blog/{post.slug}</span>
                </div>

                <div :if={post.keywords != []} class="cms-keywords">
                  <span :for={keyword <- post.keywords} class="cms-keyword">{keyword}</span>
                </div>
                <div
                  :if={post.keywords == [] and @keyword_edit != post.slug}
                  class="cms-keyword-missing"
                >
                  ⚠ no keywords — this post cannot be filtered
                </div>

                <form
                  :if={@keyword_edit == post.slug}
                  phx-submit="save_keywords"
                  class="cms-keyword-form"
                >
                  <input type="hidden" name="slug" value={post.slug} />
                  <input
                    type="text"
                    name="keywords"
                    class="cms-input"
                    value={Enum.join(post.keywords, ", ")}
                    placeholder="film, ferry, nyc"
                    autocomplete="off"
                  />
                  <button type="submit" class="cms-link">Write</button>
                  <button type="button" phx-click="cancel_keywords" class="cms-link">Cancel</button>
                </form>
              </div>

              <div class="cms-item-actions">
                <button
                  :if={@keyword_edit != post.slug}
                  phx-click="edit_keywords"
                  phx-value-slug={post.slug}
                  class="cms-link"
                >
                  Keywords
                </button>
                <button
                  phx-click="delete_post"
                  phx-value-slug={post.slug}
                  class="cms-link danger"
                  data-confirm="Purge this post?"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section class="cms-panel">
        <h2>Image library</h2>
        <p class="cms-hint">
          Images for embedding in posts. Copy the markdown from a card below.
        </p>

        <form id="image-upload-form" phx-change="validate">
          <div class="cms-drop" phx-drop-target={@uploads.image.ref}>
            <div class="cms-drop-title">DROP IMAGES HERE</div>
            <p class="cms-hint">.jpg .jpeg .png .gif .webp</p>
            <label class="cms-browse">
              BROWSE FILES <.live_file_input upload={@uploads.image} class="cms-file-input" />
            </label>

            <div :for={entry <- @uploads.image.entries} class="cms-entry">
              {entry.client_name}
              <div class="cms-progress">
                <div class="cms-progress-bar" style={"width: #{entry.progress}%"}></div>
              </div>
              <p :for={err <- upload_errors(@uploads.image, entry)} class="cms-error">
                {upload_error_message(err)}
              </p>
            </div>
          </div>
        </form>

        <div :if={@images == []} class="cms-empty">No images uploaded.</div>

        <div :if={@images != []} class="cms-images" style="margin-top: 1.5rem;">
          <div :for={image <- @images} class="cms-image">
            <img src={image.path} alt={image.name} />
            <input
              type="text"
              value={"![#{Path.rootname(image.name)}](#{image.path})"}
              readonly
              onclick="this.select(); navigator.clipboard && navigator.clipboard.writeText(this.value)"
            />
            <button
              phx-click="delete_image"
              phx-value-name={image.name}
              class="cms-link danger"
              data-confirm="Purge this image?"
              style="margin-top: 0.4rem;"
            >
              Delete
            </button>
          </div>
        </div>
      </section>

      <.cms_styles />
    </div>
    """
  end
end
