// A PDF read with PDF.js (assets/vendor/pdf.mjs), for the ZoteroReader hook.
//
// Pages are laid out at the width of the reader and drawn as they come near
// the view (an IntersectionObserver), each a canvas under a transparent text
// layer for selecting, with the annotations drawn between the two. Far pages
// are let go again, so a long book does not hold every page in memory.
//
// What keeps a tab alive: at most KEEP pages stay drawn and DRAWING are drawn
// at once; no canvas holds more than MAX_PIXELS (Safari's limit for one
// canvas, and roughly its budget for all of them is 384 MB); a canvas let go is
// shrunk to nothing, since Safari frees canvas memory only then. Each page is
// fitted to its own width. A page let go while it was still being drawn
// (scrolled away, or the reader resized) has its draw dropped by its
// generation number, never finished onto an empty page.
//
// Each reader has a worker of its own, ended when the reader closes: PDF.js
// keeps one PDFWorker per port, so a shared one was taken down by the reader
// closing while the next one opened.
//
// Positions are Zotero's: rects in PDF points ([x1, y1, x2, y2], origin at the
// page's bottom left), sort index PPPPP|OOOOOO|TTTTT (page, offset of the
// first selected character in the page's text, distance from the top).

import * as pdfjs from "../../vendor/pdf.mjs"
import workerSource from "../../vendor/pdf-worker.txt"
import { pad, debounce, flatten, textOffset, markClass } from "./util.js"

const KEEP = 6 // pages kept drawn at once
const DRAWING = 2 // pages drawn at once
const MAX_SCALE = 2.5
const MAX_PIXELS = 16777216 // a canvas's pixels (4096 × 4096)
const MAX_SIDE = 16384 // a canvas's longest side

let workerUrl = null
// The worker runs from a blob of its own source: only app.js and its chunks
// are served, so it has no address of its own.
function newWorker() {
  if (!workerUrl) workerUrl = URL.createObjectURL(new Blob([workerSource], { type: "text/javascript" }))
  return new Worker(workerUrl, { type: "module" })
}

