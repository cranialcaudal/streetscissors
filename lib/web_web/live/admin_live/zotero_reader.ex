defmodule WebWeb.AdminLive.ZoteroReader do
  @moduledoc """
  A Zotero document read in the admin: its PDF or EPUB beside its annotations and notes, all written back to Zotero.

  `/admin/zotero/:item` opens an item's first readable attachment (`?a=`
  picks another; `?back=` is the admin page to return to, usually the draft
  the reading is for). Selecting text in the document offers a highlight or
  an underline in one of Zotero's colours, with a comment; each annotation
  can be commented, jumped to, or deleted, and a note can be added to the
  item. Everything goes through `Web.Writing.Zotero.Reader`, so it is in
  Zotero after a sync, and what was made in Zotero is here.

  The document is drawn by the `ZoteroReader` hook (`assets/js/zotero_reader.js`:
  PDF.js for a PDF, epub.js for an EPUB) inside an element it owns
  (`phx-update="ignore"`); the server tells it the annotations to draw
  (`reader:annotations`) and where to jump (`reader:jump`).
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Writing.Zotero.Reader

  def mount(%{"item" => key}, _session, socket) do
    if Reader.key?(key) do
      {:ok,
       socket
       |> assign(
         page_title: "Reading | Admin",
         item_key: key,
         doc: nil,
         attachment: nil,
         error: nil,
         selection: nil,
         back: "/admin/blog",
         annotation_count: 0,
         marks: [],
         note_count: 0,
         highlight_form: to_form(%{"comment" => "", "color" => "yellow"}, as: :highlight),
         note_form: to_form(%{"text" => ""}, as: :note)
       )
       |> stream(:annotations, [], dom_id: &"ann-#{&1.key}")
       |> stream(:notes, [], dom_id: &"note-#{&1.key}")}
    else
      {:ok,
       socket
       |> put_flash(:error, "That is not a Zotero item.")
       |> push_navigate(to: ~p"/admin/blog")}
    end
  end

  def handle_params(params, _uri, socket) do
    socket = assign(socket, back: safe_back(params["back"]))

    socket =
      if connected?(socket) do
        key = socket.assigns.item_key
        wanted = params["a"]

        start_async(socket, :load, fn ->
          with {:ok, doc} <- Reader.document(key) do
            attachment =
              Enum.find(doc.attachments, &(&1.key == wanted)) || List.first(doc.attachments)

            {:ok, doc, attachment, load_annotations(attachment), load_notes(doc.notes_key)}
          end
        end)
      else
        socket
      end

    {:noreply, socket}
  end

  # A return address inside the admin, never somewhere else.
  defp safe_back(back) when is_binary(back) do
    if String.starts_with?(back, "/admin/") and not String.contains?(back, ["//", "\\"]),
      do: back,
      else: "/admin/blog"
  end

  defp safe_back(_), do: "/admin/blog"

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

  def handle_async(:load, {:ok, {:ok, doc, attachment, annotations, notes}}, socket) do
    {:noreply,
     socket
     |> assign(
       doc: doc,
       attachment: attachment,
       error: if(is_nil(attachment), do: "This item has no PDF or EPUB stored in Zotero."),
       page_title: "#{doc.item.title} | Reading | Admin",
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

  # ── From the document ─────────────────────────────────────────────────

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
           |> put_flash(:info, "Saved to Zotero.")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Not saved: " <> describe(reason))}
      end
    else
      {:noreply, put_flash(socket, :error, "Select some text in the document first.")}
    end
  end

  def handle_event("comment", %{"key" => key, "version" => version} = params, socket) do
    changes = Map.take(params, ~w(comment color))

    case Reader.update_annotation(key, version, changes) do
      :ok ->
        {:noreply, socket |> reload_annotations() |> put_flash(:info, "Saved to Zotero.")}

      {:error, reason} ->
        {:noreply,
         socket |> reload_annotations() |> put_flash(:error, "Not saved: " <> describe(reason))}
    end
  end

  def handle_event("delete", %{"key" => key, "version" => version}, socket) do
    case Reader.delete_annotation(key, version) do
      :ok ->
        {:noreply, socket |> reload_annotations() |> put_flash(:info, "Deleted in Zotero.")}

      {:error, reason} ->
        {:noreply,
         socket |> reload_annotations() |> put_flash(:error, "Not deleted: " <> describe(reason))}
    end
  end

  def handle_event("jump", %{"key" => key}, socket) do
    {:noreply, push_event(socket, "reader:jump", %{key: key})}
  end

  # ── Notes ─────────────────────────────────────────────────────────────

  def handle_event("add_note", %{"note" => %{"text" => text}}, socket) do
    case socket.assigns.doc && socket.assigns.doc.notes_key do
      nil ->
        {:noreply, put_flash(socket, :error, "A standalone file has no item to hold notes.")}

      key ->
        case Reader.create_note(key, text) do
          :ok ->
            {:noreply,
             socket
             |> assign(note_form: to_form(%{"text" => ""}, as: :note))
             |> put_notes(load_notes(key))
             |> put_flash(:info, "Note saved to Zotero.")}

          {:error, :blank} ->
            {:noreply, put_flash(socket, :error, "Write the note first.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Not saved: " <> describe(reason))}
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

  def render(assigns) do
    ~H"""
    <.page_head
      slug="Writing / Zotero / Read"
      title={if @doc, do: @doc.item.title, else: "Opening…"}
    >
      <:lede :if={@doc}>
        {@doc.item.authors}{if @doc.item.year, do: " (#{@doc.item.year})"}
        <span :if={@attachment}>· {@attachment.title}</span>
      </:lede>
      <:actions>
        <.link navigate={@back} class="adm-btn adm-btn--quiet">Back</.link>
        <a href={"zotero://select/library/items/#{@item_key}"} class="adm-btn adm-btn--quiet">
          Open in Zotero
        </a>
      </:actions>
    </.page_head>

    <p :if={@error} id="reader-error" class="adm-help" role="alert">{@error}</p>
    <p :if={!@doc and !@error} id="reader-loading" class="adm-help">Asking Zotero…</p>

    <nav
      :if={@doc && length(@doc.attachments) > 1}
      id="reader-attachments"
      class="adm-wb-bar"
      aria-label="Files of this item"
    >
      <.link
        :for={att <- @doc.attachments}
        patch={~p"/admin/zotero/#{@item_key}?#{[a: att.key, back: @back]}"}
        class={[
          "adm-btn adm-btn--small adm-btn--quiet",
          @attachment && att.key == @attachment.key && "is-active"
        ]}
      >
        {att.title} ({att.kind |> to_string() |> String.upcase()})
      </.link>
    </nav>

    <div :if={@attachment} class="adm-reader">
      <div
        id={"reader-#{@attachment.key}"}
        class="adm-reader-view"
        phx-hook="ZoteroReader"
        phx-update="ignore"
        data-kind={@attachment.kind}
        data-src={file_url(@attachment)}
      >
        <p class="adm-help">Opening the {@attachment.kind |> to_string() |> String.upcase()}…</p>
      </div>

      <aside class="adm-reader-side" aria-label="Annotations and notes">
        <section id="reader-selection" class="adm-panel adm-reader-box">
          <h2 class="adm-panel-title">Selection</h2>
          <p :if={!@selection} class="adm-help">
            Select text in the document to highlight or underline it.
          </p>
          <.form
            :if={@selection}
            for={@highlight_form}
            id="annotate-form"
            phx-submit="annotate"
            class="adm-reader-annotate"
          >
            <blockquote class="adm-reader-quote">{@selection["text"]}</blockquote>
            <fieldset class="adm-reader-colors">
              <legend class="adm-outline-label">Colour</legend>
              <label :for={{name, _hex} <- Reader.colors()} class="adm-reader-color">
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
            <.input
              field={@highlight_form[:comment]}
              type="textarea"
              rows="3"
              class="adm-input adm-input--small"
              placeholder="A comment (optional)"
              aria-label="Comment on the selection"
            />
            <div class="adm-form-actions">
              <button type="submit" name="type" value="highlight" class="adm-btn adm-btn--primary">
                Highlight
              </button>
              <button type="submit" name="type" value="underline" class="adm-btn">
                Underline
              </button>
            </div>
          </.form>
        </section>

        <section id="reader-annotations" class="adm-panel adm-reader-box">
          <h2 class="adm-panel-title">
            Annotations<span class="adm-count">{@annotation_count}</span>
          </h2>
          <p :if={@annotation_count == 0 and @doc} class="adm-help">None yet.</p>
          <ol id="annotations" phx-update="stream" class="adm-reader-list">
            <li :for={{id, a} <- @streams.annotations} id={id} class="adm-reader-ann">
              <div class="adm-reader-ann-head">
                <span class={["adm-reader-swatch", "adm-ann--#{a.color_name}"]} aria-hidden="true"></span>
                <span class="adm-outline-label">{a.type}<span :if={where(a)}> · {where(a)}</span></span>
                <button
                  type="button"
                  phx-click="jump"
                  phx-value-key={a.key}
                  class="adm-btn adm-btn--small adm-btn--quiet"
                >
                  Show
                </button>
              </div>
              <blockquote :if={a.text != ""} class="adm-reader-quote">{a.text}</blockquote>
              <form phx-submit="comment" class="adm-reader-comment">
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

        <section :if={@doc} id="reader-notes" class="adm-panel adm-reader-box">
          <h2 class="adm-panel-title">Notes<span class="adm-count">{@note_count}</span></h2>
          <p :if={is_nil(@doc.notes_key)} class="adm-help">
            A standalone file has no item to hold notes: give it a parent item in Zotero first.
          </p>
          <ol id="notes" phx-update="stream" class="adm-reader-list">
            <li :for={{id, n} <- @streams.notes} id={id} class="adm-reader-note">{n.text}</li>
          </ol>
          <.form
            :if={@doc.notes_key}
            for={@note_form}
            id="note-form"
            phx-submit="add_note"
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
              <button type="submit" class="adm-btn adm-btn--small adm-btn--primary">Add note</button>
            </div>
          </.form>
        </section>
      </aside>
    </div>
    """
  end
end
