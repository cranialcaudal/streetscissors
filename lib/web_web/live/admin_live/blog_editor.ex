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
             conflict: nil
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

  # The submitter says what the save is for: plain, or publishing with it.
  def handle_event("save", %{"content" => typed} = params, socket) do
    content =
      case params["then"] do
        "publish" -> Blog.mark_draft(typed, false)
        "unpublish" -> Blog.mark_draft(typed, true)
        _ -> typed
      end

    # Publishing rewrote the draft line: the editor is shown the new text.
    socket = if content == typed, do: socket, else: DocumentEditor.set(socket, "post-source", content)

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
    assign(socket, content: content, post: post, html: Blog.to_html(post.body))
  end

  defp lf(text), do: String.replace(text, "\r\n", "\n")

  def render(assigns) do
    # A browser sends \n where the file may have \r\n (Web.SourceFile puts
    # them back on save), so line endings alone are not unsaved work.
    assigns = assign(assigns, :dirty, lf(assigns.content) != lf(assigns.saved))

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
          <.pill :if={@post.draft} tone="draft">draft</.pill>
          <.pill :if={!@post.draft} tone="live">published</.pill>
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
        <div class="adm-prose">{raw(@html)}</div>
      </div>
    </form>
    """
  end
end
