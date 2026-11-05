// A PDF read with PDF.js (assets/vendor/pdf.mjs), for the ZoteroReader hook.
//
// Pages are laid out at the width of the reader and drawn as they come near
// the view (an IntersectionObserver), each a canvas under a transparent text
// layer for selecting, with the annotations drawn between the two. Far pages
// are let go again, so a long book does not hold every page in memory.
//
// Positions are Zotero's: rects in PDF points ([x1, y1, x2, y2], origin at the
// page's bottom left), sort index PPPPP|OOOOOO|TTTTT (page, offset of the
// first selected character in the page's text, distance from the top).

import * as pdfjs from "../../vendor/pdf.mjs"
import workerSource from "../../vendor/pdf-worker.txt"
import { pad, debounce, flatten, textOffset, markClass } from "./util.js"

const KEEP = 24 // pages kept drawn at once

let port = null
// The worker runs from a blob of its own source: only app.js and its chunks
// are served, so it has no address of its own.
function worker() {
  if (!port) {
    const url = URL.createObjectURL(new Blob([workerSource], { type: "text/javascript" }))
    port = new Worker(url, { type: "module" })
  }
  return port
}

export async function open({ el, src, onSelect }) {
  pdfjs.GlobalWorkerOptions.workerPort = worker()

  const task = pdfjs.getDocument({ url: src, isEvalSupported: false, enableXfa: false })
  const doc = await task.promise
  const labels = await doc.getPageLabels().catch(() => null)
  const first = await doc.getPage(1)
  const base = first.getViewport({ scale: 1 })

  const holder = document.createElement("div")
  holder.className = "adm-reader-pages"
  el.replaceChildren(holder)

  let scale = fitScale()
  let annotations = []
  const drawn = [] // pages drawn, oldest first
  const pages = []

  function fitScale() {
    const width = Math.max(280, el.clientWidth - 32)
    return Math.min(2.5, width / base.width)
  }

  function placeholder(p) {
    const w = (p.width || base.width) * scale
    const h = (p.height || base.height) * scale
    p.el.style.width = `${w}px`
    p.el.style.height = `${h}px`
  }

  for (let i = 0; i < doc.numPages; i++) {
    const pageEl = document.createElement("div")
    pageEl.className = "adm-reader-page"
    pageEl.dataset.index = String(i)
    pageEl.setAttribute("aria-label", `Page ${labels?.[i] || i + 1}`)
    holder.appendChild(pageEl)
    const p = { index: i, el: pageEl, state: "blank" }
    placeholder(p)
    pages.push(p)
  }

  const seen = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) draw(pages[Number(e.target.dataset.index)])
  }, { root: el, rootMargin: "1200px 0px" })
  pages.forEach((p) => seen.observe(p.el))

  async function draw(p) {
    if (p.state !== "blank") return p.ready
    p.state = "drawing"
    p.ready = (async () => {
      const page = p.page || (p.page = await doc.getPage(p.index + 1))
      const viewport = page.getViewport({ scale })
      p.viewport = viewport
      p.width = viewport.width / scale
      p.height = viewport.height / scale
      p.el.style.width = `${viewport.width}px`
      p.el.style.height = `${viewport.height}px`
      // What PDF.js's text layer sizes itself by.
      p.el.style.setProperty("--total-scale-factor", String(viewport.scale))
      p.el.style.setProperty("--scale-round-x", "1px")
      p.el.style.setProperty("--scale-round-y", "1px")

      const ratio = window.devicePixelRatio || 1
      const canvas = document.createElement("canvas")
      canvas.width = Math.floor(viewport.width * ratio)
      canvas.height = Math.floor(viewport.height * ratio)
      canvas.className = "adm-reader-canvas"
      const marks = document.createElement("div")
      marks.className = "adm-reader-marks"
      const text = document.createElement("div")
      text.className = "adm-reader-text"
      p.el.replaceChildren(canvas, marks, text)
      p.marks = marks
      p.text = text

      p.task = page.render({
        canvasContext: canvas.getContext("2d"),
        viewport,
        transform: ratio === 1 ? null : [ratio, 0, 0, ratio, 0, 0],
      })
      await p.task.promise
      const layer = new pdfjs.TextLayer({ textContentSource: page.streamTextContent(), container: text, viewport })
      await layer.render()
      // PDF.js's own trick: a block after the text, so a drag past the last
      // line does not select the whole page.
      const end = document.createElement("div")
      end.className = "adm-reader-text-end"
      text.appendChild(end)
      p.state = "drawn"
      drawMarks(p)
      drawn.push(p)
      forget()
    })().catch((error) => {
      if (error && error.name === "RenderingCancelledException") return
      p.state = "blank"
      throw error
    })
    return p.ready
  }

  // Lets go of the pages drawn longest ago that are out of sight.
  function forget() {
    const top = el.scrollTop
    const bottom = top + el.clientHeight
    while (drawn.length > KEEP) {
      const i = drawn.findIndex((p) => p.el.offsetTop + p.el.offsetHeight < top - 2000 || p.el.offsetTop > bottom + 2000)
      if (i < 0) break
      const [p] = drawn.splice(i, 1)
      blank(p)
    }
  }

  function blank(p) {
    if (p.task) p.task.cancel()
    p.state = "blank"
    p.el.replaceChildren()
    p.marks = p.text = p.viewport = null
    placeholder(p)
  }

  // A rect in PDF points, as [left, top, width, height] in the page's pixels
  // (PDF.js 6 converts points only).
  function toView(viewport, [x1, y1, x2, y2]) {
    const [ax, ay] = viewport.convertToViewportPoint(x1, y1)
    const [bx, by] = viewport.convertToViewportPoint(x2, y2)
    return [Math.min(ax, bx), Math.min(ay, by), Math.abs(bx - ax), Math.abs(by - ay)]
  }

  function drawMarks(p) {
    if (!p.marks || !p.viewport) return
    const nodes = []
    for (const a of annotations) {
      const pos = a.position || {}
      if (pos.pageIndex !== p.index || !Array.isArray(pos.rects)) continue
      for (const rect of pos.rects) {
        const [left, top, width, height] = toView(p.viewport, rect)
        const m = document.createElement("div")
        m.className = markClass(a)
        m.dataset.key = a.key
        m.style.left = `${left}px`
        m.style.top = `${top}px`
        m.style.width = `${width}px`
        m.style.height = `${height}px`
        nodes.push(m)
      }
    }
    p.marks.replaceChildren(...nodes)
  }

  // ── Selecting ─────────────────────────────────────────────────────────

  const pageOf = (node) => {
    const elNode = node && (node.nodeType === 1 ? node : node.parentElement)
    const pageEl = elNode && elNode.closest(".adm-reader-page")
    return pageEl && el.contains(pageEl) ? pages[Number(pageEl.dataset.index)] : null
  }

  const report = debounce(() => {
    const sel = document.getSelection()
    if (!sel || sel.isCollapsed || !sel.rangeCount) return
    const range = sel.getRangeAt(0)
    const p = pageOf(range.startContainer)
    if (!p || !p.viewport || !p.text) return

    const box = p.el.getBoundingClientRect()
    const rects = []
    for (const r of range.getClientRects()) {
      if (r.width < 1 || r.height < 1) continue
      const cx = r.left + r.width / 2
      const cy = r.top + r.height / 2
      // A highlight lives on one page: the rest of a selection that runs on is left.
      if (cx < box.left || cx > box.right || cy < box.top || cy > box.bottom) continue
      const [ax, ay] = p.viewport.convertToPdfPoint(r.left - box.left, r.top - box.top)
      const [bx, by] = p.viewport.convertToPdfPoint(r.right - box.left, r.bottom - box.top)
      rects.push([Math.min(ax, bx), Math.min(ay, by), Math.max(ax, bx), Math.max(ay, by)].map((n) => Math.round(n * 1000) / 1000))
    }
    const text = flatten(sel.toString())
    if (!rects.length || !text) return

    const view = p.page.view // [x0, y0, x1, y1] in points
    const top = view[3] - Math.max(...rects.map((r) => r[3]))
    const offset = textOffset(p.text, range.startContainer, range.startOffset)
    onSelect({
      text,
      position: { pageIndex: p.index, rects },
      sort_index: `${pad(p.index, 5)}|${pad(Math.min(offset, 999999), 6)}|${pad(Math.min(top, 99999), 5)}`,
      page_label: (labels && labels[p.index]) || String(p.index + 1),
    })
  }, 250)

  // Only a click in the document clears the selection the server holds:
  // clicking into the sidebar's comment box collapses it too.
  const onDown = (e) => {
    const text = e.target.closest && e.target.closest(".adm-reader-text")
    if (text) text.classList.add("is-selecting")
  }
  const onUp = () => {
    el.querySelectorAll(".adm-reader-text.is-selecting").forEach((t) => t.classList.remove("is-selecting"))
    const sel = document.getSelection()
    if (!sel || sel.isCollapsed) onSelect(null)
    else report()
  }
  document.addEventListener("selectionchange", report)
  el.addEventListener("mousedown", onDown)
  el.addEventListener("mouseup", onUp)

  // ── Resizing ──────────────────────────────────────────────────────────

  let width = el.clientWidth
  const resized = new ResizeObserver(debounce(() => {
    if (Math.abs(el.clientWidth - width) < 40) return
    width = el.clientWidth
    scale = fitScale()
    drawn.splice(0)
    pages.forEach((p) => { blank(p); seen.unobserve(p.el); seen.observe(p.el) })
  }, 200))
  resized.observe(el)

  return {
    setAnnotations(list) {
      annotations = list
      pages.forEach(drawMarks)
    },
    async jump(key) {
      const a = annotations.find((x) => x.key === key)
      const pos = a && a.position
      if (!pos || typeof pos.pageIndex !== "number") return
      const p = pages[pos.pageIndex]
      if (!p) return
      el.scrollTo({ top: p.el.offsetTop - 16 })
      await draw(p)
      const rect = pos.rects && pos.rects[0]
      if (rect && p.viewport) {
        const [, top] = toView(p.viewport, rect)
        el.scrollTo({ top: p.el.offsetTop + top - 80, behavior: "smooth" })
      }
      p.el.querySelectorAll(`[data-key="${CSS.escape(key)}"]`).forEach((m) => {
        m.classList.add("is-flash")
        setTimeout(() => m.classList.remove("is-flash"), 1400)
      })
    },
    clearSelection() {
      const sel = document.getSelection()
      if (sel) sel.removeAllRanges()
    },
    destroy() {
      report.cancel()
      document.removeEventListener("selectionchange", report)
      el.removeEventListener("mousedown", onDown)
      el.removeEventListener("mouseup", onUp)
      seen.disconnect()
      resized.disconnect()
      task.destroy()
    },
  }
}
