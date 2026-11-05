defmodule WebWeb.AdminLive.ZoteroReaderComponent do
  @moduledoc """
  A Zotero document open for reading: its PDF or EPUB under a highlighting toolbar, beside its annotations and notes, all written back to Zotero.

  Rendered by the reading page (`WebWeb.AdminLive.ZoteroReader`) and by the
  writing workbench's first panel (`WebWeb.AdminLive.Workbench`), so a source
  can be read beside the draft it is for. Attributes: `item_key` (an item, or
  one of its files), `attachment_key` (the file to open first, optional),
  `full_page` (the reading page: the document's title is the page's, sent up
  as `{:reader_opened, title}`), and `quote_target` (the workbench: where
  **Quote in draft** sends `"reader_quote"` with the item, the text and its
  page).

  Selecting text in the document fills the toolbar; **Highlight** or
  **Underline** saves it in Zotero in the chosen colour, with the comment.
  Each annotation can be commented, shown, quoted or deleted, and a note can
  be added to the item. Everything goes through `Web.Writing.Zotero.Reader`.
  The toolbar is always there, so the page does not move under a selection.

  The document is drawn by the `ZoteroReader` hook (`assets/js/zotero_reader.js`:
  PDF.js for a PDF, epub.js for an EPUB) inside an element it owns
  (`phx-update="ignore"`). The hook's events come here (`pushEventTo`); the
  marks to draw go back as `reader:annotations`, a jump as `reader:jump`.
  Flash goes to the host as `{:workbench_flash, kind, message}`.
  """

  use WebWeb, :live_component

  alias Web.Writing.Zotero.Reader

  @impl true
  def update(assigns, socket) do
    socket =
      assign(socket,
        quote_target: Map.get(assigns, :quote_target),
        full_page: Map.get(assigns, :full_page, false)
      )

    if Map.has_key?(socket.assigns, :item_key) do
      {:ok, socket}
    else
      socket =
        socket
        |> assign(
          id: assigns.id,
          item_key: assigns.item_key,
          doc: nil,
          attachment: nil,
          error: nil,
          selection: nil,
          annotation_count: 0,
          marks: [],
          note_count: 0,
          highlight_form: to_form(%{"comment" => "", "color" => "yellow"}, as: :highlight),
          note_form: to_form(%{"text" => ""}, as: :note)
        )
        |> stream(:annotations, [], dom_id: &"ann-#{&1.key}")
        |> stream(:notes, [], dom_id: &"note-#{&1.key}")

      {:ok, if(connected?(socket), do: load(socket, assigns[:attachment_key]), else: socket)}
    end
  end

  defp load(socket, wanted) do
    key = socket.assigns.item_key

    start_async(socket, :load, fn ->
      with {:ok, doc} <- Reader.document(key) do
        attachment =
          Enum.find(doc.attachments, &(&1.key == wanted)) || List.first(doc.attachments)

        {:ok, doc, attachment, load_annotations(attachment), load_notes(doc.notes_key)}
      end
    end)
  end

  defp load_annotations(nil), do: []

  defp load_annotations(attachment) do
    case Reader.annotations(attachment.key) do
      {:ok, list} -> list
      _ -> []
    end
  end

  defp load_notes(key) do
    case Reader.notes(key) do
      {:ok, list} -> list
      _ -> []
    end
  end

  @impl true
  def handle_async(:load, {:ok, {:ok, doc, attachment, annotations, notes}}, socket) do
    if socket.assigns.full_page, do: send(self(), {:reader_opened, doc.item.title})

    {:noreply,
     socket
     |> assign(
       doc: doc,
       attachment: attachment,
       error: if(is_nil(attachment), do: "This item has no PDF or EPUB stored in Zotero."),
       selection: nil
     )
     |> put_annotations(annotations)
     |> put_notes(notes)}
  end

  def handle_async(:load, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, error: describe(reason))}
  end

  def handle_async(:load, {:exit, _reason}, socket) do
    {:noreply, assign(socket, error: "Could not reach api.zotero.org.")}
  end

  # The hook is told the marks to draw as they change, and asks for them
  # itself once it has the document open (a push before then is lost).
  defp put_annotations(socket, annotations) do
    marks = Enum.map(annotations, &for_hook/1)

    socket
    |> assign(annotation_count: length(annotations), marks: marks)
    |> stream(:annotations, annotations, reset: true)
    |> push_event("reader:annotations", %{annotations: marks})
  end

  defp put_notes(socket, notes) do
    socket |> assign(:note_count, length(notes)) |> stream(:notes, notes, reset: true)
  end

  # What the hook draws: no text or comment, only where and how.
  defp for_hook(a), do: Map.take(a, [:key, :type, :color_name, :position])

  defp reload_annotations(socket) do
    put_annotations(socket, load_annotations(socket.assigns.attachment))
  end

  # Flash is the layout's, so the host LiveView puts it.
  defp flash(socket, kind, message) do
    send(self(), {:workbench_flash, kind, message})
    socket
  end

  # ── From the document ─────────────────────────────────────────────────

  @impl true
  def handle_event("reader_ready", _params, socket) do
    {:reply, %{annotations: socket.assigns.marks}, socket}
  end

  def handle_event("selection", %{"text" => text} = params, socket) when is_binary(text) do
    text = text |> String.replace(~r/\s+/u, " ") |> String.trim()

    selection =
      if text == "",
        do: nil,
        else: Map.take(params, ~w(position sort_index page_label)) |> Map.put("text", text)

    {:noreply, assign(socket, :selection, selection)}
  end

  def handle_event("selection", _params, socket), do: {:noreply, assign(socket, :selection, nil)}

  # Another of the item's files.
  def handle_event("pick", %{"key" => key}, socket) do
    case socket.assigns.doc && Enum.find(socket.assigns.doc.attachments, &(&1.key == key)) do
      nil ->
        {:noreply, socket}

      attachment ->
        {:noreply,
         socket
         |> assign(attachment: attachment, selection: nil)
         |> put_annotations(load_annotations(attachment))}
    end
  end

  # ── Annotations ───────────────────────────────────────────────────────

  def handle_event("annotate", %{"highlight" => form} = params, socket) do
    %{selection: selection, attachment: attachment} = socket.assigns

    if selection && attachment do
      attrs =
        Map.merge(selection, %{
          "type" => if(params["type"] == "underline", do: "underline", else: "highlight"),
          "color" => form["color"],
          "comment" => form["comment"]
        })

      case Reader.create_annotation(attachment, attrs) do
        {:ok, _annotation} ->
          {:noreply,
           socket
           |> assign(
             selection: nil,
             highlight_form: to_form(%{"comment" => "", "color" => form["color"]}, as: :highlight)
           )
           |> push_event("reader:clear_selection", %{})
           |> reload_annotations()
           |> flash(:info, "Saved to Zotero.")}

        {:error, reason} ->
          {:noreply, flash(socket, :error, "Not saved: " <> describe(reason))}
      end
    else
      {:noreply, flash(socket, :error, "Select some text in the document first.")}
    end
  end

  def handle_event("comment", %{"key" => key, "version" => version} = params, socket) do
    changes = Map.take(params, ~w(comment color))

    case Reader.update_annotation(key, version, changes) do
      :ok ->
        {:noreply, socket |> reload_annotations() |> flash(:info, "Saved to Zotero.")}

      {:error, reason} ->
        {:noreply,
         socket |> reload_annotations() |> flash(:error, "Not saved: " <> describe(reason))}
    end
  end

  def handle_event("delete", %{"key" => key, "version" => version}, socket) do
    case Reader.delete_annotation(key, version) do
      :ok ->
        {:noreply, socket |> reload_annotations() |> flash(:info, "Deleted in Zotero.")}

      {:error, reason} ->
        {:noreply,
         socket |> reload_annotations() |> flash(:error, "Not deleted: " <> describe(reason))}
    end
  end

  def handle_event("jump", %{"key" => key}, socket) do
    {:noreply, push_event(socket, "reader:jump", %{key: key})}
  end

  # ── Notes ─────────────────────────────────────────────────────────────

  def handle_event("add_note", %{"note" => %{"text" => text}}, socket) do
    case socket.assigns.doc && socket.assigns.doc.notes_key do
      nil ->
        {:noreply, flash(socket, :error, "A standalone file has no item to hold notes.")}

      key ->
        case Reader.create_note(key, text) do
          :ok ->
            {:noreply,
             socket
             |> assign(note_form: to_form(%{"text" => ""}, as: :note))
             |> put_notes(load_notes(key))
             |> flash(:info, "Note saved to Zotero.")}

          {:error, :blank} ->
            {:noreply, flash(socket, :error, "Write the note first.")}

          {:error, reason} ->
            {:noreply, flash(socket, :error, "Not saved: " <> describe(reason))}
        end
    end
  end

  defp describe(:auth_failed), do: "Zotero refused the API key (it needs write access)."

  defp describe(:conflict),
    do: "it changed in Zotero since this page read it; it has been reread."

  defp describe(:not_found), do: "Zotero has no such item."
  defp describe(:no_file), do: "Zotero holds no file for it."
  defp describe(:not_configured), do: "set ZOTERO_USER_ID and ZOTERO_API_KEY in .env."
  defp describe({:rejected, message}), do: "Zotero said: " <> to_string(message)

  defp describe(reason) when reason in [:bad_position, :bad_sort_index, :bad_type, :no_text],
    do: "the selection could not be placed on the page; select it again."

  defp describe(_), do: "could not reach api.zotero.org."

  defp file_url(attachment),
    do: ~p"/admin/zotero/file/#{attachment.key}/#{attachment.md5 || "none"}"

  defp where(%{page_label: label}) when label != "", do: "p. #{label}"
  defp where(_), do: nil

  defp kind_label(attachment), do: attachment.kind |> to_string() |> String.upcase()

  # Quoting needs an item to cite: a file standing alone has none.
  defp can_quote?(quote_target, doc),
    do: quote_target != nil and doc != nil and doc.notes_key != nil

  @impl true
  def render(assigns) do
    ~H"""
    <div class="adm-reader-wrap">
      <header :if={@doc} class="adm-reader-head">
        <strong :if={!@full_page} class="adm-zotero-item-title">{@doc.item.title}</strong>
        <span class="adm-zotero-item-meta">
          {@doc.item.authors}{if @doc.item.year, do: " (#{@doc.item.year})"}
        </span>
      </header>

      <p :if={@error} id="reader-error" class="adm-help" role="alert">{@error}</p>
      <p :if={!@doc and !@error} id="reader-loading" class="adm-help">Asking Zotero…</p>

      <nav
        :if={@doc && length(@doc.attachments) > 1}
        id="reader-attachments"
        class="adm-reader-files"
        aria-label="Files of this item"
      >
        <button
          :for={att <- @doc.attachments}
          type="button"
          phx-click="pick"
          phx-value-key={att.key}
          phx-target={@myself}
          aria-pressed={to_string(@attachment != nil and att.key == @attachment.key)}
          class={[
            "adm-btn adm-btn--small adm-btn--quiet",
            @attachment && att.key == @attachment.key && "is-active"
          ]}
        >
          {att.title} ({kind_label(att)})
        </button>
      </nav>

      <p :if={@doc && @attachment && is_nil(@doc.notes_key)} id="reader-standalone" class="adm-help">
        This file stands alone in Zotero, so it cannot hold notes or be cited.
        In Zotero, drag it onto its item to file it there.
      </p>

      <div :if={@attachment} class={["adm-reader", @full_page && "adm-reader--page"]}>
        <.form
          for={@highlight_form}
          id="annotate-form"
          phx-submit="annotate"
          phx-target={@myself}
          class="adm-reader-bar"
        >
          <p id="reader-picked" class={["adm-reader-picked", @selection && "is-picked"]}>
            <%= if @selection do %>
              “{@selection["text"]}”
            <% else %>
              Select text in the document to highlight, underline or quote it.
            <% end %>
          </p>
          <fieldset class="adm-reader-colors">
            <legend class="adm-reader-color-name">Colour</legend>
            <label :for={{name, _hex} <- Reader.colors()} class="adm-reader-color" title={name}>
              <input
                type="radio"
                name="highlight[color]"
                value={name}
                checked={@highlight_form[:color].value == name}
              />
              <span class={["adm-reader-swatch", "adm-ann--#{name}"]} aria-hidden="true"></span>
              <span class="adm-reader-color-name">{name}</span>
            </label>
          </fieldset>
          <div class="adm-reader-bar-comment">
            <.input
              field={@highlight_form[:comment]}
              type="text"
              class="adm-input adm-input--small"
              placeholder="Comment (optional)"
              aria-label="Comment on the selection"
            />
          </div>
          <div class="adm-reader-bar-actions">
            <button
              type="submit"
              name="type"
              value="highlight"
              class="adm-btn adm-btn--small adm-btn--primary"
              disabled={is_nil(@selection)}
            >
              Highlight
            </button>
            <button
              type="submit"
              name="type"
              value="underline"
              class="adm-btn adm-btn--small"
              disabled={is_nil(@selection)}
            >
              Underline
            </button>
            <button
              :if={@quote_target}
              id="reader-quote-selection"
              type="button"
              phx-click="reader_quote"
              phx-target={@quote_target}
              phx-value-item={@doc.notes_key}
              phx-value-text={@selection && @selection["text"]}
              phx-value-page={@selection && @selection["page_label"]}
              class="adm-btn adm-btn--small"
              disabled={is_nil(@selection) or not can_quote?(@quote_target, @doc)}
              title="Type it at the draft's cursor, cited"
            >
              Quote in draft
            </button>
          </div>
        </.form>

        <div
          id={"reader-#{@attachment.key}"}
          class="adm-reader-view"
          phx-hook="ZoteroReader"
          phx-update="ignore"
          phx-target={@myself}
          data-kind={@attachment.kind}
          data-src={file_url(@attachment)}
        >
          <p class="adm-help">Opening the {kind_label(@attachment)}…</p>
        </div>

        <aside class="adm-reader-side" aria-label="Annotations and notes">
          <section id="reader-annotations" class="adm-reader-box">
            <h3 class="adm-outline-label">
              Annotations<span class="adm-count">{@annotation_count}</span>
            </h3>
            <p :if={@annotation_count == 0} class="adm-help">None yet.</p>
            <ol id="annotations" phx-update="stream" class="adm-reader-list">
              <li :for={{id, a} <- @streams.annotations} id={id} class="adm-reader-ann">
                <div class="adm-reader-ann-head">
                  <span class={["adm-reader-swatch", "adm-ann--#{a.color_name}"]} aria-hidden="true"></span>
                  <span class="adm-outline-label">
                    {a.type}<span :if={where(a)}> · {where(a)}</span>
                  </span>
                  <span class="adm-reader-ann-acts">
                    <button
                      type="button"
                      phx-click="jump"
                      phx-value-key={a.key}
                      phx-target={@myself}
                      class="adm-btn adm-btn--small adm-btn--quiet"
                    >
                      Show
                    </button>
                    <button
                      :if={can_quote?(@quote_target, @doc) and a.text != ""}
                      type="button"
                      phx-click="reader_quote"
                      phx-target={@quote_target}
                      phx-value-item={@doc.notes_key}
                      phx-value-text={a.text}
                      phx-value-page={a.page_label}
                      class="adm-btn adm-btn--small adm-btn--quiet"
                      title="Type it at the draft's cursor, cited"
                    >
                      Quote
                    </button>
                  </span>
                </div>
                <blockquote :if={a.text != ""} class="adm-reader-quote">{a.text}</blockquote>
                <form phx-submit="comment" phx-target={@myself} class="adm-reader-comment">
                  <input type="hidden" name="key" value={a.key} />
                  <input type="hidden" name="version" value={a.version} />
                  <textarea
                    name="comment"
                    rows="2"
                    class="adm-input adm-input--small"
                    aria-label="Comment"
                    placeholder="Comment…"
                  >{a.comment}</textarea>
                  <div class="adm-form-actions">
                    <button type="submit" class="adm-btn adm-btn--small">Save comment</button>
                    <button
                      type="button"
                      phx-click="delete"
                      phx-value-key={a.key}
                      phx-value-version={a.version}
                      phx-target={@myself}
                      class="adm-btn adm-btn--small adm-btn--quiet adm-act-danger"
                      data-confirm="Delete this annotation in Zotero?"
                    >
                      Delete
                    </button>
                  </div>
                </form>
              </li>
            </ol>
          </section>

          <section id="reader-notes" class="adm-reader-box">
            <h3 class="adm-outline-label">Notes<span class="adm-count">{@note_count}</span></h3>
            <ol id="notes" phx-update="stream" class="adm-reader-list">
              <li :for={{id, n} <- @streams.notes} id={id} class="adm-reader-note">{n.text}</li>
            </ol>
            <.form
              :if={@doc.notes_key}
              for={@note_form}
              id="note-form"
              phx-submit="add_note"
              phx-target={@myself}
              class="adm-reader-annotate"
            >
              <.input
                field={@note_form[:text]}
                type="textarea"
                rows="4"
                class="adm-input adm-input--small"
                placeholder="A note on this reading…"
                aria-label="New note"
              />
              <div class="adm-form-actions">
                <button type="submit" class="adm-btn adm-btn--small adm-btn--primary">
                  Add note
                </button>
              </div>
            </.form>
          </section>
        </aside>
      </div>
    </div>
    """
  end
end
