// The ZoteroReader hook: a Zotero PDF or EPUB, read and annotated in the
// admin (WebWeb.AdminLive.ZoteroReader renders the element it owns:
// <div id="reader-KEY" phx-hook="ZoteroReader" phx-update="ignore"
//      data-kind="pdf|epub" data-src="/admin/zotero/file/KEY/MD5">).
//
// The viewer (reader/pdf_view.js with PDF.js, reader/epub_view.js with
// epub.js) is fetched on first mount as its own chunk, so no other page
// loads either library.
//
// To the server: "reader_ready" once the document is open (the reply is the
// annotations to draw), and "selection" as the reader selects text, with
// where it is in Zotero's terms (position, sort index, page label), or with
// no text when the selection is gone.
// From the server: "reader:annotations" (redraw), "reader:jump" (scroll to
// one), "reader:clear_selection" (after a highlight is saved).

export const ZoteroReader = {
  async mounted() {
    const { kind, src } = this.el.dataset
    try {
      const view = kind === "epub"
        ? await import("./reader/epub_view.js")
        : await import("./reader/pdf_view.js")
      if (this.gone) return
      this.view = await view.open({
        el: this.el,
        src,
        onSelect: (selection) => this.pushEvent("selection", selection || { text: "" }),
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
    if (this.gone) return this.view.destroy()

    this.handleEvent("reader:annotations", ({ annotations }) => this.view.setAnnotations(annotations || []))
    this.handleEvent("reader:jump", ({ key }) => this.view.jump(key))
    this.handleEvent("reader:clear_selection", () => this.view.clearSelection())
    this.pushEvent("reader_ready", {}, (reply) => this.view.setAnnotations((reply && reply.annotations) || []))
  },

  destroyed() {
    this.gone = true
    if (this.view) this.view.destroy()
  },
}
