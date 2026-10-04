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

  The `.PostEditor` hook adds the two things a textarea lacks: ⌘S / Ctrl+S
  saves, and leaving the page with unsaved text asks first.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Blog

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
             conflict: nil
           )
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

  # The submitter says what the save is for: plain, or publishing with it.
  def handle_event("save", %{"content" => content} = params, socket) do
    content =
      case params["then"] do
        "publish" -> Blog.mark_draft(content, false)
        "unpublish" -> Blog.mark_draft(content, true)
        _ -> content
      end

    {:noreply, socket |> put_content(content) |> save([])}
  end

  def handle_event("take_disk", _params, socket) do
    %{content: content, revision: revision} = socket.assigns.conflict

    {:noreply,
     socket
     |> assign(revision: revision, saved: content, conflict: nil)
     |> put_content(content)
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
    assign(socket, content: content, post: post, html: Blog.to_html(post.body))
  end

  def render(assigns) do
    assigns = assign(assigns, :dirty, assigns.content != assigns.saved)

    ~H"""
    <.page_head slug="Write / Blog / Edit" title={@post.title}>
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
        <button type="button" phx-click="keep_editing" class="adm-link adm-link--quiet">
          Keep editing
        </button>
      </div>
      <details class="adm-conflict-disk">
        <summary>What is on disk now</summary>
        <pre>{@conflict.content}</pre>
      </details>
    </section>

    <form
      id="post-editor"
      class="adm-editor adm-editor--post"
      phx-change="change"
      phx-submit="save"
      phx-hook=".PostEditor"
      data-dirty={to_string(@dirty)}
    >
      <div class="adm-editor-body">
        <p class="adm-editor-bar">
          <span>Source</span>
          <.pill :if={@dirty} tone="held">unsaved</.pill>
          <.pill :if={!@dirty} tone="quiet">saved</.pill>
        </p>
        <textarea
          id="post-source"
          name="content"
          class="adm-input adm-input--code"
          phx-debounce="300"
          spellcheck="true"
          aria-label={"Source of #{@slug}.md"}
        >{@content}</textarea>
      </div>

      <div class="adm-editor-body" id="post-preview">
        <p class="adm-editor-bar">
          <span>As the site reads it</span>
          <.pill :if={@post.draft} tone="draft">draft</.pill>
          <.pill :if={!@post.draft} tone="live">published</.pill>
        </p>
        <dl class="adm-facts">
          <div>
            <dt>Date</dt>
            <dd>{stamp(@post.date)}</dd>
          </div>
          <div>
            <dt>Length</dt>
            <dd>{@post.word_count} words, {@post.read_min} min</dd>
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
        <div class="adm-prose">{raw(@html)}</div>
      </div>
    </form>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PostEditor">
      // The two things a textarea lacks: Cmd/Ctrl+S saves, and leaving with
      // unsaved text asks first. Whether there is unsaved text is the
      // server's to say (data-dirty), so the guard and the pill never disagree.
      export default {
        mounted() {
          this.onKey = (event) => {
            if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "s") {
              event.preventDefault()
              this.el.requestSubmit()
            }
          }
          this.onLeave = (event) => {
            if (this.el.dataset.dirty === "true") {
              event.preventDefault()
              event.returnValue = ""
            }
          }
          window.addEventListener("keydown", this.onKey)
          window.addEventListener("beforeunload", this.onLeave)
        },
        destroyed() {
          window.removeEventListener("keydown", this.onKey)
          window.removeEventListener("beforeunload", this.onLeave)
        }
      }
    </script>
    """
  end
end
