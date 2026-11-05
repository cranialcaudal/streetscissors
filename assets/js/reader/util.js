// Small helpers the two viewers share.

export const pad = (n, width) => String(Math.max(0, Math.floor(n))).padStart(width, "0").slice(-width)

export function debounce(fn, ms) {
  let t
  const run = (...args) => { clearTimeout(t); t = setTimeout(() => fn(...args), ms) }
  run.cancel = () => clearTimeout(t)
  return run
}

// The selection's text as one line, as Zotero stores a highlight's text.
export const flatten = (text) => String(text || "").replace(/\s+/g, " ").trim()

// How many characters of `root`'s text come before (node, offset): the
// offset part of Zotero's sort index.
export function textOffset(root, node, offset) {
  const doc = root.ownerDocument
  const walker = doc.createTreeWalker(root, 4 /* NodeFilter.SHOW_TEXT */)
  let count = 0
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (n === node) return count + offset
    if (node.nodeType !== 3 && node.contains(n)) return count
    count += n.nodeValue.length
  }
  return count
}

// A highlight's class: its colour is one of Zotero's eight, as a token.
export const markClass = (a) =>
  `adm-reader-hl adm-ann--${a.color_name || "other"}${a.type === "underline" ? " is-underline" : ""}${a.type === "note" ? " is-note" : ""}`
