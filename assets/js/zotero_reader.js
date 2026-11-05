// The ZoteroReader hook: a Zotero PDF or EPUB, read and annotated in the
// admin (WebWeb.AdminLive.ZoteroReaderComponent renders the element it owns,
// on the reading page or in the workbench's first panel:
// <div id="reader-KEY" phx-hook="ZoteroReader" phx-update="ignore"
//      data-kind="pdf|epub" data-src="/admin/zotero/file/KEY/MD5">).
//
// The viewer (reader/pdf_view.js with PDF.js, reader/epub_view.js with
// epub.js) is fetched on first mount as its own chunk, so no other page
// loads either library. A hook destroyed while its file is still loading
// stops the load (an AbortSignal) rather than finishing it for no one.
//
// To the component (pushEventTo, so it reaches the reader wherever it is
// rendered): "reader_ready" once the document is open (the reply is the
// annotations to draw), and "selection" as the reader selects text, with
// where it is in Zotero's terms (position, sort index, page label), or with
// no text when the selection is gone.
// From the server: "reader:annotations" (redraw), "reader:jump" (scroll to
// one), "reader:clear_selection" (after a highlight is saved).

const failed = (where) => (error) => console.warn(`[ZoteroReader] ${where}`, error)

export const ZoteroReader = {
  async mounted() {
    const { kind, src } = this.el.dataset
    this.abort = new AbortController()
    try {
      const view = kind === "epub"
        ? await import("./reader/epub_view.js")
        : await import("./reader/pdf_view.js")
      if (this.gone) return
      this.view = await view.open({
        el: this.el,
        src,
        signal: this.abort.signal,
        onSelect: (selection) => this.pushEventTo(this.el, "selection", selection || { text: "" }),
      })
    } catch (error) {
      if (this.gone) return
      const p = document.createElement("p")
      p.className = "adm-help"
      p.setAttribute("role", "alert")
      p.textContent = `Could not open the file: ${error && error.message ? error.message : error}`
      this.el.replaceChildren(p)
      return
    }
    if (this.gone) return this.close()

    const guard = (where, fn) => (payload) => {
      try {
        const out = fn(payload)
        if (out && typeof out.catch === "function") out.catch(failed(where))
      } catch (error) {
        failed(where)(error)
      }
    }
    this.handleEvent("reader:annotations", guard("annotations", ({ annotations }) => this.view.setAnnotations(annotations || [])))
    this.handleEvent("reader:jump", guard("jump", ({ key }) => this.view.jump(key)))
    this.handleEvent("reader:clear_selection", guard("clear_selection", () => this.view.clearSelection()))
    this.pushEventTo(this.el, "reader_ready", {}, guard("reader_ready", (reply) => this.view.setAnnotations((reply && reply.annotations) || [])))
  },

  close() {
    const view = this.view
    this.view = null
    if (view) Promise.resolve(view.destroy()).catch(failed("destroy"))
  },

  destroyed() {
    this.gone = true
    if (this.abort) this.abort.abort()
    this.close()
  },
}
