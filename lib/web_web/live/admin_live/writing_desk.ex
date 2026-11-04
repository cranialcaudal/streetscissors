defmodule WebWeb.AdminLive.WritingDesk do
  @moduledoc """
  The papers (`Web.Writing.Papers`): the list, and a new one from a skeleton or a pasted blueprint (`Writing / Papers`).

  A paper opens in `WebWeb.AdminLive.PaperEditor`, the blog's workbench over
  a file that is never published, with Export.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Writing.{Export, Papers}

  def mount(_params, _session, socket) do
    papers = Papers.list()

    {:ok,
     socket
     |> assign(
       page_title: "Papers | Admin",
       paper_count: length(papers),
       folder: Web.Writing.papers_path(),
       pandoc?: Export.available?(),
       form: to_form(%{"title" => "", "kind" => "article"}, as: :paper),
       blueprint: to_form(%{"text" => ""}, as: :blueprint)
     )
     |> stream(:papers, papers, dom_id: &"paper-#{&1.slug}")}
  end

  def handle_event("create", %{"paper" => %{"title" => title, "kind" => kind}}, socket) do
    kind = if kind in Enum.map(Web.Writing.kinds(), &elem(&1, 0)), do: kind, else: "essay"

    case Papers.create(title, kind) do
      {:ok, slug} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/writing/#{slug}")}

      {:error, :exists} ->
        {:noreply, put_flash(socket, :error, "There is already a paper with that title.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "A paper needs a title to be filed under.")}
    end
  end

  def handle_event("from_blueprint", %{"blueprint" => %{"text" => text}}, socket) do
    case Papers.create_from_blueprint(text) do
      {:ok, slug} ->
        {:noreply, push_navigate(socket, to: ~p"/admin/writing/#{slug}")}

      {:error, :exists} ->
        {:noreply,
         put_flash(socket, :error, "A paper with that outline's title is already here.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Paste a markdown outline with a title to start.")}
    end
  end

  def render(assigns) do
    ~H"""
    <.page_head slug="Writing / Papers" title="Papers">
      <:lede>
        Writing that is not for the blog: papers, reviews, grant pages. The same workbench,
        reading list, citations and Zotero, never published, and exported through Pandoc.
      </:lede>
    </.page_head>

    <.panel title="New paper">
      <.form for={@form} id="new-paper-form" phx-submit="create" class="adm-inline-form">
        <.input
          field={@form[:title]}
          type="text"
          placeholder="A title to file it under"
          aria-label="Title of the new paper"
          class="adm-input"
          autocomplete="off"
          required
        />
        <.input
          field={@form[:kind]}
          type="select"
          options={Enum.map(Web.Writing.kinds(), fn {kind, label} -> {label, kind} end)}
          aria-label="What kind of paper"
          class="adm-select"
        />
        <button type="submit" class="adm-btn adm-btn--primary">
          <.icon name="hero-plus" class="size-4" /> Start
        </button>
      </.form>
      <p class="adm-help">
        Starts a file in the writing folder with sections, word goals and beats for that kind of
        paper, an empty reading list, and <code>zotero:</code>
        and <code>csl:</code>
        lines to name its Zotero folder and citation style.
      </p>

      <details class="adm-outline-import">
        <summary>Or start from an outline</summary>
        <.form
          for={@blueprint}
          id="paper-blueprint-form"
          phx-submit="from_blueprint"
          class="adm-outline-form"
        >
          <.input
            field={@blueprint[:text]}
            type="textarea"
            rows="6"
            class="adm-input adm-input--code"
            placeholder="Paste a markdown blueprint: a title, section headers with (~250 words), bulleted beats, and a reading list…"
            aria-label="Markdown blueprint"
            required
          />
          <div>
            <button type="submit" class="adm-btn adm-btn--primary">Build paper from outline</button>
          </div>
        </.form>
      </details>
    </.panel>

    <.panel title="Papers" count={@paper_count}>
      <p :if={!@pandoc?} class="adm-help" role="alert">
        Pandoc is not on this machine's <code>PATH</code>, so Export is hidden.
      </p>
      <.empty :if={@paper_count == 0}>No papers yet.</.empty>
      <div id="papers" class="adm-list adm-list--desk" phx-update="stream">
        <article :for={{id, paper} <- @streams.papers} id={id} class="adm-item">
          <div class="adm-item-main">
            <h2 class="adm-item-title">{paper.title}</h2>
            <div class="adm-item-meta">
              <span class="adm-figure">{Calendar.strftime(paper.date, "%Y-%m-%d")}</span>
              <span>
                <span class="adm-figure">{paper.word_count}</span>
                <span :if={paper.outline.target_words}>
                  / <span class="adm-figure">{paper.outline.target_words}</span>
                </span>
                words
              </span>
              <span :if={paper.outline.beats_total > 0}>
                <span class="adm-figure">
                  {paper.outline.beats_done}/{paper.outline.beats_total}
                </span>
                beats
              </span>
              <span :if={paper.outline.research.total > 0}>
                <span class="adm-figure">{paper.outline.research.total}</span> sources
              </span>
            </div>
          </div>
          <div class="adm-item-actions">
            <.link navigate={~p"/admin/writing/#{paper.slug}"} class="adm-btn adm-btn--small">
              Open
            </.link>
            <a
              :if={@pandoc?}
              href={~p"/admin/writing/#{paper.slug}/export/docx"}
              class="adm-btn adm-btn--small adm-btn--quiet"
              download
            >
              Word
            </a>
            <a
              :if={@pandoc?}
              href={~p"/admin/writing/#{paper.slug}/export/pdf"}
              class="adm-btn adm-btn--small adm-btn--quiet"
              download
            >
              PDF
            </a>
          </div>
        </article>
      </div>
    </.panel>
    """
  end
end