export async function open({ el, src, onSelect, signal }) {
  const port = newWorker()
  const pdfWorker = new pdfjs.PDFWorker({ port })
  const task = pdfjs.getDocument({ url: src, worker: pdfWorker, isEvalSupported: false, enableXfa: false })

  let closing = null
  function close() {
    closing ||= (async () => {
      try { await task.destroy() } catch (_) { /* already gone */ }
      pdfWorker.destroy()
      port.terminate()
    })()
    return closing
  }
  const abort = () => close()
  signal?.addEventListener("abort", abort, { once: true })

  let doc, labels, base
  try {
    doc = await task.promise
    labels = await doc.getPageLabels().catch(() => null)
    base = (await doc.getPage(1)).getViewport({ scale: 1 })
  } catch (error) {
    await close()
    throw error
  } finally {
    signal?.removeEventListener("abort", abort)
  }

  const holder = document.createElement("div")
  holder.className = "adm-reader-pages"
  el.replaceChildren(holder)

  let width = fitWidth()
  let annotations = []
  let closed = false
  const pages = []
  const drawn = [] // pages drawn, oldest first
  const queue = [] // pages waiting to be drawn, next first
  let active = 0

  function fitWidth() {
    return Math.max(280, el.clientWidth - 32)
  }

  // Each page fitted to the reader's width by its own size.
  const scaleFor = (w) => Math.min(MAX_SCALE, width / w)

  function placeholder(p) {
    const w = p.width || base.width
    const h = p.height || base.height
    const s = scaleFor(w)
    p.el.style.width = `${w * s}px`
    p.el.style.height = `${h * s}px`
  }

  for (let i = 0; i < doc.numPages; i++) {
    const pageEl = document.createElement("div")
    pageEl.className = "adm-reader-page"
    pageEl.dataset.index = String(i)
    pageEl.setAttribute("aria-label", `Page ${labels?.[i] || i + 1}`)
    holder.appendChild(pageEl)
    const p = { index: i, el: pageEl, state: "blank", gen: 0, waiters: [] }
    placeholder(p)
    pages.push(p)
  }

  const seen = new IntersectionObserver((entries) => {
    for (const e of entries) {
      const p = pages[Number(e.target.dataset.index)]
      if (e.isIntersecting) want(p)
      else if (p.state === "queued") settle(p, false, "blank")
    }
  }, { root: el, rootMargin: "1200px 0px" })
  pages.forEach((p) => seen.observe(p.el))

  // ── Drawing ───────────────────────────────────────────────────────────

  // Queues a page; `first` puts it at the front. Resolves true once it is
  // drawn, false if it is let go first.
  function want(p, first = false) {
    if (closed) return Promise.resolve(false)
    if (p.state === "drawn") return Promise.resolve(true)
    const done = new Promise((resolve) => p.waiters.push(resolve))
    if (p.state === "blank" || p.state === "failed") {
      p.state = "queued"
      first ? queue.unshift(p) : queue.push(p)
    } else if (p.state === "queued" && first) {
      queue.splice(queue.indexOf(p), 1)
      queue.unshift(p)
    }
    pump()
    return done
  }

  function settle(p, ok, state) {
    p.state = state
    const waiters = p.waiters.splice(0)
    waiters.forEach((resolve) => resolve(ok))
  }

  function pump() {
    while (!closed && active < DRAWING && queue.length) {
      const p = queue.shift()
      if (p.state !== "queued") continue
      active++
      draw(p).finally(() => { active--; pump() })
    }
  }

  async function draw(p) {
    p.state = "drawing"
    const gen = p.gen
    const stale = () => closed || p.gen !== gen
    let canvas = null
    try {
      const page = p.page || (p.page = await doc.getPage(p.index + 1))
      if (stale()) return
      const natural = page.getViewport({ scale: 1 })
      p.width = natural.width
      p.height = natural.height
      const viewport = page.getViewport({ scale: scaleFor(natural.width) })
      p.el.style.width = `${viewport.width}px`
      p.el.style.height = `${viewport.height}px`
      // What PDF.js's text layer sizes itself by.
      p.el.style.setProperty("--total-scale-factor", String(viewport.scale))
      p.el.style.setProperty("--scale-round-x", "1px")
      p.el.style.setProperty("--scale-round-y", "1px")

      // The screen's pixel ratio, less if the canvas would be too big.
      let ratio = window.devicePixelRatio || 1
      ratio = Math.min(
        ratio,
        Math.sqrt(MAX_PIXELS / (viewport.width * viewport.height)),
        MAX_SIDE / viewport.width,
        MAX_SIDE / viewport.height,
      )
      canvas = document.createElement("canvas")
      canvas.width = Math.max(1, Math.floor(viewport.width * ratio))
      canvas.height = Math.max(1, Math.floor(viewport.height * ratio))
      canvas.className = "adm-reader-canvas"
      const context = canvas.getContext("2d")
      if (!context) throw new Error("the browser has no memory left for this page")
      const marks = document.createElement("div")
      marks.className = "adm-reader-marks"
      const text = document.createElement("div")
      text.className = "adm-reader-text"
      p.el.replaceChildren(canvas, marks, text)
      p.canvas = canvas

      p.task = page.render({
        canvasContext: context,
        viewport,
        transform: ratio === 1 ? null : [ratio, 0, 0, ratio, 0, 0],
      })
      await p.task.promise
      if (stale()) return
      p.layer = new pdfjs.TextLayer({ textContentSource: page.streamTextContent(), container: text, viewport })
      await p.layer.render()
      if (stale()) return
      // PDF.js's own trick: a block after the text, so a drag past the last
      // line does not select the whole page.
      const end = document.createElement("div")
      end.className = "adm-reader-text-end"
      text.appendChild(end)
      p.viewport = viewport
      p.marks = marks
      p.text = text
      p.task = p.layer = null
      drawMarks(p)
      drawn.push(p)
      settle(p, true, "drawn")
      forget()
    } catch (error) {
      if (stale() || (error && error.name === "RenderingCancelledException")) return
      // A page that cannot be drawn says so, and is tried again when it
      // next comes into view.
      if (canvas) canvas.width = canvas.height = 0
      const note = document.createElement("p")
      note.className = "adm-help"
      note.textContent = `Page ${p.index + 1} could not be drawn: ${error && error.message ? error.message : error}`
      p.el.replaceChildren(note)
      p.canvas = p.task = p.layer = null
      settle(p, false, "failed")
      console.warn("[pdf_view]", error)
    }
  }

  // Lets go of the pages drawn longest ago that are out of sight.
  function forget() {
    const top = el.scrollTop
    const bottom = top + el.clientHeight
    while (drawn.length > KEEP) {
      const i = drawn.findIndex((p) => p.el.offsetTop + p.el.offsetHeight < top - 1200 || p.el.offsetTop > bottom + 1200)
      if (i < 0) break
      blank(drawn[i])
    }
  }

  // A page back to an empty box of its size: its draw, if any, is dropped.
  function blank(p) {
    p.gen++
    if (p.task) p.task.cancel()
    if (p.layer) p.layer.cancel()
    if (p.canvas) p.canvas.width = p.canvas.height = 0
    const i = drawn.indexOf(p)
    if (i >= 0) drawn.splice(i, 1)
    p.el.replaceChildren()
    p.canvas = p.task = p.layer = p.marks = p.text = p.viewport = null
    settle(p, false, "blank")
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
        const [left, top, w, h] = toView(p.viewport, rect)
        const m = document.createElement("div")
        m.className = markClass(a)
        m.dataset.key = a.key
        m.style.left = `${left}px`
        m.style.top = `${top}px`
        m.style.width = `${w}px`
        m.style.height = `${h}px`
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

  let selected = false
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
    selected = true
    onSelect({
      text,
      position: { pageIndex: p.index, rects },
      sort_index: `${pad(p.index, 5)}|${pad(Math.min(offset, 999999), 6)}|${pad(Math.min(top, 99999), 5)}`,
      page_label: (labels && labels[p.index]) || String(p.index + 1),
    })
  }, 250)

  // Only a click in the document clears the selection the server holds:
  // clicking into the sidebar's comment box collapses it too. And only once,
  // not on every click.
  const onDown = (e) => {
    const text = e.target.closest && e.target.closest(".adm-reader-text")
    if (text) text.classList.add("is-selecting")
  }
  const onUp = () => {
    el.querySelectorAll(".adm-reader-text.is-selecting").forEach((t) => t.classList.remove("is-selecting"))
    const sel = document.getSelection()
    if (sel && !sel.isCollapsed) report()
    else if (selected) {
      selected = false
      onSelect(null)
    }
  }
  document.addEventListener("selectionchange", report)
  el.addEventListener("mousedown", onDown)
  el.addEventListener("mouseup", onUp)

  // ── Resizing ──────────────────────────────────────────────────────────

  // A hidden reader (its panel folded) measures 0 wide: it keeps its pages
  // until it is shown again.
  const relayout = debounce(() => {
    if (closed || el.clientWidth === 0) return
    const next = fitWidth()
    if (Math.abs(next - width) < 40) return
    width = next
    queue.splice(0)
    pages.forEach((p) => { blank(p); seen.unobserve(p.el); seen.observe(p.el) })
  }, 200)
  const resized = new ResizeObserver(relayout)
  resized.observe(el)

  return {
    setAnnotations(list) {
      annotations = list || []
      pages.forEach(drawMarks)
    },
    async jump(key) {
      const a = annotations.find((x) => x.key === key)
      const pos = a && a.position
      if (!pos || typeof pos.pageIndex !== "number") return
      const p = pages[pos.pageIndex]
      if (!p) return
      el.scrollTo({ top: p.el.offsetTop - 16 })
      if (!(await want(p, true)) || !p.viewport) return
      const rect = pos.rects && pos.rects[0]
      if (rect) {
        const [, top] = toView(p.viewport, rect)
        el.scrollTo({ top: p.el.offsetTop + top - 80, behavior: "smooth" })
      }
      p.el.querySelectorAll(`[data-key="${CSS.escape(key)}"]`).forEach((m) => {
        m.classList.add("is-flash")
        setTimeout(() => m.classList.remove("is-flash"), 1400)
      })
    },
    clearSelection() {
      selected = false
      const sel = document.getSelection()
      if (sel) sel.removeAllRanges()
    },
    destroy() {
      if (closed) return close()
      closed = true
      report.cancel()
      relayout.cancel()
      document.removeEventListener("selectionchange", report)
      el.removeEventListener("mousedown", onDown)
      el.removeEventListener("mouseup", onUp)
      seen.disconnect()
      resized.disconnect()
      queue.splice(0)
      pages.forEach(blank)
      return close()
    },
  }
}
