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
| [`vendor/`](vendor/) | Two small libraries kept as files: `topbar.js` (the loading bar at the top of the page) and `heroicons.js` (the icon set) |
| `tsconfig.json` | Lets code editors understand the JavaScript; not used to build anything |

## How the styling works

**Every rule is written by hand.** The project uses Tailwind only as the build step, with utility
classes turned off (`source(none)` in `css/app.css`). So a class like `blog-post-colophon` in a
template is defined in one of these files, by name, and nothing is generated.

**Colours, type and spacing are variables ("tokens")**, defined once at the top of `css/app.css`
(`--paper`, `--ink`, `--rule`, `--color-orange`…). Pages use the variables, never colour codes
written out. That is how one page can look like printed paper and another like a darkroom:

| Theme | Where | File |
|---|---|---|
| Paper (the default) | Most pages | `theme.css`, `app.css` |
| Darkroom | `/negatives` | `negatives.css` |
| Blueprint steel | Every `/fitness` page | `steel.css` |
| NX-01 console | `/logs` | `logs.css` |
| Brown scapular | `/Christ` | `faith.css` |
| The studio | `/admin` | `css/admin/` |

Each theme re-defines the same variables inside its own class (`.darkroom`, `.steel`…), so a
component written with tokens looks right in all of them. **Careful:** in the darkroom, NX-01 and
scapular themes, `--ink` (normally the dark text colour) is *light*. Surfaces that must stay dark
use the `--paper-*` variables.

**Fonts are served from the site itself** (`css/fonts.css`, files in `priv/static/fonts/`); no
page asks Google or anyone else for anything.

## The JavaScript

The site works without JavaScript; the scripts only make it nicer. Most interactive behaviour
is done by the server through LiveView. What is here:

| File | What it does | Used by |
|---|---|---|
| `app.js` | Starts LiveView, registers the hooks below, the search box's suggestions, the service worker, the stale-tab reload, and small page helpers | Every page |
| `trail.js` | Makes the header's Back button return to the last thing you were reading, and puts you back where you were on it | Every page |
| `emissions_controls.js` | Redraws the commuting-emissions charts when a reader moves a slider (the same maths as `analysis/emissions.R`) | One blog post |
| `gym_routine.js` | The training day's checklist | `/fitness` |
| `markdown_editor.js` | A markdown toolbar hook. Still registered in `app.js`, but **no page uses it now** (the blog editor has its own colocated hook); a candidate for removal | Nothing |
| `pc_terminal.js` | Keeps the typing cursor in the `/pc` terminal, and scrolls it as text arrives | `/pc` |

Many other small scripts are **colocated hooks**: written inside the Elixir file of the
component that uses them (look for `<script :type={Phoenix.LiveView.ColocatedHook}`), and
gathered into the bundle when the code compiles. That keeps a piece of behaviour next to the
HTML it belongs to.

## If you want to change…

- **A page's look**: find its outermost class in the template, then search `css/` for it.
- **A colour everywhere**: the token in `css/app.css` (and check the themes that re-define it).
- **Add an icon**: add its name to the `@source inline(...)` list in `css/app.css`. An icon not
  on the list shows as an empty square, with no error anywhere.
- After changing anything here, `mix assets.build` (or a running `mix phx.server`, which rebuilds
  by itself).
