# assets/

**What the browser runs and how pages look**: the stylesheets (CSS) and the small amount of
browser code (JavaScript). They are not served from here directly. `mix assets.build` (in
development) and `mix assets.deploy` (for the live site) bundle them into two files,
`priv/static/assets/css/app.css` and `priv/static/assets/js/app.js`, and those are what every page
loads.

## What is here

| Folder | What it holds |
|---|---|
| [`css/`](css/) | Every stylesheet, one file per area of the site, all brought together by `css/app.css` |
| [`css/admin/`](css/admin/) | The admin's stylesheets, one per part of the admin (`base.css` first: shared pieces) |
| [`js/`](js/) | The browser code: `app.js` (the entry point) and the pieces it imports |
| [`vendor/`](vendor/) | Libraries kept as files: `topbar.js` (the loading bar at the top of the page), `heroicons.js` (the icon set), and `codemirror.js` (the admin editor's engine, with its licences in `codemirror.LICENSE.txt`; rebuilt only by `tools/vendor/codemirror/build.sh`, never edited by hand) |
| `tsconfig.json` | Lets code editors understand the JavaScript; not used to build anything |

## How the styling works

**Every rule is written by hand.** The project uses Tailwind only as the build step, with utility
classes turned off (`source(none)` in `css/app.css`). So a class like `blog-post-colophon` in a
template is defined in one of these files, by name, and nothing is generated.

**Colours, type and spacing are variables ("tokens")**, defined once at the top of `css/app.css`
(`--paper`, `--ink`, `--rule`, `--accent-ink`…). Pages use the variables, never colour codes
written out.

**Every public page wears one shell** (`css/shell.css`: page head, buttons, plates, tabs, fields):
paper, Sorts Mill Goudy to read, IBM Plex Mono for controls, and poppy (`--accent-ink`) on
anything that can be pressed. A section changes only `--section-tint`, which colours decoration
(the current tab, an eyebrow, a rule) and never anything pressable. The sections keep their own
wrapper class and stylesheet:

| Section | Wrapper | File |
|---|---|---|
| Most pages | none | `theme.css`, `shell.css` |
| `/fitness` | `.steel` | `steel.css`, `fitness_*.css` |
| `/logs` | `.nx01` | `logs.css` |
| `/Christ` | `.faith` | `christ.css` |
| `/negatives` | `.darkroom` | `negatives.css` |
| `/admin` | `.admin-layout` | `css/admin/` |

**`/negatives` is the one dark section**, for the photographs. Under `.darkroom`, `--ink`
(normally the dark text colour) is *light*, so surfaces that must stay dark use the `--paper-*`
variables. The admin has its own tokens (`--st-*`), dark by default and light under a light
system theme.

**Fonts are served from the site itself** (`css/fonts.css`, files in `priv/static/fonts/`); no
page asks Google or anyone else for anything.

## The JavaScript

The site works without JavaScript; the scripts only make it nicer. Most interactive behaviour
is done by the server through LiveView. What is here:

| File | What it does | Used by |
|---|---|---|
| `app.js` | Starts LiveView, registers the hooks below, the search box's suggestions, the service worker, the stale-tab reload, and small page helpers | Every page |
| `trail.js` | Makes the header's Back button return to the last thing you were reading, and puts you back where you were on it | Every page |
| `home_new.js` | Slides in the homepage's corner card of the newest work a moment after the page loads, and keeps it closed once closed until what it shows changes | `/` |
| `home_previews.js` | Plays a few silent seconds of the newest log in that card, on hover or while on screen; never under reduced motion or Save-Data | `/` |
| `christ.js` | Marks the prayer it is time for by the reader's own clock, and the pages' other small enhancements | `/Christ` |
| `emissions_controls.js` | Redraws the commuting-emissions charts when a reader moves a slider (the same maths as `analysis/emissions.R`) | One blog post |
| `gym_routine.js` | The training day's checklist, kept in the browser | `/fitness` |
| `document_editor.js` | The admin's document editor hook (`WebWeb.DocumentEditor`): mounts the editor over a form's textarea and keeps the two in step. Fetches `editor/core.js` only when a page has an editor | `/admin` blog, fitness, newsletter and log notes |
| `editor/core.js` | The editor itself: CodeMirror 6 over the file's own text. Live mode, the slash menu, `[[` completion, outline and Zen are all drawn over the text; nothing untyped is ever rewritten, so Obsidian and the editor agree | Loaded by `document_editor.js` as its own chunk |
| `pc_terminal.js` | Keeps the typing cursor in the `/pc` terminal, and scrolls it as text arrives | `/pc` |

Many other small scripts are **colocated hooks**: written inside the Elixir file of the
component that uses them (look for `<script :type={Phoenix.LiveView.ColocatedHook}`), and
gathered into the bundle when the code compiles. That keeps a piece of behaviour next to the
HTML it belongs to.

## If you want to change…

- **A page's look**: find its outermost class in the template, then search `css/` for it.
- **A colour everywhere**: the token in `css/app.css` (and check `.darkroom` and the admin, which re-define tokens).
- **Add an icon**: add its name to the `@source inline(...)` list in `css/app.css`. An icon not
  on the list shows as an empty square, with no error anywhere.
- After changing anything here, run `mix assets.build`; the live site picks the change up at the
  next deploy (`ops/redeploy.sh`). This machine is also the live server, so don't start a
  `mix phx.server` to look: use `ops/preview.sh`.
