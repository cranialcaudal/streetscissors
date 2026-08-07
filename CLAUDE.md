# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Street Scissors** is a single-author personal website + CMS on Phoenix 1.8 / LiveView 1.1
(Elixir ~> 1.15), backed by **SQLite** (`ecto_sqlite3`). The OTP app is `:web`; the web layer namespace
is `WebWeb`. `AGENTS.md` is the Phoenix 1.8 coding-conventions / usage-rules reference (Elixir, LiveView,
HEEx, Ecto idioms) — consult it for *how to write* code; this file covers *how this app is wired*.

## Commands

```bash
mix setup                       # deps.get + ecto.setup (create/migrate/seed) + assets.setup + build
mix phx.server                  # dev server at localhost:4000
iex -S mix phx.server           # dev server with IEx

mix test                        # ecto.create --quiet + ecto.migrate --quiet, then the suite
mix test test/web/general_test.exs            # single file
mix test test/web/general_test.exs:42         # single test by line number
mix test --failed                             # rerun last failures

mix format
mix precommit                   # compile --warnings-as-errors + deps.unlock --unused + format + test
mix ecto.migrate / mix ecto.reset
mix ecto.gen.migration name_in_snake_case     # always generate migrations this way

mix assets.build                # tailwind + esbuild (dev)
mix assets.deploy               # minified assets + phx.digest (production)
```

**Run `mix precommit` before considering any change done** — it is the project gate
(warnings-as-errors compile, unused-dep check, format, full test run).

## Architecture — the non-obvious parts

Standard Phoenix layering: contexts + Ecto schemas in `lib/web/<context>/`; controllers, LiveViews,
components, plugs in `lib/web_web/`. The pieces that take reading several files to understand:

- **Admin auth**: login (`AdminSessionController`) checks a single password via
  `Plug.Crypto.secure_compare` against `Application.get_env(:web, :admin_password)` and sets
  `session["admin_user"] = true`. The `/admin/*` LiveViews sit in `live_session :admin` with
  `on_mount {WebWeb.AdminAuth, :ensure_admin}` (router.ex), which halts and redirects non-admins —
  new admin routes belong in that live_session. Most admin LiveViews also belt-and-suspenders check
  `session["admin_user"]` in `mount/3`. The `SetCurrentUser` plug only exposes `@admin_mode` to
  templates — **it does not protect routes.** Non-admin pages with admin-only actions (e.g. the
  fitness landing's log buttons) gate per-event on the session flag.

- **File-based content systems** (all read from disk at request time; the repo's `content/` dir is
  an Obsidian vault):
  - **The blog** (`Web.Blog`): **strictly typed work** — markdown in `content/blog/` (env
    `BLOG_PATH`), served at `/blog` and `/blog/<slug>`. Supports YAML frontmatter
    (title/description/date/keywords — see `content/templates/blog-template.md`) and
    Obsidian-style photo embeds (`![[roll012]]` for a contact sheet, `![[roll012/3|Caption]]`
    for a single frame) expanded post-Earmark by `Web.Blog.Embeds` against `Web.Negatives`.
  - Blog embeds also support `![[ride:123]]` — a Komoot ride card via `Web.Rides`.
  - The old manuscripts section is retired: every `/manuscripts*` URL 301-redirects to `/blog`
    (`LegacyRedirectController`), as do the old `/blog/<category>` and `/fitness/<slug>` paths.
  - There is also a legacy DB `blog_posts` table — plus unused `tags`/`post_tags` tables from an
    abandoned tagging attempt — that nothing in `lib/` reads. Keywords are **not** stored there.

- **Every browser request runs the plug chain** `Analytics` → `SetCurrentUser` → `FetchStats` →
  `LoadSiteSettings` (see `router.ex` `:browser` pipeline). So analytics hit-logging and site-settings
  loading happen on all HTML routes; `Analytics` and the guestbook persist client IP addresses.
  Site settings are key/value rows (`SiteSettings.get_setting/2`) read on every request.

- **Supervision tree** (`lib/web/application.ex`): Repo, an `Ecto.Migrator` that auto-runs migrations
  **only in releases** (`RELEASE_NAME` set), PubSub, `Finch` (named `Swoosh.Finch`, for email over HTTP
  e.g. Resend), a `Task.Supervisor`, and `Web.Scheduler` (**Quantum** cron jobs). **Oban caveat:** it is
  configured (`config/config.exs`) and `workers/newsletter_sender.ex` is an `Oban.Worker`, but `{Oban, …}`
  is **not** in the supervision tree — so jobs enqueued via `Oban.insert/1` are persisted yet never
  executed. Adding `Oban` to `application.ex` children is required to actually process them.

- **Feature areas** beyond the blog: fitness (`Web.Fitness` + `Web.Fitness.Vault` markdown regimen/wiki;
  the `/fitness` landing is the regimen accordion — today auto-expanded via `Web.Clock`, a
  tzdata-free US-Pacific helper — beside a latest-Komoot-ride card), Komoot-synced rides
  (`Web.Rides` + `Web.Rides.KomootSync`: hourly Quantum sync, re-syncs edited tours via
  `changed_at`, hides tours private on Komoot from public queries, caches static-map thumbnails
  via `Web.Rides.Thumbs` served at `/fitness/rides/:id/thumb`), newsletter + subscribers,
  guestbook, contact messages, analytics, a `/pc` terminal
  LiveView (its `C:\DOCS\BLOG` mirrors blog posts), RSS feed + sitemap controllers, and a custom
  captcha (`lib/web_web/captcha.ex`, not reCAPTCHA).

- **Captain's logs** (`Web.Audio`) are the blog's sibling, not a feature of it: DB-backed spoken
  pieces at `/logs` and `/logs/<slug>` (`WebWeb.LogsLive.Index`/`.Show`). `/audio` 301s to `/logs`.
  Audio files are uploaded through `/admin/logs`, stored via `Web.Uploads` (default
  `priv/static/uploads/logs/`, `:uploads_path`) and served by `WebWeb.Plugs.MediaServe`, which
  supports HTTP Range so listeners can seek. **A blog post no longer picks up a sidecar `.mp3` by
  filename** — that coupling is gone, along with the blog's sticky player.

- **Keywords** are the one filtering vocabulary shared by both sections, normalized through
  `Web.Keywords` (`parse/1`, `normalize/1`, `tally/1`, `slugify/1`) so `"New York"` and
  `"new-york"` are one token. A post's keywords live in its frontmatter (`keywords:`, or Obsidian's
  `tags:`; `Blog.set_keywords/2` rewrites the line in place from the admin); a log's live in the
  `audio_logs.keywords` column, normalized in the changeset. Both sections sort by **most recent**
  or **most witnessed** with the sort and `?keyword=` filter in the URL — "witnessed" means
  `analytics_hits` page views for posts and `audio_plays` rows for logs.

