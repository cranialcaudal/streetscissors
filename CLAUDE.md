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
  new admin routes belong in that live_session. `WebWeb.AdminNav` runs second and feeds the rail
  (current path, waiting counts); it skips views the router didn't mount (`socket.router == nil`),
  because the root layout's sticky newsletter overlay inherits the session's hooks. Most admin LiveViews also belt-and-suspenders check
  `session["admin_user"]` in `mount/3`. The `SetCurrentUser` plug only exposes `@admin_mode` to
  templates — **it does not protect routes.** Non-admin pages with admin-only actions (e.g. the
  fitness landing's log buttons) gate per-event on the session flag.

- **Private by default.** The public GitHub repo is the site's code only. `content/` (apart from
  `content/templates/`), photos, `scripts/`
  and the `/pc` reading files are gitignored and live only on the host. **Never put personal
  details in code**: they belong in `content/` or `.env` with a neutral fallback, so a fresh clone
  still builds and boots. For example:
  - `content/england2026/trip.json` and `call.md`
  - `content/emails/welcome.md`
  - `content/fitness/meals-week.json`
  - `AUTHOR_NAME`, `MACHINE_NAME` and `NEGATIVES_PATH` in `.env`

  The vault's root holds only `about.md` and folders. `content/notes/` is the author's private
  planning (no public page renders it; `notes/calendar.md` shows at the admin-only
  `/admin/fitness/calendar`). An unfinished post is a file in `content/blog/` with `draft: true`.
  `/food` and `/england2026` are public but unlisted: out of the sitemap, disallowed
  in robots.txt, and `noindex, nofollow`.

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
  - Blog embeds also support `![[ride:123]]` — a ride card via `Web.Rides`, with Komoot's picture of the route when the ride is clear.
  - **Drafts**: `draft: true` in the frontmatter takes a post off the site. `Blog.list_posts/0`
    and `get_post/1` do not see drafts, so nothing built on them does (index, feeds, sitemap,
    almanac, `/pc`, letters); only the admin passes `drafts: true` or calls `list_all_posts/0`.
    The author's own session can open a draft at its address, marked and `noindex`.
  - **The editor** (`/admin/blog/:slug/edit`, `AdminLive.BlogEditor`) edits the **whole file**,
    frontmatter included, with the page it makes beside it (`Blog.preview/2`, `Blog.to_html/1`).
    `Blog.read_source/1` returns the text with a revision (its SHA-256) and
    `Blog.write_source/4` **refuses to save over a file whose revision moved**, since the vault
    is edited in Obsidian too. The author then takes the disk's version or saves over it, in
    which case the replaced text goes to the vault's `.trash/` first. Saves are written beside
    the file and renamed over it. "New post" (`Blog.create_draft/2`) starts from
    `content/templates/blog-template.md`, the template Obsidian inserts, as a dated draft.
  - **The image library** is `Web.Blog.Images`, under the uploads root at `/uploads/images/`.
    It was `priv/static/images/uploads` in the checkout, which a release does not serve from,
    so an upload answered 404 until the next deploy. Images from the old folder are still
    listed at their old address.
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

- **Backups** (`Web.Backup`, `lib/web/backup/`): four things, each kept the way that suits it.
  The database is a nightly `VACUUM INTO` snapshot, reopened and integrity-checked, 14 kept.
  The written content (`Backup.Content`: `content/`, `scripts/`, the `/pc` reading files, the
  recipe seed, `test/private/` — never `.env`) is a `tar.gz` that is unpacked and compared hash
  for hash before it counts, and **a version is written only when the manifest's fingerprint
  changed**, so the 30 kept are 30 versions; `last-run` in the backup dir records the nights
  that found nothing new. The negatives (`Backup.Photos`) and the captain's logs' media
  (`Backup.Uploads`, minus `staging/`) are rsync mirrors with no `--delete`. Everything goes to
  the external drive when `Backup.MirrorWatcher` sees it plugged in. The database's and the
  negatives' mirror folders are never created (their presence is the "drive is in" signal); the
  two newer ones are made one level deep by `Backup.claim_mirror/1`, only inside a folder that
  is already there. `Backup.catch_up/0` runs at boot for the nights the machine slept through.
  The mirror paths are exported by the systemd unit, not `.env`.
  **`Backup.Drill` rehearses a restore weekly**: the newest snapshot is copied to a scratch
  file, opened on its own connection, integrity-checked and has every table counted; the
  newest content archive is unpacked and its fingerprint recomputed against the one in its
  name (`Content.restore_check/1`); the newest copies on the drive get the same when it is in.
  The outcome is the `restore_drill` setting, shown on the overview and watched by the monitor.

- **The machine watches itself** (`Web.Monitor`, every 15 min by Quantum). `Web.Monitor.Probe`
  makes the checks that cost something: the **certificate** the proxy serves (verified as a
  browser would; warns under 21 days left, since Caddy renews at 30), the **proxy** (`GET
  /health` on the site's own name), **DNS** (the A record and this machine's public address,
  both asked of public resolvers directly because `/etc/hosts` maps the domain to loopback
  here), the **disk**, and the systemd user **units** in `MONITOR_UNITS`. The pass also watches
  `SystemStatus.local_checks/0`, stores what it found in the `monitor_state` setting, and the
  overview reads that (`Monitor.last/0`) rather than probing on mount. Only a `:fail` is mailed:
  on its second pass running, again each day, and once when it clears. A lookup that could not
  be made is a `:warn`, never a `:fail`. Mail goes through `Web.Notify` (the `notify_email`
  setting, else `NOTIFY_EMAIL`; an Oban job on `mailers`), which also announces a held
  guestbook signature. Every probe takes its outside world as options and `test.exs` runs none.
  `GET /health` sits in a scope with no pipeline, so it sets no cookie and logs no hit;
  `.github/workflows/uptime.yml` asks it from outside, which is the only thing that can see the
  machine being off. **There is no dynamic DNS**: the registrar's panel has no API, so a changed
  address is mailed with the value to type in.

