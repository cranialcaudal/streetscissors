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

- **Private by default.** The public GitHub repo is the site's code only. `content/` (apart from
  `content/templates/` and `content/architecture-notes.md`), photos, ride thumbnails, `scripts/`
  and the `/pc` reading files are gitignored and live only on the host. **Never put personal
  details in code**: they belong in `content/` or `.env` with a neutral fallback, so a fresh clone
  still builds and boots. For example:
  - `content/england2026/trip.json` and `call.md`
  - `content/emails/welcome.md`
  - `content/fitness/meals-week.json` and `biometric-goals.json`
  - `AUTHOR_NAME`, `MACHINE_NAME` and `NEGATIVES_PATH` in `.env`

  `config/test.exs` points the vault, trip, emails, blog and negatives paths at invented fixtures
  in `test/support/fixtures/`. Checks against the real content go in the gitignored
  `test/private/`. Anything read at compile time (`Web.Blog.Embeds`' `emissions.R`, `PcLive`'s TXT
  files) must tolerate the file being absent.

- **File-based content systems** (all read from disk at request time; the repo's `content/` dir is
  an Obsidian vault):
  - **The blog** (`Web.Blog`): **strictly typed work** — markdown in `content/blog/` (env
    `BLOG_PATH`), served at `/blog` and `/blog/<slug>`. The index sets the first post in the current
    sort/filter as a lead story over a contents list; its styles live in `writing.css`, scoped to
    `.writing` (square, in the header controls' voice) because `blog-bento-*` classes still carry
    the fitness pages. A slug is the filename; a title-shaped one ("Tide's Out") 301s to its
    `Keywords.slugify/1` form once a file by that name exists, and view counts are keyed by the
    slugified form so old-URL hits carry over. Supports YAML frontmatter
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
  e.g. Resend), a `Task.Supervisor`, **Oban** (supervised since the prod-hardening pass, on the SQLite
  `Oban.Engines.Lite` engine — stock Oban emits Postgres-only SQL that `ecto_sqlite3` rejects), and
  `Web.Scheduler` (**Quantum** cron jobs), plus `Web.Media.Transcoder`, which runs the captain's
  logs' ffmpeg queue one job at a time. The transcoder deliberately does *not* use Oban: its retries
  would re-encode an unreadable source over and over. It resumes instead from the `audio_logs` rows
  left at `pending`/`processing`, which it requeues on boot.

