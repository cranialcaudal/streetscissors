// The DocumentEditor hook: mounts the admin's editor (assets/js/editor/core.js)
// over a form field. WebWeb.DocumentEditor renders the markup this expects:
//
//   <div class="adm-ed">
//     <textarea id="X-input" name="…" phx-update="ignore">   the real field
//     <div id="X" phx-hook="DocumentEditor" phx-update="ignore" data-input="X-input">
//
// Every edit is written into the textarea and announced with a bubbling
// `input` event, so the form's own phx-change (and its debounce) runs exactly
// as it did for a plain textarea, and nothing about to_form or the tests
// changes. The textarea is ignored by LiveView's patches, so a slow reply can
// never put older text back under the cursor; once CodeMirror is in, CSS
// (`:has(.cm-editor)`) hides it. Without JavaScript it is simply the editor.
//
// Everything the hook changes lives inside the ignored div (the bar, the
// outline, the live and zen states), because LiveView resets the attributes
// of what it renders.
//
// From the server: push_event("editor:set", %{id: "X", content: text})
// replaces the text (taking the version on disk, opening another draft), and
// push_event("editor:insert", %{id: "X", text: …}) types at the cursor (the
// media drawer).
//
// The editor code and the vendored CodeMirror are fetched on first mount, as
// a separate chunk: public pages never load them.

const MODE_KEY = "document-editor-live"

const remembered = () => {
  try { return localStorage.getItem(MODE_KEY) === "1" } catch (_) { return false }
}
const remember = (on) => {
  try { localStorage.setItem(MODE_KEY, on ? "1" : "0") } catch (_) {}
}