- **Feature areas** beyond the blog: fitness (`Web.Fitness` + `Web.Fitness.Vault` markdown regimen/wiki;
  **`/fitness` is one day to a page** (2026-10-07; it was an accordion of all seven): `/fitness`
  is always today by `Web.Clock`, a tzdata-free US-Pacific helper, and `/fitness/day/<weekday>`
  is that day whatever today is, so the day being looked at is in the address and a reload
  keeps it. The days link with `navigate`, never `patch` (a patch would carry one day's ticked
  boxes onto the next day's list). The strip of days at the top prints each day's one word
  (`theme:` in `weekly/<day>.md`: "legs", "arms", "cardio") and fills today in hot metal. The
  day's checklist leads the page; under it sit
  **The Week**: `Web.Fitness.Week` reads
  `content/fitness/week.md` and `WebWeb.FitnessWeek` renders it, untimed chips for visitors and clock
  times for the admin only, so the public page never says when he's out of the house), Komoot-synced rides
  (`Web.Rides` + `Web.Rides.KomootSync`). **Komoot is the only input**: `/fitness/rides` mirrors
  every *recorded* tour, private ones included, as the **Activities** page — a lightbox in the
  manner of `/negatives`: sport pills filter the page via `?sport=`, the newest activity in view is
  featured on its plate (`Activity.plate/1`) under a band for the last 7 and 28 days, then one
  sideways-scrolling **shelf per sport**, largest first (`WebWeb.Activity` components; the ‹ ›
  buttons are the `.ShelfScroll` colocated hook), and the totals are one quiet Pacific-local
  line per year at the foot.
  Activities under 0.2 mi (or with no distance) are excluded at the query — `Rides.list_rides/0`
  and `get_ride/1` — while `komoot_index/0` still sees them so the sync doesn't re-import them.
  These pages are the one place `.steel` gets rounded corners back: `rides.css` outranks steel's
  `border-radius: 0 !important` with `.steel.activities …` selectors. `Web.Rides.Units` speaks
  Komoot's vocabulary (sport names, Distance/Duration/Avg speed/Uphill) and formats Pacific dates.
  `visibility` no longer hides anything.
  **Komoot draws the activity, and the watch says what the body did** (since 2026-10-05). For
  the three days before that the site drew every route itself, from a track it cut by its own
  zones; that is gone (`ride_tracks`, `Web.Rides.Route`/`Track`, MapLibre, the `RouteMap` hook).
  - **The plate is Komoot's embed** (`Rides.embed_url/1`: `…/tour/<id>/embed?profile=1&gallery=1`,
    plus `share_token=` for a private tour). The ride page adds "Open on Komoot"
    (`Rides.tour_url/1`), and the cards show Komoot's static map, cached by `Web.Rides.Thumbs`
    and served at `/fitness/rides/:id/thumb?v=<fingerprint>`. What makes this safe is **Komoot's
    own privacy zone**, set in its app: Komoot cuts it out of everything it hands anyone but
    the owner.
  - **Everything a visitor is shown comes from a read made with no login**
    (`Client.public_tour/2`, with the share token for a private tour). The owner's view of a
    route, the whole of it, is never fetched: the listing's `map_image` is ignored, and a
    thumbnail is named `<ride id>-<hash of the stranger's map URL>.jpg`, so a picture fetched
    from any other URL (an earlier cut, or the whole-route images an older version kept as
    `<id>.jpg`) can never be served for the ride. `Thumbs.sweep_all/1` deletes those on every
    pass that reads.
  - **`rides.stranger_view` is what a stranger is given, and only `"clear"` is shown through
    Komoot** (`Rides.clear?/1`; the embed, the link and the picture all key off it):
    - `"clear"`: a route that stays away from every private place.
    - `"exposed"`: the tripwire, `Web.Rides.Privacy.verdict/1`. `RIDE_PRIVACY_ZONES`
      (`lat,lng`, `;` between several, **in `.env`, never in code or tests**, which use
      invented ground) is the site's own note of what Komoot's zone is meant to hide. A
      stranger's view that **begins or ends** within 100 m of one is exposed: a working zone
      trims exactly that, so the zone is gone, moved or not applied. This is the alarm.
      With no zones set nothing is checked; a setting that can't be read exposes everything.
    - `"passing"`: the ends are trimmed and the route comes back within 100 m in between.
      **A zone trims where a tour starts and ends, not a pass back through it mid-tour**, so
      a ride that came home and went out again lands here in ordinary use: 2 of 64 did on the
      first pass. Held back like an exposed tour, and **not a fault**: nothing is mailed. It
      shows again once the tour is split or trimmed in the app.
    - `"hidden"`: Komoot refuses a stranger the whole tour (`403 AccessDeniedPrivacyZone`,
      which the client returns as `:hidden`) because it never leaves the zone. **That is an
      answer, not a failure.** Counted as a failure it kept the ETag from ever being stored,
      and the pass re-read the listing and half-failed every hour.
    - `nil`: not asked yet. Nothing of Komoot's is shown for it, public or not.

    Anything but clear shows a blank plate and the site's own figures, and is looked at
    again on every pass that reads the listing. `SystemStatus.ride_privacy/0` fails while any
    listed ride is exposed, so the overview shows it and the monitor mails it; passing rides
    are counted in its detail and leave it green. The admin says how many, never where.
  - **Private tours are shown through Komoot share links.** The sync asks for a tour's share
    token the first time it sees it private (`Client.share_token/2`, which creates one when
    there is none) and keeps it; a link that stops working is asked for once more.
  - **Heart rate and energy come from Apple Health** (`Web.Rides.Workout`, `health_workouts`),
    because Komoot keeps neither: every tour's `kcal_active` is 0, and its track carries
    position, height and time. A workout pairs with the ride whose start is nearest its own,
    within 10 minutes (`Rides.attach_health/1`, at read time; nothing is stored on the ride).
    There are two ways in, both ending in `Rides.store_workouts/1`:
    - **Apple's own export** (`Web.Rides.AppleHealth.Export`), dropped on `/admin/rides`. It
      is read as a stream (`unzip -p` through a `Port`, a line at a time), keeping only the
      workouts that match a ride and the heart-rate samples inside them.
      `Web.Rides.HealthImport` runs it in a supervised task, one at a time (the import is
      whichever process holds the module's name), and **deletes the file whatever happens**.
      The upload is written by `WebWeb.HealthExportWriter` straight into an inbox **beside**
      the uploads root (mode 0700): never `/tmp`, and never under `uploads/`, which the proxy
      serves. `HealthImport.clear_inbox/0` empties it at boot.
    - **`POST /api/health/ingest`** (`HealthWebhookController`), for the Health Auto Export
      app's JSON. **Closed until a token is made** on the admin page (or `HEALTH_WEBHOOK_TOKEN`
      is set); only the token's SHA-256 is kept. A workout's `route` is never read.

    A workout with no energy of its own (Komoot's watch app writes none) gets the sum of the
    watch's active-energy samples over it.
  - **The pages lead with the body** (`WebWeb.Activity`): `health/1` sits above the plate
    (average, peak, energy; on the ride page also the lowest, the time in five zones and the
    trace, with the `.HeartTrace` hook), `recent/1` gives the last 7 and 28 days, and the
    yearly line carries kcal and average bpm. Zones are shares of
    `Rides.heart_rate_ceiling/0`, the highest rate any workout on file reached, since the site
    is told nobody's age. A figure that covers only some activities says how many.
  Each ride's figures come from the tour *listing*; there are no planned routes, GPX upload or
  live tracking (removed 2026-09-14; `/fitness/rides/live` and `/live` redirect to the archive).
  The hourly Quantum pass copies edits via `changed_at` (reading the tour as a stranger again),
  mirrors privacy on every read, and **deletes rides whose tour left the
  listing** — except when the listing comes back empty, which is treated as a
  glitch rather than a wiped account. A stranger's read that fails fails the tour, the same as
  a failed import, and `komoot_changed_at` is recorded last so the next pass tries it again.
  **The hourly pass is built to cost nothing when nothing
  changed**: the API token lives in `Web.Komoot.Auth` (supervised) rather than being re-minted
  every hour — logging in is the call that can lock the account — and the listing is a
  conditional GET against the ETag in `site_settings` (`komoot_etag_tour_recorded`). Komoot's ETag
  is a plain md5 of the listing body, so a 304 provably means no tour was added, edited, deleted,
  **or flipped private/public**. The ETag is stored only when the listing processed with zero
  failures (otherwise a broken import would never be retried), and the admin "Sync now" button
  passes `force: true`. Every pass, hourly or manual, records `komoot_last_sync_at` and
  `komoot_last_sync_result` (`KomootSync.last_run/0`), so a sync that keeps failing shows on the
  admin overview instead of only in the journal.
  The decision of 2026-09-24 against health tracking was a decision against the paid phone
  app, which was the only way in then known. It was reversed on 2026-10-05: Apple's own export
  does the job for nothing. `/fitness/biometrics` and the `biometrics` table stay gone, and
  nutrition stays in the vault's markdown (`meals.md`, `meals-week.json`).
  Newsletter + subscribers,
  guestbook, contact messages, analytics, a `/pc` terminal
  LiveView (its `C:\DOCS\BLOG` mirrors blog posts), RSS feed + sitemap controllers, and a custom
  captcha (`lib/web_web/captcha.ex`, not reCAPTCHA).

- **The prayer pages** (`/Christ/*`, `WebWeb.FaithController`, 2026-10-06): the liturgical day, the
  Hours, the readings at Mass, the Rosary, and the Bible they are read from. **Nothing is fetched
  from another site**, at request time or by the browser, and the pages are the same for every
  reader: no account, no setting, nothing stored. Unlisted like `/food`.
  - **`Web.Bible`** reads one translation from `priv/bible/<name>/` (`index.json` + a JSON file per
    book). The one committed is the CPDV, which is public domain. **A licensed text (the RSV-CE)
    must not be committed**: lay it out the same way outside the checkout and set `BIBLE_PATH`.
    Citations arrive in the lectionary's numbering; `Web.Bible.Versification` carries them to a
    Vulgate-numbered text (Psalms, Joel, Malachi, Zechariah exactly; Esther refused; Tobit, Judith
    and Sirach passed through and marked `approximate`, which the page says).
  - **`Web.Liturgy.Calendar.day/2`** works the day out from the date: seasons with the United
    States' movable days, over `Web.Liturgy.Sanctoral`'s layered plain-text calendars in
    `priv/liturgy/` (calendarium-romanum's General Roman Calendar, then `usa-en.txt`, then
    `ocd-en.txt`, the Discalced Carmelite proper as revised in 2023). An entry replaces the entry
    with the same identifier in an earlier layer, which is how a rank is raised and a saint moved.
  - **`Web.Liturgy.Lectionary`** is citations only (`priv/liturgy/lectionary.json`, the dioceses of
    the United States, 2023 to May 2027). A later date borrows the newest date in the file that
    was the same liturgical day, and the page says which. It matches on the US calendar, so a day
    only Carmel keeps shows the general readings and says so. The days with several Masses were
    empty upstream and were filled in by hand.
  - **`Web.Liturgy.Hours`** lays Lauds, Vespers and Compline out from the four-week psalter and
    prays them from the hosted Bible. The approved English office is under copyright: no
    antiphons, intercessions or collects, and the fixed prayers (`Web.Liturgy.Prayers`) are the
    traditional public-domain wordings. `Web.Liturgy.Fast` is the Rule of Saint Albert's season
    (September 14 to Easter, Sundays and solemnities excepted) beside the Church's own days.
  - **`/Christ` is the whole day on one page** (`?date=` for any other day), **and only the day**:
    the saints of the day by name (a life is on the saint's own page), the fast in a line, and
    each prayer written out behind its own `<details>`, so it opens in place with no JavaScript.
    The essay on the Carmelite fast came off the page on 2026-10-07; don't put explanation back.
    Each prayer is a component in `FaithHTML` (`office/1`, `masses/1`, `midday/1`,
    `rosary_text/1`) because it is also a page of its own. `app.js` only enhances: it opens the
    prayer it is time for by the reader's clock, steps the Rosary bead by bead from the `<li
    data-bead>` list the page already carries, and lets ← → follow `rel="prev"`/`rel="next"`.
    Nothing is stored. `/Christ/calendar` is a month of days; `/Christ/bible/go?q=` opens a typed
    citation.
  - **`Web.Liturgy.Saints`** (`priv/liturgy/saints.json`) holds a life for 270 of the calendar's
    278 entries: the opening summary of the English Wikipedia article (CC BY-SA 4.0, shown with
    its source). Pictures are the articles' lead images where Commons records a free licence,
    shown with author and licence, in `priv/static/images/saints/`, which is gitignored, so a
    missing file just means no picture. Every match was checked by hand; do not regenerate the
    file from search results without doing the same.
  - All Souls and the Order's commemoration of its dead carry the rank `:commemoration`. The
    general calendar's titles were reworded to the Roman Missal's English names.
  - **Page theme: the brown scapular** (`faith.css`, the only stylesheet these pages have).
    `.faith` re-inks the site's tokens as `.steel` and `.darkroom` do: brown wool ground, cream
    type, and red thread. `--stitch` is the sewn line (always `dashed`: the panel's edge and the
    three seams) and `--accent-ink` is the same red lifted to pass as small text on brown.
    **Under `.faith` `--ink` is light.** Print goes back to black on white.
  - The address is `/Christ`, capital and all (renamed from `/faith` on 2026-10-07); `/faith/*`
    and `/christ/*` 301 there (`LegacyRedirectController.christ/2`). The code keeps the old
    name: `FaithController`, `faith.css`, `.faith-*`.
  - `priv/faith/guide.md` (the essay on the fast) is kept on disk but nothing renders it.

- **Captain's logs** (`Web.Audio`) are the blog's sibling, not a feature of it: DB-backed
  recordings — **video or audio** — at `/logs` and `/logs/<slug>` (`WebWeb.LogsLive.Index`/`.Show`).
  `/audio` 301s to `/logs`. **A blog post no longer picks up a sidecar `.mp3` by filename** — that
  coupling is gone, along with the blog's sticky player.
  - **An entry is titled by the day it was recorded**, not by a title anyone types: `Log.title/1`
    renders `recorded_on`, the slug *is* the date (`2026-09-18`), and `seq` makes room for more
    than one recording in a day (`2026-09-18-2`, marked "Entry 02"). `caption` is an optional
    line, never the title. The section wears the NX-01 console look (`logs.css`, the `.nx01`
    token block; **under it `--ink` is *light***, so anything meant to stay dark keys off
    `--paper-*`). There is no stardate: it was derived from the date, shown twice, and meant
    nothing — the console speaks through its instruments instead, so the rail carries a real
    reading (`{n} on file`, or the log's own designation) in the panel's mono voice.
    Posters and video are shown at **full colour** — the rides archive's `saturate()` muting
    reads as a fault on footage rather than as calm.
  - **The page is shaped like the rides archive**: newest entry in view gets the theater
    (`LogEntry.plate/1` + a figures panel), everything else is one chronological run of cards,
    and the years are a footnote. **No card mounts a player** — opening `/logs` fetches posters
    and nothing else, which a test pins.
  - **Delivery is one progressive file** (since 2026-09-22; it was an HLS ladder played by
    hls.js). `Web.Media.Transcoder` (supervised, concurrency 1, `nice`-d) drives ffmpeg through
    a `Port`, parsing `-progress pipe:1` into throttled PubSub broadcasts on `"log:<id>"`. Video
    becomes one 720p `video.mp4` (`+faststart`), audio one `.m4a` plus an ffmpeg `showwavespic`
    waveform as its poster, and the browser's own `<video>`/`<audio>` plays either — no player
    library. **Video is pinned to `fps=30` and `-level:v 4.0`**: the booth's WebM has 1 ms
    timestamps and no frame rate, and without the filter ffmpeg padded it out to a real
    1000 fps, which libx264 labelled level 6.0 and which Safari and many hardware decoders
    refused. `Web.Media.FFmpeg` owns every argument list and resolves its binaries through
    `:ffmpeg_bin`/`:ffprobe_bin` so the suite runs against stubs in `test/support/`. The
    transcoder decides an entry's real `kind` from the probe, so a file uploaded as video with
    no video track is corrected to audio rather than pointing at a file that was never written.
  - **Sources are gone after a transcode, so an encode change is applied with
    `Web.Media.reencode/1`**: it re-runs a ready entry from its own rendition (its MP4, or a
    legacy ladder's `v0/index.m3u8`), clearing the trims already baked in. On prod, through
    `bin/web rpc`.
  - **The player (`LogEntry.plate/1` + `.LogPlayer`) owns its plate**: `phx-update="ignore"`,
    so a patch — counting a witness is one — never resets it. Its state is a class that only
    repeats what the media element reported: `is-loading` from the click, `is-playing` on the
    element's own `playing` event, `is-error` on an `error` event, a refused `play()` or 15 s
    of nothing, with **Try again** and **Open the file**. `start()` calls `play()` inside the
    click with nothing awaited first, because Safari refuses a `play()` that isn't.
  - Each entry owns a directory `logs/<slug>-<token>/` (`Web.Uploads.entry_dir/1`). The token is
    for **cache safety**: a re-transcode writes a new directory and swaps the pointer, so nothing
    at a path ever changes and the one-year `immutable` header is honest.
  - **Caddy serves `/uploads/*` off disk** (both Caddyfiles), so no BEAM process is in the byte
    path, with Range requests for seeking. Its `.m3u8`/`.m4s` `Content-Type` rules are dormant
    leftovers of the HLS era, kept so an old URL still answers correctly.
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

- **The scanner studio** (`/admin/scanner`, `WebWeb.AdminLive.Scanner`) takes a roll from film on
  the glass to a sheet on `/negatives`, on the host the scanner is plugged into.
  - **`Web.Scanner.Bed`** (supervised) owns the flatbed: one `scanimage` `Port` at a time (a second
    request is `{:error, :busy}`), progress and results on PubSub `"scanner"`, a hard timeout that
    kills the OS process, and device listing run off the caller. A scan is written as
    `<target>.partial` and renamed only on exit 0, so a failed scan never leaves a truncated TIFF
    that looks like a strip. The LiveView never runs a scan itself; the slow tools go through
    `start_async`.
  - **`Web.Scanner.Driver`** is pure argument-building and parsing (the `Web.Media.FFmpeg`
    split). Every scan passes `--source "Transparency Unit" --film-type "Negative Film"`; a strip
    is 300 dpi cut to its format's **holder rectangle** (`-l -t -x -y`, mm, from
    `SCANNER_AREA_35MM` / `SCANNER_AREA_120`; 620 uses 120's), a keeper 2400 dpi cut to its
    frame's region from `frames.json` plus a margin. **One strip placement per scan** — there is
    no bed-wide strip detection. SANE lists webcams too, and first: only a `:scanner` is ever
    used (`Driver.pick/1`; `SCANNER_DEVICE` pins a backend by id *prefix*, since the id carries
    the USB address).
  - **`Web.Scanner.Pipeline`** runs the same tools as the `negatives` command — `film-develop
    analyze`/`develop` and `digital-contact-sheet-maker` (config `:film_develop_bin`,
    `:contact_sheet_bin`; found on PATH, which is why the systemd unit's PATH includes
    `~/.local/bin`). **Nothing stands in for them**: a missing or failing tool is an
    `{:error, text}` the page shows. There used to be a fallback that invented `frames.json` and
    composed a stretched sheet with ImageMagick; don't bring it back — invented frame rectangles
    put the public grease-pencil rings in the wrong place. `publish_roll/4` re-checks both gates
    itself and refuses otherwise; `catalog.csv`'s `frames` is the strip count. The next roll
    number is the lowest free one, as `negatives` picks it. Reordering, rotating or deleting a
    strip deletes `frames.json` (it now describes other strips), so Gate 1 fails until the roll
    is analysed again. A keeper's raw scan goes to `raw-frames/frame-NN.tiff` and only the
    developed `frames/NN.png` is served.
  - **No simulation in production.** `Web.Scanner.Simulation` draws pretend scans only when
    `:scanner_simulation` is set, which `dev.exs` and `test.exs` do. With no scanner and no
    simulation the page disables its scan buttons and still takes uploads (copied, never
    converted). The suite runs against `test/support/stub_scanimage`, `stub_film_develop` and
    `stub_contact_sheet`, switched by `STUB_*` env vars.
  - Styled only by `adm-scan-*` rules in `admin.css`.

- **Keywords** are the one filtering vocabulary shared by both sections, normalized through
  `Web.Keywords` (`parse/1`, `normalize/1`, `tally/1`, `slugify/1`) so `"New York"` and
  `"new-york"` are one token. A post's keywords live in its frontmatter (`keywords:`, or Obsidian's
  `tags:`; `Blog.set_keywords/2` rewrites the line in place from the admin); a log's live in the
  `audio_logs.keywords` column, normalized in the changeset. Both sections sort by **most recent**
  or **most witnessed** with the sort and `?keyword=` filter in the URL. "Witnessed" counts
  people, not loads: for posts, distinct `ip_hash` in `analytics_hits` unioned across every
  address the post has lived at; for logs, distinct `audio_plays.witness` tokens — an anonymous
  id the browser keeps in `localStorage`, sent by the `.LogPlayer` hook only after 30 s have
  actually played (half the entry if shorter), one row per browser per log by unique index, and
  never recorded for an admin session. Plays from before 2026-09-22 have no token (they were all
  logged against Caddy's `::1`) and count for nothing.

- **The 404** (`WebWeb.ErrorHTML`, `WebWeb.NotFound`, `Web.Nearby`). The page is a **whole
  document** (`error_html/not_found.html.heex`), not a block for a layout: an address no route
  matches has been through no pipeline, and a LiveView that raises on mount is rendered with
  layouts off, so both used to go out as a bare unstyled `<div>`. Controllers and plugs say
  "not here" through `WebWeb.NotFound.render/1`, which turns the layouts off, so a missing
  post, an unknown route and an admin page asked for without a session are the same page.
  `Web.Nearby.suggest/1` reads the missed address and offers up to three real things: posts
  by closeness of name, logs and days by date, rolls by number, exercises by name. **An
  address outside the site's own sections is offered nothing and costs no file read or
  query** — most 404s are scanners. It never raises. Styled by `not_found.css`.

- **Print**: `writing.css` ends with the post page's `@media print` rules (the year's are in
  `almanac.css`): chrome, the letter form and embed controls are dropped, external links print
  their address after them, and `.blog-post-colophon` (hidden on screen) says where the page
  was published.

- **Sized photographs**: `Web.Negatives` keeps each preview at `widths/0` (480 and 960) as
  well as at 2000, as `<name>-<width>.webp` beside it, made from the preview on first
  request. `?w=` on `/negatives/frame/…` and `/negatives/preview/…` asks for one; **a width
  not in the list is the full preview**, which is what stops `?w=` filling the disk.
  `Negatives.sized_url/2` and `srcset/1` build the addresses. The strip of prints and the
  almanac's day thumbnails ask for 480; the frame view and a frame embedded in a post carry a
  `srcset`. The contact sheet itself is left at one size: its neighbours are prefetched, and a
  prefetch cannot follow a `srcset`.

- **Share cards** (`Web.ShareCard`, `WebWeb.ShareController`): the `og:image` of a post, a
  frame and a roll is a 1200x630 card of the work itself. A post is its title set in Goudy on
  paper over the wordmark and date; a frame or a sheet is the picture whole on the darkroom's
  ground (the WebP previews those pages used are cropped through by a 1.91:1 unfurl, and not
  shown at all by some). **A page only names its card** (`post_url/1` etc., a stat at most)
  and the card is drawn by ImageMagick when `/share/…` is first fetched, so no page render
  shells out. Files live in `cards/` under the uploads root, named with a fingerprint of the
  title and date or of the source image; the URL carries it as `?v=`, so the year-long cache
  header is honest and a retitle sweeps the old file. The title reaches ImageMagick through
  `caption:@file`, never as an argument. The two faces are vendored in `priv/fonts/` (OFL).
  `/share/*` has no pipeline, like `/health`. Logs already have a 16:9 JPEG poster.

- **Tending the content** (2026-10-04), both under **Write** in the admin's rail:
  - **`Web.Keywords.Index`** (`/admin/keywords`) is the one place a keyword is changed
    everywhere: `usage/0` lists each with the posts and logs that carry it (drafts and
    unpublished logs included, or the old spelling resurfaces when they publish), and
    `rename/2` rewrites every post's frontmatter and every log's column. Renaming to a keyword
    that exists **merges** the two.
  - **`Web.ContentHealth`** (`/admin/health`) reports broken internal links and images,
    `![[embeds]]` that resolved to nothing (`Blog.Embeds.unresolved/1`), published posts with no
    description or keywords, library images and regimen modules nothing uses
    (`Fitness.Vault.audit/0`), and rolls whose marks are withheld with the reason and the
    command that fixes each (`Negatives.Sheet.status/1`). **A link is checked by dispatching it
    through `WebWeb.Endpoint`** (`ContentHealth.ask/1`) and reading the status, so there is no
    second list of valid paths to drift from the router; the request is loopback under a bot
    user agent, which the analytics plug skips. External links are counted, not followed. The
    report renders every page it checks, so the LiveView builds it with `start_async`.

- **Answered and followed** (2026-09-29): the social half of a feed, in the site's terms.
  - **`Web.Pieces`** is the one vocabulary for "a piece": refs `"post:<slug>"`, `"log:<slug>"`,
    `"frame:<roll>/<n>"` (roll padded like `/negatives/roll/013`). `resolve/1` checks it exists and
    is public (a draft log is `:error`); `from_path/1` maps a site path to a ref. Letters,
    webmentions and the admin all store and resolve refs through it.
  - **The almanac** (`Web.Almanac`, `AlmanacController`): `/day/:date` and `/almanac/:year`, built
    from dates every section already has. Posts use their `date`, logs `recorded_on`, rolls the
    sheet's scan date (the day it came out of the tank), and rides their Pacific-local day.
    **Never times**, the same rule as the public week. An empty day or year is a **404**, and
    prev/next only point at days with work, so crawlers can't walk an infinite calendar. Every
    piece's date links to its day (`.day-link`). The year page's `@media print` rules are the
    printed edition; its button uses `data-print` and one delegated listener in `app.js`, since
    controller pages have no hooks.
  - **Letters** (`Web.Letters`, `WebWeb.LettersLive`): contact messages with a `piece`,
    `may_publish` (the writer's consent) and `published_at` (the author's choice); both are needed
    to publish. `LettersLive` is a nested LiveView `live_render`ed at the foot of posts, logs and
    frames. **A nested LiveView cannot read connect_info**, so each host passes `"remote_ip"` in the
    signed session: `ClientIP.from_conn` on the blog's controller page, and `@client_ip` from
    mount on the logs and negatives pages. The frame view keys its id per frame
    (`letters-frame-013-4`) so patching between frames remounts it. Styled in `letters.css`, token
    only, with `--letters-act` re-pointed per theme (paper, `nx01`, `darkroom`). Letters land in
    the admin Inbox, which shows each one's piece and offers Publish / Take down only when
    `may_publish` is set.
  - **Feeds**: `/feed` is the whole site (posts, ready logs with an `<enclosure>` so podcast apps
    follow them, and rolls), newest 30, with excerpts rather than full text by choice.
    `/feed?keyword=` follows a keyword across the blog and the logs; an unknown one is a 404. The
    blog and logs indexes set `@keyword_feed` for a second `<link rel="alternate">` and show
    "Follow … by RSS".
  - **IndieWeb markup** (`WebWeb.Microformats`): `h-entry` on posts, logs and frames (`p-name`,
    `dt-published`, `e-content`/`u-photo`, `p-category`, hidden `u-url` and `p-author h-card`), and
    a representative `h-card` on the homepage. The name comes from `AUTHOR_NAME` and falls back to
    the site name. **`rel="me"` is opt-in** through `REL_ME_URLS` (https only), empty by default,
    which keeps `SEO.person_json_ld_tag/0`'s no-cross-linking decision.
  - **Webmentions** (`Web.Webmentions`, `WebmentionController`): `POST /webmention` sits in a scope
    with no pipeline at all (no session, no CSRF, no `accepts`), is rate-limited per IP, requires
    the target to be one of our pieces, stores the mention as `pending`, and answers 202.
    `Web.Workers.WebmentionVerifier` (Oban queue `webmentions: 2`) fetches the source through an
    **SSRF guard**: it resolves the host, refuses any non-public address (loopback, RFC 1918,
    link-local, CGNAT, ULA, mapped v4), and re-checks every hop of at most 3 hand-followed
    redirects, with a 10 s timeout and a 1 MB body cap. The resolver and Req options are
    configurable, so the suite never touches DNS or the network
    (`Web.WebmentionsTestResolver`, `Req.Test`). A verified link is `held`; the author approves it
    at `/admin/citations`, and then it shows in `LettersLive` as "Cited by", linked
    `nofollow ugc`. A source that doesn't link (yet) or answers 410 is `gone`, and a later ping can
    bring it back. Only the author rejects, and a rejection sticks.
  - **Webmentions sent** (`Web.Webmentions.Outgoing`, `webmentions_sent`): hourly, every
    published post is rendered and each `<a href>` to another host that has no row yet is
    queued (`Web.Workers.WebmentionSender`). The job finds the target's endpoint (a `Link`
    header first, then the first `<link>`/`<a rel="webmention">`), posts `source` and `target`,
    and records `sent`, `no_endpoint` (never asked again) or `failed`. A link that leaves a
    post it was sent from is announced once more and becomes `withdrawn`. Both the target and
    the endpoint go through the receiver's SSRF guard and Req options. Posts and anchors only:
    an iframe or an image is not a citation. `/admin/citations?show=sent` lists them, with
    "Try again". `:webmention_send` false turns the pass off.

- **The admin — "the composing room"** (rebuilt 2026-09-29), the print shop's back office. **Every
  admin rule lives in `assets/css/admin.css`** under `.admin-layout` (`adm-` prefix), and pages are
  built from `WebWeb.AdminComponents` (`page_head`, `panel`, `tabs`, `rows`, `pill`, `stat`,
  `drop_zone`, `copy_field`, …): no `<style>` blocks, no inline colour. The old per-page blocks
  (`CmsStyles`, the fitness "mission control", the rides table) are gone. Plex Mono is the
  instrument voice; Goudy is kept for page titles and for words people wrote. The pigments are
  lifted for the dark ground (`--adm-act`/`-live`/`-held`/`-fail`, each ≥4.5:1). theme.css styles
  bare `button`s, so every admin button class states its hover in full.
  The rail groups pages as **Write** (Blog, Captain's Logs, Fitness, Keywords, Content health), **Darkroom** (Scanner), **Mail** (Inbox, Guestbook,
  Citations, Newsletter) and **Sync** (Activities), plus Overview and Settings, with badges for
  open messages (letters included), held signatures, held citations and failed transcodes. It folds to a Menu bar at ≤900px. **View state is in the
  URL** here too: `?box=` (inbox), `?show=` (guestbook, keywords), `?filter=missing|drafts`
  (blog), `?tab=` (fitness).
  `/admin/dashboard` is the **Overview**: a "Needs you" queue (each row a link to where the thing
  gets done, shown only when non-zero), counts, traffic, and `Web.SystemStatus` (snapshots, the
  content's versions, the mirror drive, Komoot's last run, ride privacy, failed mail jobs). Contact messages live at `/admin/inbox`, and site settings at
  `/admin/settings` (the Spotify playlist, the newsletter's test address). The newsletter page
  holds drafts (`newsletter_drafts.status = "draft"`, which becomes the send's record when sent), a
  sandboxed preview built from `Web.Email.preview_page/2`, a `[Test]` send, and the subscriber
  list. New guestbook signatures are announced on `"guestbook:admin"` so the approval queue fills
  live; the public `"guestbook"` topic still hears only approvals. The blog manager keeps its
  batch `.md` drop and keyword editing, and `/admin/content` 301s to `/admin/blog`. The logs booth's
  `.LogRecorder` hook and its `data-role` markup are load-bearing (see above); restyle around them.

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
  beneath it), the sortable index (`?mode=index&sort=format&dir=asc`), and a **frame view**
  (`/negatives/roll/:roll/frame/:n`) that gives an individual photograph its own address and
  links back to the contact sheet it was cut from.
  **The URL is the whole of the view state, and every control is a link.** A roll has its own
  address (`/negatives/roll/013`, padded — `13`/`roll013` resolve and canonicalise to it), so
  `handle_params/3` is the only place that sets state and the browser's own Back button walks
  the archive a step at a time. `WebWeb.NegativesLive.Format` composes every destination and
  **omits defaults** (`logs_path/2` and `blog_query/2` are the same idea), so one control never
  clobbers another — sorting used to hardcode `/negatives?mode=index&…`, which dropped the roll
  you were on and rewrote the path when you came in via `/archive`. The old `?slug=` form
  patches to the roll's real address. The arrows **stop at the ends rather than wrapping**: the
  archive is a list, and "12 of 31" would otherwise be a lie. `phx-window-keydown` gives ← → and
  Escape (one element per key — a bare binding ships every keystroke to the server), and it is
  the only thing left that pushes a patch of its own, because a key cannot be a link.
  **The archive's contents sit in a left rail beside the sheet** (`.negatives-layout`, the same
  grid as `/how-to`'s contents rail), scrolling inside itself because 31 rolls is taller than a
  screen, with a colocated hook keeping the current roll in view. It folds at **1200px, which is
  geometry not taste**: the rail plus its gap costs 280px and `.sheet-plate` is
  `min(column, --stage-h × aspect-ratio)`, so a landscape sheet wants 775px and 1152−280 clears
  it while 1052−280 does not. Below that the rail hides and the full table is the index.
  The index's **Frames column counts real exposures** via `Sheet.frame_count/1` (`catalog.csv`'s
  `frames` is the *strip* count, out by 3–6×); it reads a `frames.json` per roll, which is why
  it belongs to the table that renders on request and not to the rail that renders every visit.
  Sheets are prefetched one neighbour either side — stepping otherwise stalls on a ~300KB fetch.
  **A frame is a finished print, not a strip scan.** `Negatives.list_frames/1` reads a roll's
  `frames/` directory — the archive pipeline's own output, `NN.png` from `film-develop
  develop` — and frame numbers run 1..N across every exposure on the roll, as `frames.json`
  numbers them. (They used to be the *strip* files in the folder above, so "frame 3" of a 120
  roll meant its third strip of three exposures; the strip scans are no longer addressable
  one by one, since the sheet already shows every one of them.) `/negatives/frame/:roll/:frame`
  serves a downscaled copy and `.../original` the print itself, as an attachment.
  **Printed frames are circled on the sheet in grease pencil**, and the circle is the link.
  `Web.Negatives.SheetLayout` transcribes the GIMP assembler (`film-contact-sheet.scm`, which
  lives in `~/.config/GIMP/*/scripts/` and **cannot be vendored**) to map a frame's rectangle
  in `frames.json` onto the assembled sheet; `Web.Negatives.Sheet` does the I/O and refuses to
  answer unless **two gates** pass — the strip files on disk must still match `strips[].file`
  (a stale `--analyze` is the common failure; 4 of 30 rolls were stale when this was built),
  and one of the three paper sizes must compose to the sheet's real pixel dimensions. Either
  gate failing means *no marks*, never marks in the wrong place. So drift in the script makes
  rings vanish — `test/private/negatives_layout_test.exs` is what reports that, by name and
  with the `negatives --analyze NNN` to fix it. `Web.Negatives.GreasePencil` generates each
  ring from `phash2({slug, frame})`: varied but fixed, like the wordmark's letter offsets, so
  no two frames are circled alike and nothing twitches between the static render and the
  connected mount. The rings sit on `.sheet-plate`, a box carrying the sheet's exact aspect
  ratio — **an overlay can only register with a picture if some element has the picture's
  dimensions**, which is why the plate specifies width only (add a height and `aspect-ratio`
  is ignored) and why its mat is a border, not padding (`inset: 0` resolves against the
  padding box).
  **Page theme — "darkroom"** (`assets/css/negatives.css`): `/negatives` carries the hero's look
  inward — inverted paper/ink tokens on a near-black ground, Bebas display face, orange at half
  opacity. **Careful:** under `.darkroom` `--ink` is *light*, so surfaces meant to stay dark (the
  plate mat behind photographs) must key off `--paper-*`, not `--ink`.
  **Section theme — "blueprint steel"** (`assets/css/steel.css`): every `/fitness*` page puts
  `steel` on its outermost element (fitness index/wiki/show, all `rides_live` views),
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

The live site is a `MIX_ENV=prod` release under the systemd user unit `streetscissors.service`,
behind Caddy (`caddy-streetscissors.service`, `Caddyfile`). **`./redeploy.sh` is the deploy**:
assets, then the release, then a restart and a health gate. Before it builds, it copies the
release that is serving to `_build/prod/rel/web.previous` (only while the site answers, so a
second attempt after a bad deploy does not replace the good copy with the broken one), and
**`./rollback.sh` swaps the two and restarts**; run twice, it swaps back. It does not touch the
checkout or undo a migration.

There is also a container path (`Dockerfile`, `docker-compose.yml`, `deploy.sh`,
`Caddyfile.prod`) and `start_prod.sh` for running the release by hand. Production secrets/config
resolve at runtime in `config/runtime.exs` (`:admin_password`, mailer, etc. come from env there).
The live database is outside the checkout (`DATABASE_PATH`, exported by the unit); `web_dev.db`
and `web_test.db` in the repo root are the development and test databases. Migrations auto-run
on release boot via the supervised `Ecto.Migrator`.

**This machine is both the server and the workbench**, so `config/dev.exs` keeps a development
server off the live site's ground: its backups go to `tmp/dev_backups/` rather than the real
backup folder (where a snapshot of `web_dev.db` would become the newest "live" snapshot), and
it sends no webmentions. To poke at code without booting the app at all, use
`mix run --no-start -e …`; against the live release, `_build/prod/rel/web/bin/web rpc '…'`.