- **Feature areas** beyond the blog: fitness (`Web.Fitness` + `Web.Fitness.Vault` markdown regimen/wiki;
  the `/fitness` landing is the regimen accordion — today auto-expanded via `Web.Clock`, a
  tzdata-free US-Pacific helper — under **The Week**: `Web.Fitness.Week` reads
  `content/fitness/week.md` and `WebWeb.FitnessWeek` renders it, untimed chips for visitors and clock
  times for the admin only, so the public page never says when he's out of the house), Komoot-synced rides
  (`Web.Rides` + `Web.Rides.KomootSync`). **Komoot is the only input**: `/fitness/rides` mirrors
  every *recorded* tour, private ones included, as the **Activities** page — a lightbox in the
  manner of `/negatives`: sport pills filter the page via `?sport=`, the newest activity in view is
  featured with Komoot's route map and a figures panel, then one sideways-scrolling **shelf per
  sport**, largest first (`WebWeb.Activity` components; the ‹ › buttons are the `.ShelfScroll`
  colocated hook), and the mileage is one quiet Pacific-local line per year at the foot.
  Activities under 0.2 mi (or with no distance) are excluded at the query — `Rides.list_rides/0`
  and `get_ride/1` — while `komoot_index/0` still sees them so the sync doesn't re-import them.
  These pages are the one place `.steel` gets rounded corners back: `rides.css` outranks steel's
  `border-radius: 0 !important` with `.steel.activities …` selectors. `Web.Rides.Units` speaks
  Komoot's vocabulary (sport names, Distance/Duration/Avg speed/Uphill) and formats Pacific dates.
  `visibility` no longer hides anything — it only decides whether a ride page uses Komoot's
  `/tour/:id/embed` (which refuses non-public tours) or the static map cached by
  `Web.Rides.Thumbs` at `/fitness/rides/:id/thumb`. Each ride is built from the tour *listing*
  alone: there is no stored GPS track, planned routes, GPX upload, privacy zones, or live tracking
  (all removed 2026-09-14; `/fitness/rides/live` and `/live` redirect to the archive). The hourly
  Quantum pass copies edits via `changed_at`, mirrors privacy on every read, and **deletes rides
  whose tour left the listing** — except when the listing comes back empty, which is treated as a
  glitch rather than a wiped account. **The hourly pass is built to cost nothing when nothing
  changed**: the API token lives in `Web.Komoot.Auth` (supervised) rather than being re-minted
  every hour — logging in is the call that can lock the account — and the listing is a
  conditional GET against the ETag in `site_settings` (`komoot_etag_tour_recorded`). Komoot's ETag
  is a plain md5 of the listing body, so a 304 provably means no tour was added, edited, deleted,
  **or flipped private/public**. The ETag is stored only when the listing processed with zero
  failures (otherwise a broken import would never be retried), and the admin "Sync now" button
  passes `force: true`.
  Newsletter + subscribers,
  guestbook, contact messages, analytics, a `/pc` terminal
  LiveView (its `C:\DOCS\BLOG` mirrors blog posts), RSS feed + sitemap controllers, and a custom
  captcha (`lib/web_web/captcha.ex`, not reCAPTCHA).

- **Captain's logs** (`Web.Audio`) are the blog's sibling, not a feature of it: DB-backed
  recordings — **video or audio** — at `/logs` and `/logs/<slug>` (`WebWeb.LogsLive.Index`/`.Show`).
  `/audio` 301s to `/logs`. **A blog post no longer picks up a sidecar `.mp3` by filename** — that
  coupling is gone, along with the blog's sticky player.
  - **An entry is titled by the day it was recorded**, not by a title anyone types: `Log.title/1`
    renders `recorded_on`, the slug *is* the date (`2026-09-18`), and `seq` makes room for more
    than one recording in a day (`2026-09-18-2`, marked "Entry 02"). `caption` is an optional
    line, never the title. A stardate is still derived from the date — this section keeps its
    NX-01 console look (`logs.css`, the `.nx01` token block; **under it `--ink` is *light***, so
    anything meant to stay dark keys off `--paper-*`).
  - **The page is shaped like the rides archive**: newest entry in view gets the theater
    (`LogEntry.plate/1` + a figures panel), everything else is one chronological run of cards,
    and the years are a footnote. **No card mounts a player** — opening `/logs` fetches posters
    and nothing else, which a test pins.
  - **Delivery is HLS.** `Web.Media.Transcoder` (supervised, concurrency 1, `nice`-d) drives
    ffmpeg through a `Port`, parsing `-progress pipe:1` into throttled PubSub broadcasts on
    `"log:<id>"`. Video becomes a two-rung fMP4 ladder (720p + 480p, keyframes forced onto a
    shared grid so a player can switch); **audio skips HLS** for one progressive `.m4a` plus an
    ffmpeg `showwavespic` waveform as its poster. `Web.Media.FFmpeg` owns every argument list and
    resolves its binaries through `:ffmpeg_bin`/`:ffprobe_bin` so the suite runs against stubs in
    `test/support/`. The transcoder decides an entry's real `kind` from the probe, so a file
    uploaded as video with no video track is corrected to audio rather than pointing at a
    playlist that was never written.
  - Each entry owns a directory `logs/<slug>-<token>/` (`Web.Uploads.entry_dir/1`). The token is
    for **cache safety**: a re-transcode writes a new directory and swaps the pointer, so nothing
    at a path ever changes and the one-year `immutable` header is honest.
  - **Caddy serves `/uploads/*` off disk** (both Caddyfiles), so no BEAM process is in the byte
    path for a page of segments. It must set `Content-Type` for `.m3u8`/`.m4s` explicitly — Go's
    MIME table knows neither, and hls.js refuses a playlist typed as octet-stream.
    `WebWeb.Plugs.MediaServe` is the dev-time equivalent (Range, ETag, HEAD).
  - `/admin/logs` is a **recording booth**: `getUserMedia` preview, one record button, then trim
    in/out and a poster frame chosen over the take. Those are *numbers* — ffmpeg applies them
    server-side, nothing is re-encoded in the browser. The blob reaches the server through
    LiveView's chunked uploader (`this.upload/2`), and the `<.live_file_input>` **must stay inside
    the form**: that upload works by putting the file on the input and relying on `phx-change` to
    allocate an entry, and outside a form it fails silently on both sides. The recorder's choices
    are staged over the socket into their own assign *before* any bytes move, because the change
    event the upload triggers would otherwise rebuild the form and wipe them.
  - Sources are **not kept** after a successful transcode, so a trim is a one-time decision;
    caption, keywords, date, published and the poster stay editable. A failed entry keeps its
    source and can be retried from the admin.

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
  The sticky header (`CoreComponents.blog_header/1`, styled only in `header.css` — no inline
  styles) flanks the wordmark with a matched pair of `.header-action` controls. The paper site's
  interaction rule is **ink reads, poppy acts**: anything pressable wears `--accent-ink`
  (`#a73b19`, the poppy deepened to pass small-text contrast) *at rest*, not only on hover, and
  targets are ≥44px; solid ink marks the current choice (the header, `/blog`, post pages). The back control
  shows just the destination ("return to fitness" → "Fitness") and carries the full "Back to …" as
  its aria-label; both controls fold to equal icon squares at ≤900px.
  **Flash notices** are said once, by the layouts: `Layouts.app` (every `:default` LiveView via
  the router's `live_session` layout, and controller pages via `put_layout`) and
  `admin.html.heex` both render `Layouts.flash_group/1`, pinned under the sticky header and styled
  by hand in `flash.css` — the generator's daisyUI classes never generated, so every flash used to
  print as bare text below the page. Don't add flash markup to page templates. The group sits
  outside `.steel`/`.darkroom`, so it keeps paper tokens there like the header does; inside
  `.admin-layout` it goes dark. Only the full-screen dialogs above it (the dispatch overlay, admin
  login) say their own.
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
