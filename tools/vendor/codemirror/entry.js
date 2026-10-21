// What the admin editor (assets/js/editor/core.js) uses from CodeMirror 6,
// bundled into one file so the site's build needs no node_modules. Add a
// name here, run build.sh, and commit both outputs.
export {
  EditorState, EditorSelection, Compartment, RangeSetBuilder, StateEffect, StateField,
} from "@codemirror/state"
export {
  EditorView, keymap, drawSelection, highlightActiveLine, placeholder, ViewPlugin,
  Decoration, MatchDecorator, WidgetType, dropCursor,
} from "@codemirror/view"
export {
  defaultKeymap, history, historyKeymap, indentWithTab, undo, redo,
} from "@codemirror/commands"
export {
  syntaxHighlighting, HighlightStyle, bracketMatching, foldGutter, foldService, foldKeymap,
  indentOnInput, syntaxTree,
} from "@codemirror/language"
export { markdown, markdownLanguage, markdownKeymap } from "@codemirror/lang-markdown"
export {
  autocompletion, completionKeymap, startCompletion, closeBrackets, closeBracketsKeymap,
} from "@codemirror/autocomplete"
export { search, searchKeymap, highlightSelectionMatches } from "@codemirror/search"
export { tags } from "@lezer/highlight"
export { GFM } from "@lezer/markdown"
