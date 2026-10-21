// The admin's document editor: CodeMirror 6 over the file's own text.
//
// Source-first, on purpose. The vault is also edited in Obsidian (whose editor
// is CodeMirror 6 too), and saves are guarded by the file's revision. So the
// text is never re-serialised: what was not typed is not touched, byte for
// byte. Everything "rich" here (heading sizes, dimmed marks, task boxes,
// highlighted embeds) is a decoration drawn over the text, never a change to
// it. (A browser hands a textarea's text over with \n line endings; a file
// saved with \r\n gets them back on save, from Web.SourceFile.)
//
// Loaded lazily by assets/js/document_editor.js, so the public pages never
// download this or the vendored CodeMirror (assets/vendor/codemirror.js).

import {
  EditorState, EditorSelection, Compartment, RangeSetBuilder,
  EditorView, keymap, drawSelection, highlightActiveLine, placeholder, ViewPlugin,
  Decoration, MatchDecorator, WidgetType, dropCursor,
  defaultKeymap, history, historyKeymap, indentWithTab, redo,
  syntaxHighlighting, HighlightStyle, bracketMatching, foldGutter, foldService, foldKeymap,
  syntaxTree,
  markdown, markdownLanguage,
  autocompletion, completionKeymap, startCompletion,
  search, searchKeymap, highlightSelectionMatches,
  tags,
} from "../../vendor/codemirror.js"

const WORDS_PER_MINUTE = 230

// The leading `---` … `---` block, as [from, to] in the document, or null.
// Read only: the server owns what the frontmatter means.
export function frontmatterRange(doc) {
  if (doc.lines < 2 || !/^---[ \t]*\r?$/.test(doc.line(1).text)) return null
  for (let n = 2; n <= doc.lines; n++) {
    if (/^---[ \t]*\r?$/.test(doc.line(n).text)) return [doc.line(1).from, doc.line(n).to]
  }
  return null
}

