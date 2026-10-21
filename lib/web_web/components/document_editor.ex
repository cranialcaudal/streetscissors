defmodule WebWeb.DocumentEditor do
  @moduledoc """
  The admin's document editor: CodeMirror over a form field
  (`assets/js/document_editor.js`, `assets/js/editor/core.js`).

  **Source-first.** The text is the file's own, edited in place and never
  re-serialised, so a post saved from here differs from what Obsidian saved
  only where something was typed. Headings, task boxes and embeds are drawn
  over the text in Live mode; the text underneath stays as it is.

  **The contract with the page.** `document_editor/1` renders a real
  `<textarea name={name}>`, and every edit is written into it with an `input`
  event, so the host's form, `to_form/2`, `phx-change`/`phx-submit` and its
  tests work as with a plain textarea. The textarea is `phx-update="ignore"`:
  the page never patches it, so a reply can't put older text back. When the
  server changes the text itself (the version on disk was taken), it says so
  with `set/3`.

  **Completion.** A host calls `attach/1` in `mount/3`, and the editor's
  `[[`, `![[`, `related:` and `keywords:` completions are answered from
  `Web.Editor.Complete` without the host writing a clause for it.
  """
  use Phoenix.Component

  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3]

  attr :id, :string, required: true, doc: "the editor's id; the textarea is `<id>-input`"
  attr :name, :string, required: true, doc: "the form field's name, as a plain textarea had it"
  attr :value, :string, default: ""
  attr :label, :string, default: "Document"

  attr :complete, :string,
    default: "none",
    values: ~w(none blog fitness),
    doc: "what `[[` offers (Web.Editor.Complete)"

  attr :media, :boolean, default: false, doc: "a drawer of images and film to insert"
  attr :hidden, :boolean, default: false
  attr :debounce, :string, default: "400"
  attr :size, :string, default: "tall", values: ~w(tall short)

  def document_editor(assigns) do
    ~H"""
    <div class={["adm-ed", @size == "short" && "adm-ed--short"]} id={"#{@id}-shell"} hidden={@hidden}>
      <.live_component
        :if={@media}
        module={WebWeb.DocumentEditor.Media}
        id={"#{@id}-media"}
        editor={@id}
      />
      <textarea
        id={"#{@id}-input"}
        name={@name}
        class="adm-input adm-input--code adm-ed-input"
        aria-label={@label}
        phx-update="ignore"
        phx-debounce={@debounce}
        hidden={@hidden}
      >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      <div
        id={@id}
        class="adm-ed-host"
        phx-hook="DocumentEditor"
        phx-update="ignore"
        data-input={"#{@id}-input"}
        data-complete={@complete}
        data-label={@label}
        data-media={@media && "true"}
      >
      </div>
    </div>
    """
  end

  @doc "Answers the editors' completion requests on this LiveView. Call in `mount/3`."
  def attach(socket), do: attach_hook(socket, :document_editor, :handle_event, &handle_event/3)

  @doc "Replaces the editor's text (and its field's) with `content`."
  def set(socket, id, content), do: push_event(socket, "editor:set", %{id: id, content: content})

  defp handle_event("editor_complete", params, socket) do
    items =
      Web.Editor.Complete.items(
        to_string(params["q"] || ""),
        to_string(params["kind"] || "link"),
        to_string(params["scope"] || "none")
      )

    {:halt, %{items: items}, socket}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