- **Admin content managers** are split one per section: `/admin/blog` (batch `.md` drop, flags
  posts missing keywords, image library) and `/admin/logs` (metadata-first form; the upload is
  consumed on submit so a rejected save orphans nothing, and the `AudioDuration` JS hook reads the
  file's duration in the browser). `/admin/content` 301s to `/admin/blog`.

- **Frontend**: hand-written CSS only — Tailwind v4 runs with `source(none)` so **no utility
  classes generate**; heroicons must be safelisted in `assets/css/app.css`. Design system is
  **"UC Press / Valley print"** (replaced the old black-ground "hairline mono" look): paper ground
  (`--paper`, `--paper-raised`, `--paper-sunk`, `--paper-deep`) under ink text (`--ink` … `--ink-4`),
  `--rule`/`--rule-strong` hairlines, and pigment accents (`--color-orange` poppy, `--color-jade`
  laurel, `--color-dodger` valley dusk). Type: **Sorts Mill Goudy** (`--font-serif`, the libre
  revival of Goudy, who cut California Old Style for UC Press) carries headings + body via
  `--font-heading`/`--font-body`; **IBM Plex Mono** is the instrument voice — `--font-ui` for nav,
  buttons and labels, `--font-data` (same family, `tabular-nums`) for stats, timestamps and tables.
  Both webfonts load in `root.html.heex`; the old `--font-mono` stack led with `'Cascadia Code'`,
  which is not a webfont, so visitors actually got Courier New.
  The **wordmark** is `WebWeb.CoreComponents.wordmark/1` — one `<span class="wm-l">` per letter,
  each with a fixed (never random) rotation/shift/kern in `em`, shared by the homepage overlay and
  the sticky header. Wrappers carry `aria-label="streetscissors"`, since the name is no longer a
  single string in the DOM (two homepage tests assert it).
  `CoreComponents.baker_wordmark/1` is the stretched-and-cropped display line (homepage photo
  hero, `/negatives` masthead). Its geometry is **measured off the rendered font** with canvas
  `actualBoundingBox*` metrics, never guessed — `getBBox()` returns the layout box and is useless
  for this — so each line's `x`/`length` make its *ink* span 0..1000 and the `viewBox` trims 3.5%
  off each end of the ink band.
  `/negatives` runs three modes off one LiveView: the sheet view (image first, all controls
  beneath it), the sortable index (`?mode=index&sort=date|format&dir=asc|desc` — the sort is
  patched into the URL so it can be linked), and a **frame view**
  (`/negatives/roll/:roll/frame/:n`) that gives an individual photograph its own address and
  links back to the contact sheet it was cut from. `Negatives.list_frames/1` enumerates a roll's
  published frames, so the strip under a sheet fills in on its own as scans are uploaded.
  **Page theme — "darkroom"** (`assets/css/negatives.css`): `/negatives` carries the hero's look
  inward — inverted paper/ink tokens on a near-black ground, Bebas display face, orange at half
  opacity. **Careful:** under `.darkroom` `--ink` is *light*, so surfaces meant to stay dark (the
  plate mat behind photographs) must key off `--paper-*`, not `--ink`.
  **Section theme — "blueprint steel"** (`assets/css/steel.css`): every `/fitness*` page puts
  `steel` on its outermost element (fitness index/wiki/show/biometrics, all `rides_live` views),
  which re-inks the *same tokens* to a steel blue-grey ground with white rules and **League Spartan**
  in every voice (a libre stand-in for Futura, which is not licensable for web). Hot metal
  (`--color-orange` `#ff6a2b`) is reserved for figures and interaction — headings are struck back to
  `--ink` by a rule in `steel.css`, so don't reintroduce `color: var(--theme-color)` on headings
  there. New section pages need only the `steel` class; style with tokens and they inherit. All tokens live in one `:root` block in `app.css` — **pages should
  read tokens, never literal hex**. Deliberate dark exceptions: the `/pc` terminal (`pc.css`), the
  plate mat behind contact sheets (`negatives.css`), and the admin layout. esbuild bundles
  `assets/js/` (only `app.js`/`app.css` are served — vendor deps must be imported into them, never
  referenced as external `<script>`/`<link>`).

## Deployment

Containerized (`Dockerfile`, `docker-compose.yml`); `deploy.sh` / `start_prod.sh` drive releases
(`rel/`); **Caddy** is the reverse proxy (`Caddyfile`, `Caddyfile.prod`). Production secrets/config
resolve at runtime in `config/runtime.exs` (`:admin_password`, mailer, etc. come from env there).
SQLite DB files live in the repo root (`web_dev.db`, `web_test.db`, `street_scissors_prod.db`);
migrations auto-run on release boot via the supervised `Ecto.Migrator`.
