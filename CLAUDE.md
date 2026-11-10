# CLAUDE.md

The rules in this app that are easy to break. How each part works, and why, is in
`docs/architecture.md` (by section, same names as below); each module's own docs go deeper. The
plain-language manual is `docs/how-to.md` (live at `/how-to`); what's next is `docs/roadmap.md`.

## Project

**Street Scissors** is a single-author personal website + CMS on Phoenix 1.8 / LiveView 1.2
(Elixir ~> 1.15), backed by **SQLite** (`ecto_sqlite3`). The OTP app is `:web`; the web layer
namespace is `WebWeb`. Contexts and schemas are in `lib/web/<context>/`; controllers, LiveViews,
components and plugs in `lib/web_web/`.

**This machine is both the live server and the workbench.** Never run a bare `mix phx.server`
or `iex -S mix phx.server` to poke at something: use `mix run --no-start -e …`, the live release
(`_build/prod/rel/web/bin/web rpc '…'`), or `ops/preview.sh` to look at a change on real data
(127.0.0.1:4100, a copy of the live database; `PREVIEW=1` turns off cron, jobs, mail, backups and
the scanner; `content/` is still shared, so look, don't write).

**The working tree is what gets deployed.** Keep it deployable and committed: no half-finished
migrations, and commit before deploying so `git log` says what is live.

Live data, backups and Caddy's log are in `~/streetscissors-data/`. The film tools are in
`tools/film/`, linked into `~/.local/bin` by `tools/install.sh`, so **an edit there is live at
once**. Kept-but-unused things are in `~/streetscissors-attic/`.

## Commands

```bash
mix setup                                   # deps.get + ecto.setup + assets.setup + build
mix test                                    # creates/migrates the test db, then the suite
mix test test/web/guestbook_test.exs:42     # one test by line
mix test --failed                           # rerun last failures
mix precommit                               # compile --warnings-as-errors + deps.unlock --unused + format + test
mix lint                                    # reports only: credo + sobelow + deps.audit + hex.audit
mix ecto.gen.migration name_in_snake_case   # always generate migrations this way
mix assets.build                            # tailwind + esbuild (dev)
ops/redeploy.sh                             # the deploy (see Deployment)
```

**Run `mix precommit` before considering any change done.** `mix lint` gates nothing yet: new code
should add nothing to its reports. A Sobelow finding that was read and is not a fault is marked
`# sobelow_skip ["Its.Type"]` above the function or pipeline, under a comment that says why;
`--mark-skip-all` is not used, because it keys on line numbers.

## Phoenix conventions

Where Phoenix's generator defaults disagree, this list wins.

- **No Tailwind utility classes.** Tailwind v4 runs with `source(none)`. All CSS is hand-written
  from tokens: no `@apply`, no daisyUI, no `<style>` blocks, no inline `<script>`. Only
  `app.js`/`app.css` are served; vendor code is imported into them.
- **Icons:** `<.icon name="hero-…">`, and the name must be on the allowlist (`@source inline(...)`
  in `app.css`). An unlisted name renders an empty square with no error.
- **Layouts** come from the router (`live_session` layout, `put_layout`), never by wrapping a
  template in `<Layouts.app>`. Flash is rendered only by the layouts.
- **Forms:** `to_form/2` in the LiveView, `@form[:field]` with `<.input>` in the template. Never
  `<.form let={f}>`, never a changeset in a template.
- **Lists that grow** are streams; to filter, refetch and `stream(..., reset: true)`.
- **JS interop:** colocated hooks (`<script :type={Phoenix.LiveView.ColocatedHook} name=".Name">`)
  or `phx-hook` with a unique DOM id. An element whose hook owns its DOM needs `phx-update="ignore"`.
- **Elixir:** `Enum.at/2`, not `list[i]`; bind the result of `if`/`case`; never
  `String.to_atom/1` on input; predicates end in `?`; HTTP is `Req`.
- **HEEx:** `{...}` in attributes and bodies, `<%= %>` only for block constructs; `:if`/`:for` on
  tags; `class={["a", @b && "c"]}`; comments `<%!-- --%>`.
- **Ecto:** preload what a template reads. Program-set fields (ids, owner) are never in `cast/3`.
- **Tests:** `Phoenix.LiveViewTest` with `element/2`, `has_element?/2` and DOM ids. Assert outcomes,
  not raw HTML.
- **Docs:** every module has a `@moduledoc` whose first paragraph is one summary sentence. Neutral
  voice ("the author", never "he"); history belongs in commit messages, not docs.

## Rules that break easily

### Privacy

- **The public GitHub repo is code only.** Personal details (names, addresses, IPs, places, dates
  of private events) go in `content/` or `.env` with a neutral fallback, never in code, docs or
  tests. Test addresses come from the documentation ranges (192.0.2.0/24, 198.51.100.0/24,
  203.0.113.0/24). Checks against real content go in the gitignored `test/private/`.
- Anything read at compile time must tolerate the file being absent.
- **No raw IP is stored**: only `Analytics.hash_ip/1`. The guestbook's contact field is encrypted
  under `SECRET_KEY_BASE` and read only by `Guestbook.guestbook_contact/1`; never put it in an
  export, search, email, PubSub or log.
- **Never times on public pages** (fitness week, daybook, changelog, rides): only dates.
- **Ride privacy:** only `stranger_view == "clear"` shows Komoot content; no latitude or longitude
  is ever stored; `RIDE_PRIVACY_ZONES` lives only in `.env`.
- `/food` is admin only and held out of search; `/Christ` is unlisted but searchable. Every other
  public page must be findable (`search_test.exs` walks the router).

### Admin and requests

- **A new admin page goes in `live_session :admin`** (`on_mount {WebWeb.AdminAuth, :ensure_admin}`)
  **and a new admin controller route in the `:admin_only` scope** under it, which answers the
  site's 404. No action checks the session itself, and `router_admin_test.exs` fails for an admin
  address in neither block. `SetCurrentUser` does not protect routes. Public pages with admin
  actions gate each event on the session flag; on `/fitness` the first `handle_event/3` clause
  does it for all of them, and has to stay first.
- The `:browser` pipeline reads nothing from the database per request.
- **Prefetch must not count:** speculation rules prefetch, never prerender; the Analytics plug skips
  `Sec-Purpose: prefetch`; `app.js` posts `/seen`. Who counts is `WebWeb.Visitor.counted?/3`.

### Content and editors

- **Drafts:** `Blog.list_posts/0` and `get_post/1` never return drafts; only the admin passes
  `drafts: true`.
- **The document editor is source-first CodeMirror**, because Obsidian edits the same files. Never
  re-serialise text or swap in a WYSIWYG editor. When the server changes the text, call
  `DocumentEditor.set/3`. Its textarea and div are `phx-update="ignore"`.
- `Web.SourceFile.write/4` refuses to save over a file that moved on disk; keep it that way.
- `Web.Keywords` is the one vocabulary for keywords; `Web.Pieces` for "a piece".
- **The manual is live on save**: write it beside and rename over. It is public (no addresses,
  names, unlisted pages or open weaknesses). First table column never wraps; no unbroken code word
  over ~24 characters outside a table or fence.

### Media, scanner and darkroom

- `Web.Media.FFmpeg` owns every ffmpeg argument list. Video is pinned to `fps=30` and
  `-level:v 4.0` (Safari). The transcoder is not Oban; sources are deleted after a transcode.
- The log player's `start()` calls `play()` synchronously inside the click (Safari).
  `<.live_file_input>` must stay inside its form.
- **Cuts:** everything from the browser goes through `Web.Cuts.Timeline.normalize/2`. The
  assign is `plan`, not `layout`.
- **Negatives:** the URL is the whole view state; build URLs with `NegativesLive.Format` and
  `Negatives.sized_url/2`. Rings show only when both sheet gates pass; never misplaced ones.
- **Scanner:** never bring back a fallback that invents `frames.json`. The V550 scans film only at
  400/800/1600/3200 dpi. `redeploy.sh` waits for the scanner to be idle.
- **Darkroom:** an edit is a recipe, never a change to the picture. Stable Diffusion runs only
  under its `systemd-run` memory cap. `priv/film/stocks.json` holds only datasheet figures.
  A change to `Prior` or `Taste` must not worsen `mix darkroom.eval`'s mean colour error.

### Fitness

- The block file is the only place a block's dates, phases and lifts are written. Frontmatter is
  flat `key: value`, and **a `#` becomes part of the value**.
- **The first line naming a slug is its plan**, so a primer must never link a block lift.
- Days link with `navigate`, never `patch`. A modal's backdrop must not carry `phx-click`.
- Wiki pages: `### Why it works` only with `references:` (else `(theory)`), never a weekday,
  `functional_category` from the thirteen. Citations only from `references.md`, checked on PubMed.
- **Figures:** never two renders at once; look at every pose; films live under the uploads root and
  show only for the figure file they were made from. Keep `figure3d.js` and `measure.mjs`'s `FIELD`
  in step.

### Liturgy

- **A licensed Bible text (RSV-CE) must never be committed**; set `BIBLE_PATH`. Nothing on
  `/Christ` is fetched from another site. Don't regenerate `saints.json` from search results
  unchecked.

### Frontend

- Pages read tokens, never literal hex. Anything pressable wears `--accent-ink` at rest; targets
  ≥44px (admin ≥40px). Nothing scrolls sideways at 390px.
- Under `.darkroom` (`/negatives`), `--ink` is light.
- Admin CSS: one file per area under `assets/css/admin/`, every rule under `.admin-layout` with
  the `adm-` prefix, tokens `--st-*`, text pairings ≥4.5:1. Editing bays stay dark (`st-bay`).
- The font preloads in the root layout must match what `phx.digest` writes, or fonts load twice.
- The wordmark's `aria-label="streetscissors"` is asserted by tests.

## Deployment

A `MIX_ENV=prod` release under the systemd user unit `streetscissors.service`, behind Caddy
(`caddy-streetscissors.service`, `ops/caddy/Caddyfile`). The manual's Part 6 walks through it.

- **`ops/redeploy.sh` is the deploy**: assets, release, restart, health gate. It keeps the serving
  release as `_build/prod/rel/web.previous`, and **`ops/rollback.sh` swaps the two** (it doesn't
  touch the checkout or undo a migration).
- **Don't deploy while a scan is running** or the owner is mid-session. Deploy only at a pause they
  name. Content and the manual need no deploy.
- Unit files live in `ops/systemd/` (`%h`, `%u`) and are installed in `~/.config/systemd/user/`:
  change both together. **Never run `site up` or `sudo caddy start`.**
- `config/runtime.exs` is packed into the release (a change means a deploy); `.env` or the unit
  only needs a restart.
- **The release listens on `127.0.0.1:4000` only**, and Erlang distribution stays on loopback
  (`rel/env.sh.eex`). Bound wider, a LAN caller could forge `x-forwarded-for`.
- The live database is outside the checkout (`DATABASE_PATH`). Read it only read-only
  (`sqlite3 "file:…?mode=ro"`). Migrations run at release boot.
- GitHub runs scheduled workflows (the uptime check) only from `master`.
