// An EPUB read with epub.js (assets/vendor/epub.js), for the ZoteroReader hook.
//
// One section at a time, scrolled, with Previous and Next. The book's own
// scripts never run (epub.js leaves `allow-scripts` off its iframe's sandbox).
//
// Positions are Zotero's: a FragmentSelector holding the selection's EPUB
// CFI, sort index SSSSS|CCCCCCCC (section, offset of the first selected
// character in the section's text). Highlights are drawn by epub.js
// (marks-pane, an SVG over the book) in the page around it, so the site's
// classes colour them.

import ePub from "../../vendor/epub.js"
import { pad, debounce, flatten, textOffset } from "./util.js"

const CFI = "http://www.idpf.org/epub/linking/cfi/epub-cfi.html"

export async function open({ el, src, onSelect }) {
  const bar = document.createElement("div")
  bar.className = "adm-reader-epub-bar"
  const prev = button("Previous")
  const where = document.createElement("span")
  where.className = "adm-outline-label"
  const next = button("Next")
  bar.append(prev, where, next)
  const box = document.createElement("div")
  box.className = "adm-reader-epub"
  el.replaceChildren(bar, box)

  const book = ePub(src, { openAs: "epub" })
  await book.ready
  const rendition = book.renderTo(box, {
    width: "100%",
    height: "100%",
    flow: "scrolled-doc",
    allowScriptedContent: false,
  })

  let annotations = []
  let shown = [] // [cfi, type] drawn now

  rendition.on("selected", (cfiRange, contents) => {
    const range = contents.range(cfiRange)
    const text = flatten(range && range.toString())
    if (!text) return
    const offset = textOffset(contents.document.body, range.startContainer, range.startOffset)
    onSelect({
      text,
      position: { type: "FragmentSelector", conformsTo: CFI, value: cfiRange },
      sort_index: `${pad(contents.sectionIndex || 0, 5)}|${pad(Math.min(offset, 99999999), 8)}`,
      page_label: "",
    })
  })

  // A click in the book that leaves nothing selected clears the selection.
  rendition.hooks.content.register((contents) => {
    contents.document.addEventListener("mouseup", debounce(() => {
      const s = contents.window.getSelection()
      if (!s || s.isCollapsed) onSelect(null)
    }, 50))
  })

  rendition.on("relocated", (location) => {
    const section = location && location.start && location.start.index
    where.textContent = typeof section === "number" ? `Section ${section + 1} of ${book.spine.length}` : ""
  })

  prev.addEventListener("click", () => rendition.prev())
  next.addEventListener("click", () => rendition.next())

  await rendition.display()

  function draw() {
    for (const [cfi, type] of shown) rendition.annotations.remove(cfi, type)
    shown = []
    for (const a of annotations) {
      const cfi = a.position && a.position.value
      if (!cfi || !cfi.startsWith("epubcfi(")) continue
      const type = a.type === "underline" ? "underline" : "highlight"
      // marks-pane takes one class (classList.add), so the colour is the
      // class and the kind of mark an attribute.
      rendition.annotations[type](cfi, { key: a.key }, () => {}, `adm-ann--${a.color_name || "other"}`, { "data-mark": type })
      shown.push([cfi, type])
    }
  }

  return {
    setAnnotations(list) {
      annotations = list
      draw()
    },
    async jump(key) {
      const a = annotations.find((x) => x.key === key)
      if (a && a.position && a.position.value) await rendition.display(a.position.value)
    },
    clearSelection() {
      for (const c of rendition.getContents()) {
        const s = c.window.getSelection()
        if (s) s.removeAllRanges()
      }
    },
    destroy() {
      book.destroy()
    },
  }
}

function button(label) {
  const b = document.createElement("button")
  b.type = "button"
  b.className = "adm-btn adm-btn--small adm-btn--quiet"
  b.textContent = label
  return b
}