export const DocumentEditor = {
  async mounted() {
    this.input = document.getElementById(this.el.dataset.input)
    if (!this.input) return

    const { createEditor } = await import("./editor/core.js")
    if (this.gone) return

    // The frame holds everything the hook draws: the bar, the outline, the
    // text and the count. Live and zen are classes on it.
    this.frame = document.createElement("div")
    this.frame.className = "adm-ed-frame"
    this.bar = this.makeBar()
    const host = document.createElement("div")
    host.className = "adm-ed-cm"
    this.outlineEl = document.createElement("nav")
    this.outlineEl.className = "adm-ed-outline"
    this.outlineEl.setAttribute("aria-label", "Outline")
    this.outlineEl.hidden = true
    this.statusEl = document.createElement("p")
    this.statusEl.className = "adm-ed-status"
    this.statusEl.setAttribute("aria-live", "polite")
    this.frame.append(this.bar, this.outlineEl, host, this.statusEl)
    this.el.replaceChildren(this.frame)

    this.editor = createEditor({
      parent: host,
      doc: this.input.value,
      scope: this.el.dataset.complete || "none",
      label: this.el.dataset.label,
      live: remembered(),
      onChange: (text) => {
        this.input.value = text
        this.input.dispatchEvent(new Event("input", { bubbles: true }))
        this.refreshPanel()
      },
      ask: (q, kind, scope) =>
        new Promise((resolve) => {
          this.pushEvent("editor_complete", { q, kind, scope }, (reply) => resolve((reply && reply.items) || []))
        }),
      onSubmit: () => this.input.form && this.input.form.requestSubmit(),
      onLeave: () => this.setZen(false),
    })

    this.frame.classList.toggle("is-live", this.editor.live)
    this.pressed("live", this.editor.live)
    this.refreshPanel(true)

    // Sync once more as the form goes, in case the last keystroke and the
    // submit share a tick.
    this.onSubmitCapture = () => { this.input.value = this.editor.view.state.doc.toString() }
    if (this.input.form) this.input.form.addEventListener("submit", this.onSubmitCapture, true)

    this.onCommand = (e) => this.command(e.detail && e.detail.cmd)
    this.onInsert = (e) => e.detail && e.detail.text && this.editor.insert(e.detail.text)
    this.el.addEventListener("editor:command", this.onCommand)
    this.el.addEventListener("editor:insert", this.onInsert)

    // The media drawer's Insert: its words field, then the drawer makes the
    // Markdown (WebWeb.DocumentEditor.Media). Enter in a words field inserts
    // rather than submitting the page's form.
    this.onMedia = (e) => {
      const { fields, words } = e.detail || {}
      const box = words && document.getElementById(words)
      this.pushEventTo(`#${this.el.id}-media`, "insert", { ...(fields || {}), words: box ? box.value : "" })
    }
    this.onMediaKey = (e) => {
      if (e.key !== "Enter" || !e.target.matches("[data-media-words]")) return
      e.preventDefault()
      const button = e.target.parentElement.querySelector("button")
      if (button) button.click()
    }
    this.el.addEventListener("editor:media", this.onMedia)
    this.mediaEl = document.getElementById(`${this.el.id}-media`)
    if (this.mediaEl) this.mediaEl.addEventListener("keydown", this.onMediaKey)

    this.handleEvent("editor:set", ({ id, content }) => {
      if (id === this.el.id && this.editor) {
        this.editor.setText(content)
        this.input.value = content
      }
    })
    this.handleEvent("editor:insert", ({ id, text }) => {
      if (id === this.el.id && this.editor && text) this.editor.insert(text)
    })

    // A form that says it holds unsaved work (data-dirty="true") asks before
    // the tab closes. The blog editor's form sets it.
    this.onUnload = (e) => {
      if (this.input.form && this.input.form.dataset.dirty === "true") {
        e.preventDefault()
        e.returnValue = ""
      }
    }
    window.addEventListener("beforeunload", this.onUnload)
  },

  // The bar: icons are the site's own heroicon classes (on the app.css
  // allowlist), so the bar looks like every other admin button.
  makeBar() {
    const bar = document.createElement("div")
    bar.className = "adm-ed-bar"
    bar.setAttribute("role", "toolbar")
    bar.setAttribute("aria-label", "Editor")
    const tools = [
      ["live", "hero-eye", "Live", "Show the page's shape (the text is unchanged)"],
      ["outline", "hero-bars-3-bottom-left", "Outline", "Headings, to jump between"],
      ["zen", "hero-arrows-pointing-out", "Zen", "The text alone; Escape to leave"],
    ]
    if (this.el.dataset.media) tools.push(["media", "hero-photo", "Media", "Images and film to insert"])
    for (const [cmd, icon, label, title] of tools) {
      const b = document.createElement("button")
      b.type = "button"
      b.className = `adm-ed-tool adm-ed-tool--${cmd}`
      b.title = title
      b.dataset.cmd = cmd
      if (cmd !== "media") b.setAttribute("aria-pressed", "false")
      const i = document.createElement("span")
      i.className = `${icon} adm-ed-icon`
      i.setAttribute("aria-hidden", "true")
      const t = document.createElement("span")
      t.textContent = label
      b.append(i, t)
      b.addEventListener("click", () => this.command(cmd))
      bar.appendChild(b)
    }
    return bar
  },

  pressed(cmd, on) {
    const b = this.bar.querySelector(`[data-cmd="${cmd}"]`)
    if (b) b.setAttribute("aria-pressed", on ? "true" : "false")
  },

  command(cmd) {
    if (!this.editor) return
    if (cmd === "live") {
      const on = !this.editor.live
      this.editor.setLive(on)
      this.frame.classList.toggle("is-live", on)
      this.pressed("live", on)
      remember(on)
    } else if (cmd === "outline") {
      this.outlineEl.hidden = !this.outlineEl.hidden
      this.pressed("outline", !this.outlineEl.hidden)
      this.refreshPanel(true)
    } else if (cmd === "zen") {
      this.setZen(!this.frame.classList.contains("is-zen"))
    } else if (cmd === "media") {
      // The drawer is a LiveComponent beside the editor (WebWeb.DocumentEditor.Media).
      this.pushEventTo(`#${this.el.id}-media`, "toggle", {})
    } else {
      this.editor.command(cmd)
    }
  },

  setZen(on) {
    const was = this.frame.classList.contains("is-zen")
    this.frame.classList.toggle("is-zen", on)
    this.pressed("zen", on)
    document.documentElement.classList.toggle("adm-zen-open", on)
    if (on) this.editor.view.focus()
    return was && !on
  },

  // The outline and the word count, at most every quarter second.
  refreshPanel(now) {
    clearTimeout(this.panelTimer)
    const draw = () => {
      if (!this.editor) return
      const { words, minutes } = this.editor.counts()
      this.statusEl.textContent = `${words.toLocaleString()} words · ${minutes} min read`
      if (this.outlineEl.hidden) return
      const items = this.editor.outline()
      const list = document.createElement("ol")
      for (const h of items) {
        const li = document.createElement("li")
        li.className = `adm-ed-outline-h${h.level}`
        const b = document.createElement("button")
        b.type = "button"
        b.textContent = h.text
        b.addEventListener("click", () => this.editor.jump(h.pos))
        li.appendChild(b)
        list.appendChild(li)
      }
      if (!items.length) {
        const li = document.createElement("li")
        li.textContent = "No headings yet."
        list.appendChild(li)
      }
      this.outlineEl.replaceChildren(list)
    }
    if (now) draw()
    else this.panelTimer = setTimeout(draw, 250)
  },

  destroyed() {
    this.gone = true
    clearTimeout(this.panelTimer)
    if (this.onUnload) window.removeEventListener("beforeunload", this.onUnload)
    if (this.onSubmitCapture && this.input.form) this.input.form.removeEventListener("submit", this.onSubmitCapture, true)
    document.documentElement.classList.remove("adm-zen-open")
    if (this.mediaEl) this.mediaEl.removeEventListener("keydown", this.onMediaKey)
    if (this.editor) this.editor.destroy()
  },
}