// The headings, outside fences and frontmatter, for the outline panel.
export function outline(doc) {
  const front = frontmatterRange(doc)
  const out = []
  let fenced = false
  for (let n = 1; n <= doc.lines; n++) {
    const line = doc.line(n)
    if (front && line.to <= front[1]) continue
    if (/^\s*(```|~~~)/.test(line.text)) { fenced = !fenced; continue }
    const m = !fenced && /^(#{1,6})\s+(.+?)\s*#*\s*$/.exec(line.text)
    if (m) out.push({ level: m[1].length, text: m[2], pos: line.from })
  }
  return out
}

// Words in the body (frontmatter left out) and minutes to read them.
export function counts(doc) {
  const front = frontmatterRange(doc)
  const text = doc.sliceString(front ? front[1] : 0)
  const words = (text.match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu) || []).length
  return { words, minutes: Math.max(1, Math.ceil(words / WORDS_PER_MINUTE)) }
}

// ── Look ────────────────────────────────────────────────────────────────

// Classes rather than colours: assets/css/admin/editor.css inks them from the
// admin's tokens, so light and dark follow the rest of the studio.
const highlight = HighlightStyle.define([
  { tag: tags.heading1, class: "adm-md-h adm-md-h1" },
  { tag: tags.heading2, class: "adm-md-h adm-md-h2" },
  { tag: tags.heading3, class: "adm-md-h adm-md-h3" },
  { tag: [tags.heading4, tags.heading5, tags.heading6], class: "adm-md-h" },
  { tag: tags.strong, class: "adm-md-strong" },
  { tag: tags.emphasis, class: "adm-md-em" },
  { tag: tags.strikethrough, class: "adm-md-strike" },
  { tag: [tags.link, tags.url], class: "adm-md-link" },
  { tag: tags.monospace, class: "adm-md-code" },
  { tag: tags.quote, class: "adm-md-quote" },
  { tag: [tags.processingInstruction, tags.contentSeparator], class: "adm-md-mark" },
  { tag: tags.list, class: "adm-md-list" },
])

const theme = EditorView.theme({
  "&": { backgroundColor: "var(--st-surface)", color: "var(--st-ink)" },
  ".cm-content": { fontFamily: "var(--st-font-data)", caretColor: "var(--st-accent)" },
  ".cm-cursor": { borderLeftColor: "var(--st-accent)" },
  ".cm-activeLine": { backgroundColor: "color-mix(in srgb, var(--st-ink) 4%, transparent)" },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection": {
    backgroundColor: "color-mix(in srgb, var(--st-accent) 28%, transparent)",
  },
  ".cm-gutters": { backgroundColor: "var(--st-surface)", border: "none", color: "var(--st-ink-3)" },
  ".cm-tooltip": { backgroundColor: "var(--st-raised)", border: "1px solid var(--st-line-strong)" },
})

// The frontmatter block reads as data, and folds.
const frontmatterLines = ViewPlugin.fromClass(class {
  constructor(view) { this.decorations = this.build(view) }
  update(u) { if (u.docChanged) this.decorations = this.build(u.view) }
  build(view) {
    const range = frontmatterRange(view.state.doc)
    const b = new RangeSetBuilder()
    if (range) {
      const last = view.state.doc.lineAt(range[1]).number
      for (let n = 1; n <= last; n++) {
        b.add(view.state.doc.line(n).from, view.state.doc.line(n).from, Decoration.line({ class: "adm-md-front" }))
      }
    }
    return b.finish()
  }
}, { decorations: (v) => v.decorations })

const frontmatterFold = foldService.of((state, lineStart) => {
  const range = frontmatterRange(state.doc)
  if (!range || lineStart !== range[0]) return null
  return { from: state.doc.line(1).to, to: range[1] }
})

// Obsidian's syntax, which Markdown itself doesn't know: an embed
// (`![[roll012/3|Caption]]`), a wiki link (`[[slug|Name]]`), a footnote ref.
const obsidian = new MatchDecorator({
  regexp: /(!)?\[\[[^\]\n]+\]\]|\[\^[^\]\s]+\]/g,
  decoration: (m) =>
    Decoration.mark({ class: m[0].startsWith("[^") ? "adm-md-footnote" : m[1] ? "adm-md-embed" : "adm-md-wiki" }),
})

const obsidianMarks = ViewPlugin.fromClass(class {
  constructor(view) { this.decorations = obsidian.createDeco(view) }
  update(u) { this.decorations = obsidian.updateDeco(u, this.decorations) }
}, { decorations: (v) => v.decorations })

// ── Live mode: the page's shape, the text untouched ──────────────────────

class TaskBox extends WidgetType {
  constructor(done, pos) { super(); this.done = done; this.pos = pos }
  eq(other) { return other.done === this.done && other.pos === this.pos }
  toDOM(view) {
    const box = document.createElement("input")
    box.type = "checkbox"
    box.checked = this.done
    box.className = "adm-md-task"
    box.setAttribute("aria-label", this.done ? "Done" : "To do")
    // Ticking edits the text, as typing `x` would: the one place a widget
    // writes, and only the character inside the brackets.
    box.addEventListener("mousedown", (e) => {
      e.preventDefault()
      view.dispatch({ changes: { from: this.pos + 1, to: this.pos + 2, insert: this.done ? " " : "x" } })
    })
    return box
  }
  ignoreEvent() { return false }
}

const MARKS = new Set(["HeaderMark", "EmphasisMark", "CodeMark", "QuoteMark", "StrikethroughMark"])

const livePreview = ViewPlugin.fromClass(class {
  constructor(view) { this.decorations = this.build(view) }
  update(u) {
    if (u.docChanged || u.selectionSet || u.viewportChanged) this.decorations = this.build(u.view)
  }
  build(view) {
    const { state } = view
    const active = new Set(state.selection.ranges.map((r) => state.doc.lineAt(r.head).number))
    const marks = []
    for (const { from, to } of view.visibleRanges) {
      syntaxTree(state).iterate({
        from, to,
        enter: (node) => {
          const line = state.doc.lineAt(node.from)
          const m = /^ATXHeading(\d)$/.exec(node.name)
          if (m) marks.push(Decoration.line({ class: `adm-md-line-h${m[1]}` }).range(line.from))
          if (active.has(line.number)) return
          if (MARKS.has(node.name) && node.to > node.from) {
            marks.push(Decoration.mark({ class: "adm-md-hide" }).range(node.from, node.to))
          } else if (node.name === "TaskMarker") {
            const done = /x/i.test(state.doc.sliceString(node.from, node.to))
            marks.push(Decoration.replace({ widget: new TaskBox(done, node.from) }).range(node.from, node.to))
          }
        },
      })
    }
    return Decoration.set(marks, true)
  }
}, { decorations: (v) => v.decorations })

// ── Writing helpers ───────────────────────────────────────────────────────

// Wraps the selection (or the word at the cursor) in `mark`, or unwraps it.
function wrap(mark) {
  return (view) => {
    view.dispatch(view.state.changeByRange((range) => {
      let { from, to } = range
      if (from === to) {
        const word = view.state.wordAt(from)
        if (word) ({ from, to } = word)
      }
      const before = view.state.sliceDoc(from - mark.length, from)
      const after = view.state.sliceDoc(to, to + mark.length)
      if (before === mark && after === mark) {
        return {
          changes: [{ from: from - mark.length, to: from }, { from: to, to: to + mark.length }],
          range: EditorSelection.range(from - mark.length, to - mark.length),
        }
      }
      return {
        changes: [{ from, insert: mark }, { from: to, insert: mark }],
        range: EditorSelection.range(from + mark.length, to + mark.length),
      }
    }))
    return true
  }
}

function link(view) {
  view.dispatch(view.state.changeByRange((range) => {
    const text = view.state.sliceDoc(range.from, range.to)
    const insert = `[${text}]()`
    const cursor = range.from + insert.length - 1
    return { changes: { from: range.from, to: range.to, insert }, range: EditorSelection.cursor(cursor) }
  }))
  return true
}

function insertText(view, text) {
  const { from, to } = view.state.selection.main
  view.dispatch({ changes: { from, to, insert: text }, selection: { anchor: from + text.length }, scrollIntoView: true })
  view.focus()
}

// ── Completion: the slash menu, `[[`, and the frontmatter's lists ─────────

const SLASH = [
  ["Heading 1", "# "], ["Heading 2", "## "], ["Heading 3", "### "],
  ["List", "- "], ["Numbered list", "1. "], ["Task", "- [ ] "], ["Quote", "> "],
  ["Code", "```\n\n```", 4], ["Table", "| Column | Column |\n|---|---|\n|  |  |\n"],
  ["Footnote", "[^1]\n\n[^1]: "], ["Rule", "---\n"],
  ["Frame or roll", "![[", null, true], ["Link to a piece", "[[", null, true],
]

function slashSource(context) {
  const m = context.matchBefore(/^\s*\/[\w ]*$/)
  if (!m) return null
  // The options are matched against what follows the slash; choosing one
  // replaces the slash too.
  const slash = m.from + m.text.indexOf("/")
  return {
    from: slash + 1,
    options: SLASH.map(([label, insert, back, reopen]) => ({
      label,
      type: "keyword",
      apply: (view, _c, _f, t) => {
        const cursor = slash + (back == null ? insert.length : back)
        view.dispatch({ changes: { from: slash, to: t, insert }, selection: { anchor: cursor } })
        if (reopen) startCompletion(view)
      },
    })),
  }
}

function serverSource(ask, scope) {
  return async (context) => {
    const { state, pos } = context
    const front = frontmatterRange(state.doc)
    const line = state.doc.lineAt(pos)

    // In the frontmatter: `related:` takes piece refs, `keywords:` keywords.
    if (front && pos <= front[1]) {
      const key = /^(related|keywords|tags):/.exec(line.text)
      if (!key) return null
      const m = context.matchBefore(/[^,:]*$/)
      const q = m.text.trimStart()
      if (!q && !context.explicit) return null
      const items = await ask(q, key[1] === "related" ? "related" : "keyword", scope)
      return { from: pos - q.length, filter: false, options: items.map(toOption) }
    }

    const m = context.matchBefore(/!?\[\[[^\]\n]*$/)
    if (!m) return null
    const embed = m.text.startsWith("!")
    const q = m.text.slice(embed ? 3 : 2)
    const items = await ask(q, embed ? "embed" : "link", scope)
    return {
      from: m.from,
      // A closing `]]` typed (or auto-inserted) ahead of the cursor is
      // replaced too, so a choice never leaves `]]]]`.
      to: state.sliceDoc(pos, pos + 2) === "]]" ? pos + 2 : pos,
      filter: false,
      options: items.map(toOption),
    }
  }
}

function toOption(item) {
  return { label: item.label, detail: item.detail || "", apply: item.insert }
}

// ── The editor ────────────────────────────────────────────────────────────

/**
 * Mounts an editor in `parent` over `doc`.
 *
 *   onChange(text)       every edit, with the whole text
 *   ask(q, kind, scope)  a Promise of [{label, detail, insert}] from the server
 *   onSubmit()           Mod-S
 *   onLeave()            Escape; true if it left something (zen)
 *
 * Returns { view, setText, command, insert, outline, counts, destroy }.
 */
export function createEditor({ parent, doc, scope, label, live, onChange, ask, onSubmit, onLeave }) {
  const mode = new Compartment()

  const keys = [
    { key: "Mod-b", run: wrap("**") },
    { key: "Mod-i", run: wrap("_") },
    { key: "Mod-k", run: link },
    { key: "Mod-s", preventDefault: true, run: () => { onSubmit && onSubmit(); return true } },
    { key: "Mod-Shift-z", run: redo },
    { key: "Escape", run: () => (onLeave ? onLeave() : false) },
  ]

  const view = new EditorView({
    parent,
    state: EditorState.create({
      doc,
      extensions: [
        history(),
        drawSelection(),
        dropCursor(),
        highlightActiveLine(),
        bracketMatching(),
        foldGutter(),
        frontmatterFold,
        frontmatterLines,
        obsidianMarks,
        EditorView.lineWrapping,
        markdown({ base: markdownLanguage }),
        syntaxHighlighting(highlight),
        search({ top: true }),
        highlightSelectionMatches(),
        autocompletion({
          override: [slashSource, ...(ask && scope !== "none" ? [serverSource(ask, scope)] : [])],
          icons: false,
        }),
        keymap.of([...keys, ...completionKeymap, ...searchKeymap, ...foldKeymap, ...historyKeymap, indentWithTab, ...defaultKeymap]),
        mode.of(live ? livePreview : []),
        theme,
        placeholder("Write, or type / for a block"),
        EditorView.contentAttributes.of({ "aria-label": label || "Document", "aria-multiline": "true" }),
        EditorView.updateListener.of((u) => { if (u.docChanged) onChange(u.state.doc.toString()) }),
      ],
    }),
  })

  let isLive = !!live

  return {
    view,
    get live() { return isLive },
    setText(text) {
      if (text === view.state.doc.toString()) return
      view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: text } })
    },
    setLive(on) {
      isLive = on
      view.dispatch({ effects: mode.reconfigure(on ? livePreview : []) })
    },
    command(cmd) {
      const run = { bold: wrap("**"), italic: wrap("_"), link }[cmd]
      if (run) { run(view); view.focus() }
    },
    insert(text) { insertText(view, text) },
    jump(pos) {
      view.dispatch({ selection: { anchor: pos }, effects: EditorView.scrollIntoView(pos, { y: "start" }) })
      view.focus()
    },
    outline() { return outline(view.state.doc) },
    counts() { return counts(view.state.doc) },
    destroy() { view.destroy() },
  }
}
