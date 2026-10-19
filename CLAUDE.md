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
  left at `pending`/`processing`, which it requeues on boot. `Web.Darkroom.Sessions` is a
  `DynamicSupervisor` of the print editor's LightCraft processes, one per open editor.

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
  machine being off. **GitHub runs a schedule only from the repository's default branch**
  (`master`): while that file is only on a work branch, the check from outside does not exist. **There is no dynamic DNS**: the registrar's panel has no API, so a changed
  address is mailed with the value to type in.

- **Feature areas** beyond the blog: fitness (`Web.Fitness` + `Web.Fitness.Vault` markdown regimen/wiki;
  **`/fitness` is one day to a page** (2026-10-07; it was an accordion of all seven): `/fitness`
  is always today by `Web.Clock`, a tzdata-free US-Pacific helper, and `/fitness/day/<weekday>`
  is that day whatever today is, so the day being looked at is in the address and a reload
  keeps it. The days link with `navigate`, never `patch` (a patch would carry one day's ticked
  boxes onto the next day's list). The strip of days at the top prints each day's one word
  (`theme:` in `weekly/<day>.md`: "legs", "arms", "cardio") and fills today in hot metal. The
  section's tabs (Wiki, Activities) sit above that strip, as they do on the other fitness pages
  (they were at the foot of the page until 2026-10-07); then the day's checklist; under it sit
  **Logging** (admin only, the inline "Log" button on a checklist line): the wiki decides
  what can be logged, not the `exercises` table. `Fitness.loggable_exercise/1` makes the row a
  log hangs from the first time an exercise is logged; until 2026-10-08 it only looked the
  slug up, the table knew 17 of 126 exercises, and the tests passed because they seeded the
  row first. The form shows the last entry, saved entries list under the day ("Logged
  today", with Remove), and entries are dated by `Web.Clock`. **The modal's backdrop must not
  carry `phx-click`**: LiveView gives a click to the nearest ancestor that has one, so it
  closed the form on every click inside it.
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

- **The exercise wiki** (`/fitness/wiki`, `content/fitness/exercise-wiki/<group>/<slug>.md`,
  cleaned up 2026-10-08). Every page has the same five frontmatter keys and the same sections
  (`**Goal:**`, `### Execution`, `### Why it works`, `### Programming notes`), and three
  conventions that are easy to break:
  - **The heading says whether the claim is measured**: `### Why it works` on a page with
    `references:`, `### Why it works (theory)` on one without. Citations come only from
    `references.md`, whose entries are checked against PubMed before they are added.
  - **A page never names a day of the week.** It names the session ("the lower day", "the
    afternoon lift"), because the week gets rearranged and 24 pages went stale when it was.
  - **`functional_category` is a shared vocabulary of thirteen**, not free text; a new spelling
    is nearly always an old category.

  `Web.Fitness.WikiCheck.problems/0` finds all three again (and missing keys or sections, a
  citation not in the bibliography, a figure that does not draw); `/admin/health` lists them
  with the broken links, and `test/private/` holds the real vault to zero. Pages nothing links
  to are in `content/archive/exercise-wiki/`, outside the vault so nothing reads them; moving a
  file back restores it. `Vault.update_exercise/3` carries unknown frontmatter through, as
  `update_day/2` does: the admin form has no `references:` field and used to strip it on save.
  - **The figure** (`Web.Fitness.Figure`, `Web.Fitness.Clip`, `WebWeb.FitnessFigure`): a page
    whose exercise has `figures/<slug>.json` in the vault leads with a figure doing it; all 113
    pages have one (2026-10-09). The file is a few
    **poses that say where the body is** (pelvis, the back's lean and curl, and where each hand
    and foot is or points), never joint angles: elbows and knees are solved so each limb
    reaches, so a planted foot stays planted and no bone changes length. `build/1` **refuses** a
    figure that cannot reach, goes through the floor, pops a joint across its limb between
    poses, or names a key it does not know, saying which pose; a refused file shows nothing
    and is listed on `/admin/health`. Between poses the pelvis travels a straight line, except
    that **a body rocking over its knees rides up on them** (`ride_up/5`): the hips of a
    kneeling rollout travel an arc, and the straight line pressed the knees into the floor.
    - **The page plays a film of it** (`Web.Fitness.Clip`; his direction: "less abstract… a
      game engine of sorts… preload GIFs/video", then "too lumpy yet sleek"). The same loop is
      drawn once, on the bench, as a body in 3D with the muscles in the page's `anatomy:` lit,
      and kept as a silent H.264 loop of about 100 KB with its first frame as a poster; a phone
      decodes it and builds nothing. `mix fitness.film` hands each figure's joints
      (`Figure.track/2`, 24 fps) to the camera in `priv/figure/`: `render.mjs` (node, no
      packages) drives headless Chrome over its debugging port through `render.html`, where
      `figure3d.js` lifts the flat joints into 3D, builds the body from about a hundred rounded
      cones and ellipsoids (each muscle its own volume, set flush) and marches rays through
      their distance field, in three flat tones with an ink line; the frames are piped to
      ffmpeg. About 85 seconds a figure on this machine's Intel GPU (`--use-angle=gl-egl`;
      without it Chrome marches on the CPU). **The film's ground is steel's `--paper-sunk`
      written as a number in `render.html`**, so the picture has no edge on the page: change
      one, change the other, and film again.
    - **The body is smooth and the muscles lie under it** (2026-10-10, "he's too lumpy"): in
      `figure3d.js` a shape that is a muscle is sunk (`SINK`) and melted in widely (`MELT`),
      so it rounds the form without standing off it, and the tones step softly. **A hand is
      read off what is beside it** (`touching/3`): a fist round a bar, handle or band, a flat
      palm on a floor, box, wall or ball, open otherwise; no figure file says which. Knees,
      elbows, wrists and ankles have their own small shapes. **A dumbbell's handle is square
      to the forearm**, and a held prop's `"grip": "across"` (a curl, a press) or `"neutral"`
      (a hammer curl, a row, a carry; the default) says which way it runs. **A figure file
      with a key the running release does not know shows nothing on the live site**, so a
      new key waits for a deploy (`grip` and `stance` are both live).
    - **The body is built bone first** (`body/3`; the chest 2026-10-10, "the worst part",
      and the rest 2026-10-11). Bone is thin and comes first: a rib cage narrower than the
      shoulders, collar bones, shoulder blades, a pelvis, a bone and its joints in each
      limb. A muscle is then laid from the bone it starts on to the bone it ends on
      (`belly/9`), so it follows the joint between them: the pectoral and the lat go with
      the upper arm, the buttock with the thigh, the belly's wall with the ribs and the
      pelvis. And it keeps its volume (`swell/2`): a muscle that bends a joint is measured
      straight, so it thickens as the joint bends; one that straightens a joint is measured
      round the outside of it (`round/3`), so a bent joint draws it thin. **Muscles lie
      nearly flush**: one that stands a unit proud of its neighbour draws an ink line down
      its edge, which on the belly read as flaps. The shorts need their own seat between the
      legs now that the thighs are not thick enough to meet. More shapes cost time: a film
      went from about 55 seconds to 85.
    - **The body is held to a man's measurements, not to the eye** (2026-10-11, "the waist is
      off"). `mix fitness.film --measure` (`priv/figure/measure.mjs`, node, no GPU, 7 s)
      stands the figure upright and puts a tape round the solid the camera draws (`solid/1`,
      the shader's distance field again in JavaScript; **keep the two in step**, they share
      `FIELD`). Thirty-one heights, breadths, depths and girths are printed beside the mean
      of the 609 lean men (body-mass index 21 to 24) of ANSUR II, the US Army's public survey
      of 2012, each as a share of stature. What the first reading found: hips a quarter too
      wide (the hip joints were 4.8 from the middle; a man's are 4), a crotch a fifth too low
      (the pelvis was a ball round the hip joints, and the thighs ran together under it), a
      waist that was a long tube from the hips up, a head a third too broad, a neck and upper
      arm a sixth too thick, a wrist a quarter too thin, shoulders a hand too high. Thirteen
      measures were more than 8% out; five are now and none is the body's: the ankle's height
      and the forearm to the grip are the pose engine's, a shoe is wider than a foot, and the
      head is a ball by design (below). `test/web/fitness_measure_test.exs` holds the proportions (skipped without node).
      What to know before touching `body/3` again:
      - `HIPS`, `KNEES`, `FEET` in `lift/2` are how far the leg's joints are from the middle;
        a front view's pose has its hips at 5 and they are brought in to `HIPS`.
      - **The pelvis is tall**: joints near its floor, crotch 2.4 below them, crests at the
        navel. The waist is only the gap between crest and lowest rib.
      - **Two shapes near the midline, one from each leg, run together** (each smooth join
        adds a little, and six in a row add a bridge). Keep a leg's shapes 0.9 clear of it.
        The shorts' legs are two tubes each for that reason, and for a clean hem.
      - `socket/2` hangs a resting arm 1.4 below the pose's shoulder, which is 3 too high;
        the upper arm is drawn a tenth short while it hangs. The real cure is in the engine
        and means reaching every pose again.
      - The pose's hand point is the middle of a fist, so the wrist is drawn 2.1 short of
        it; under a flat palm it is at the point, and that forearm is a fifth too long.
      - With the hips a man's width a bell does not fit between knees a hip's width apart:
        `kb-swings` and the goblet squats carry the `stance` key (live since the deploy of
        2026-10-11).
    - **The weights are iron on steel, and a lit muscle is set into the body** (2026-10-11).
      `gear/3` has a fourth prop shape, the disc (flat-faced, between two points; type 4 in
      the shader and in `check.mjs`), and a material `IRON`: dumbbell heads, barbell plates
      and a kettlebell's foot are discs. A worked muscle's colour stops at the muscle's own
      footprint (`LIT_EDGE`) with a dark seam round it (`SEAM`, carried out of `body()` in
      `gSeam`); it used to reach a unit further with a soft edge and read as a patch of
      light. `tmp/film-all.sh` films every figure for the live site and can be run again.
    - **The head is a ball with the author's drawing traced on it** (2026-10-11: "Draw the
      face with this style. Round out the head and just trace the image. It's my abstract
      drawing"). His drawing is a circle with four strokes: a line down the middle of the
      face, two arcs from temple to temple that make a lens, and a short stroke across the
      middle line low down. There is no skull, jaw, nose, brow, ear or hair any more. The
      strokes are not shapes: `face()` in the shader inks them where the hit point lies on
      the ball, each stroke being where a plane cuts it, so they turn with the head and say
      which way it looks. The `FACE_*` constants are the trace, **laid on 11 degrees higher
      than drawn** because the camera looks down by that much. A copy of the drawing is
      `tmp/figure-face-drawing.jpg` (not in git). The flat fallback drawing still has its
      own plain head.
    - **A frame is drawn in bands** (`BANDS`, in `draw`), and that is what a black frame was.
      This machine's graphics driver (i915) resets any single job that has not made way
      within 640 ms of something else asking for the card: the desktop redrawing, a second
      render, its own heartbeat every 2.5 s. The page's WebGL context is then lost and
      every later frame is black, with nothing said except in the kernel's log
      (`journalctl -k | grep "preemption time out"`). With a hundred shapes a whole 1080
      frame takes about a second, so every render died the moment the desktop was in use.
      Each band is finished before the next and takes tens of milliseconds; a lost context
      now raises an error. Two renders at once, which always gave blank pictures, gave good
      ones when tried. **If black frames ever return, read the kernel's log first.**
    - **Films are content, not code.** They live in `figures/` under the uploads root (which
      the proxy serves), each named by a hash of its own bytes, with `clips.json` saying which
      film is whose, what it was filmed from, and where each pose begins. The live site's
      uploads are outside the checkout, so its films are made with
      `UPLOADS_PATH=<the service's> mix fitness.film`; nothing is deployed for a page to play
      one. **A film is shown only for the figure it was filmed from** (`Clip.find/2` compares
      a hash of the figure file and the muscles lit): edit a figure or a page's `anatomy:` and
      that page goes back to the flat drawing until it is filmed again, and `/admin/health`
      lists it (`Clip.unfilmed/0`). A new look does not retire a film; `--all` films everything
      again (about 2 hours 40 minutes).
    - **`Clip.muscles/1` is where the wiki's free text meets the camera's seventeen muscles.**
      The page names what is lit under the film ("Working: Quads, Glutes"), since the colour
      says where and not what. A page whose anatomy names no muscle (the cardio pages) lights
      nothing.
    - **The flat drawing is the fallback, and always current**: `build/1` bakes the loop at 12
      frames a second as SVG, every part a rounded stroke as thick as the part (`@thick`),
      drawn back to front in layers, clipped at the drawn ground, moved by SMIL in the markup.
      What is held can go **behind** the body (`"weight": "behind"`). Limbs within a few
      percent of straight are drawn straight, or a planted leg wobbles at the knee; a knee's
      "front" is the way the figure faces until it lies down, or the knees of a deep hinge bend
      backward.
    - Equipment that stands still is `mat`, `box`, `block` (a bench, a wall, a bag, the
      water's surface), `disc` (a bar end-on, a roller), `dome` (a BOSU), and `line` (a band or
      cable from its anchor to a hand, or a rigid pole). `floor: false` is for hanging,
      swimming and a front view used as a view from above.
    - **Some keys are for the film alone**, because a flat picture cannot show them: a pose's
      `side` (the hands to the near or far side of the body), `spread` (how far apart the hands
      are), `flare` (elbows out to the sides: a face pull drawn flat has to put them over the
      head), a line's `depth` (a band anchored beside the body, as a Pallof press needs) and a
      disc's `ball` (a hanging bag, not the end of a roller).
    - **The picture moves with no script**, and the `.Figure` hook only works the clock, the
      film's or the drawing's: pause, and a button per pose. The video plays by `autoplay`, so
      it does not wait for the page's socket (a hook mounts only once that connects, and on
      `localhost:4000` it never does: the origin check refuses it). **Reduced motion is honoured
      in the markup**: the one `<source>` carries `media="(prefers-reduced-motion:
      no-preference)"`, so a reader who asked for stillness is offered no file and keeps the
      poster, until they press Play or a pose and the hook hands the video its file
      (`data-film`). The Play button reads off the video's own `play`/`pause` events. The
      element is `phx-update="ignore"`. A hold (one pose) is its poster as an `<img>`. Styled by
      `fitness_wiki.css` with the wiki's two pages, tokens only.
    - **Authoring**: start a new figure from a posture that is already right (copy the pose of
      a finished figure in the same position and change only what moves), then
      `mix fitness.film --stills DIR <slug>` and **look at every pose**. A file that validates
      is not thereby a picture of the exercise: of the figures written by a small model that
      reported "looks right", a third were wrong (a side plank lying flat, elbows over the
      head, a band coming from behind).

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
    **Inside an hour, what people know by heart is a name** (`FaithHTML.known/1`, a closed
    `<details class="faith-known">`): the Our Father, the Glory Be after each psalm, the
    Angelus. Psalms, readings and canticles change daily and stay written out. **The Rosary is
    the order of prayer and the mysteries by name**; each mystery's scripture is behind
    `mystery_scripture/1` (closed, on the written form and on its bead), and the words of the
    prayers are listed once at the foot. Don't write them back out.
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
    Deepened on 2026-10-07 (`--paper: #1e120a`, crimson `--stitch`); `--accent-ink` is as
    saturated as it can be and still hold 4.5:1 on `--paper-raised`, so check before pushing it.
    **Under `.faith` `--ink` is light.** Print goes back to black on white.
  - The address is `/Christ`, capital and all (renamed from `/faith` on 2026-10-07); `/faith/*`
    and `/christ/*` 301 there (`LegacyRedirectController.christ/2`). The code keeps the old
    name: `FaithController`, `faith.css`, `.faith-*`.
  - **It is on the homepage** (2026-10-07): the third skinny card, where "How It Works" was.
    `/how-to` is a link in the home footer beside the almanac, which with `/about` is still
    the only way to it.
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
    so a patch — counting a view is one — never resets it. Its state is a class that only
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

- **The cutting room** (`/admin/cuts`, `Web.Cuts`, `WebWeb.AdminLive.Cuts` and
  `.CuttingRoom`, 2026-10-17, his ask: the "Premiere clone", for logs "from several takes",
  "photos from the archive", "titles and music"). A cut (`log_cuts`) is a timeline and a bin
  of files (`cut_media`); it renders into a captain's log.
  - **The timeline is data** (`Web.Cuts.Timeline`, JSON on the cut): `clips` play one after
    another on one main track (a take with `in`/`out` in ms and `gain`, or a print `still`
    with `frame: "065/6"`, `duration` and `move`), and `titles` and `sounds` sit at an `at` of
    their own. **Everything from the browser goes through `normalize/2`**, which drops what
    refers to nothing (a file not `ready`, a malformed frame) and clamps every number, so a
    saved timeline always renders. Item ids carry their track's letter (`c-`, `t-`, `s-`).
  - **The render is one ffmpeg command** built by `Web.Cuts.Render.args/3` (pure; the graph
    is in its moduledoc): each clip to 1280x720 at 30 with sound of exactly its length (a take
    by input seeking, a print by `zoompan` after scaling up 2x, which is what keeps a slow
    zoom from shuddering), `concat`, titles overlaid in their time (PNG from
    `Web.Cuts.Titles`, ImageMagick in the vendored faces, words through `caption:@`), sounds
    delayed and faded, the `duck` ones pressed down by the main track's own sound
    (`sidechaincompress`), `amix` with `normalize=0`. `test/web/cuts_render_test.exs` renders
    a real cut with the real ffmpeg (skipped without it): the graph is proved by ffmpeg, not
    by reading its text.
  - **A render becomes a log through the logs' own path** (`Cuts.publish/2`): the film is
    staged as a booth upload is, and either a new log is made (`recorded_on` from the form,
    unpublished) or, for a cut already rendered, its log is given the new source as
    `Media.reencode/1` does (off the site while it transcodes). The transcoder makes the 720p
    rendition and poster; nothing on the public side knows a log came from a cut.
  - **The bin is kept, unlike a booth source**: `cutting-room/<cut id>/` **beside** the uploads
    root (which the proxy serves), until the cut is deleted. **It is in no backup** (the
    uploads mirror covers only the uploads root); the published log's film is. Each file gets a
    proxy for the browser (`make_proxy/1`: 480 lines, a keyframe every half second for
    scrubbing), served to the admin alone with Range by `CutMediaController` through
    `MediaServe.send_media/3`; the original is never served. Proxies and renders run under
    `Web.TaskSupervisor` (`:cuts_async`, inline in the suite) and report on `"cut:<id>"`.
  - **The browser plays, the server edits.** The `.Cutting` hook plays the program from
    `data-program` (two `<video>`s taking turns so the next take is loaded before it is
    reached; a print's move as a CSS transform matching the zoompan; titles drawn in the same
    faces at the same fractions of the frame; ducking as a lowered volume) and turns drags and
    trims into events (`move`, `place`, `trim`, `split`, `delete`); the server saves and
    re-renders the blocks. The screen, the playhead and the timecode are `phx-update="ignore"`
    (the hook owns them). Overlapping titles or sounds stack in rows (`lanes/1`). The assign is
    `plan`, not `layout`, which LiveView reserves.
  - Styled by `adm-cut-*` rules in `assets/css/admin/cuts.css`. Existing logs cannot be brought into a bin
    yet: their sources were deleted after transcoding.

- **The scanner studio** (`/admin/scanner`, `WebWeb.AdminLive.Scanner`) takes a roll from film on
  the glass to a sheet on `/negatives`, on the host the scanner is plugged into.
  - **`Web.Scanner.Bed`** (supervised) owns the flatbed: one `scanimage` `Port` at a time (a second
    request is `{:error, :busy}`), progress and results on PubSub `"scanner"`, a hard timeout that
    kills the OS process, and device listing run off the caller. A scan is written as
    `<target>.partial` and renamed only on exit 0, so a failed scan never leaves a truncated TIFF
    that looks like a strip. The LiveView never runs a scan itself; the slow tools go through
    `start_async`.
  - **`Web.Scanner.Driver`** is pure argument-building and parsing (the `Web.Media.FFmpeg`
    split). Every scan passes `--source "Transparency Unit" --film-type "Positive Film"` (the backend's
    "Negative Film" doesn't invert, it pre-corrects the orange mask that `film-develop` removes
    itself; "Positive Film" is the unconverted negative the archive holds); a strip
    is cut to its format's **holder rectangle** (`-l -t -x -y`, mm, from
    `SCANNER_AREA_35MM` / `SCANNER_AREA_120`; 620 uses 120's), a chosen frame is 1600 dpi. **The V550 scans film only at 400, 800,
    1600 and 3200 dpi**, and `scanimage` rounds any other figure to the nearest and exits 0, so
    the driver asks only for those: a strip is scanned at 400 and `Bed` resamples it to the
    archive's 300 (`Driver.strip_resample/0`) before it is renamed into the roll. **One strip placement per scan** — there is
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
  - **Scan is a look; approval is what sends the scanner back** (2026-10-07, the author's
    order of work). `Driver.pass_args/2` scans the whole transparency area in colour at 400
    dpi, the scanner's quickest (28 s), and everything comes from that file in a `start_async`
    (`take_pass/3`): `Detect.read/2` says what the film is and where each strip lies (both
    slots of the 35mm holder are two strips from one pass), the roll is named to match and its
    folder made if it had none, `Pipeline.add_pass/6` cuts each strip at the archive's 300 dpi
    (grey for black and white) and writes **where each lies on the glass to the roll's
    `holder.json`**, and the roll is analysed. `SCANNER_AREA_*` now gives only the holder's
    top and height; the strips' edges are found.
  - **Approved singles are scanned at 1600 dpi, in bands.** `Pipeline.frames/1` lists the
    frames and `suggested?/1` ticks every one the analysis calls well exposed (a reading of
    the negative's tone, not of the picture: the archive held no prints to learn taste from).
    On approval `Pipeline.glass_rect/3` places each ticked frame on the glass from
    `holder.json`, and `Driver.bands/2` gathers frames that are side by side or neighbours
    into one crossing, because **the scanner's time goes with the length of glass it crosses**
    (135 s for the whole holder at 1600; one band took 62 s for three frames). Each frame is
    cut out of its band (`cut_from_band/6`) and developed. Moving, turning or deleting a strip
    deletes `holder.json`: such a strip's frames are scanned one at a time, with 3 mm of room,
    on the understanding that it was put back in the calibrated slot. **What was proposed and
    what was chosen go to the roll's `selects.json`** (`record_selects/3`), with each frame's
    turn (`rotation/2`: landscape unless the author turned it, and the way it is printed).
    The run of scans is the LiveView's, so closing the page stops it after the scan under
    way. The small positives the picker shows are `film-develop analyze --export` output in a
    0700 folder under the system tmp dir, never in the archive.
  - **`film-develop` was reworked on 2026-10-07** (it lives in `~/.local/bin`, outside this repo;
    the copy it replaced is in `~/film-pipeline-backups/2026-10-07/`). What the site relies on:
    - **A frame's rectangle in `frames.json` is the picture itself**, rebate and film edges
      left out. That is why a single scanned in place gets no margin
      (`Driver.keeper_margin(:in_place)` is 0) and why the grease-pencil rings sit tighter.
    - **35mm is cut on the film's fixed 38 mm grid**, so a strip holds however many frames it
      holds and frame numbers run on across strips of different lengths. The old tool cut
      every strip into six and cut through pictures on 19 of the archive's 53 strips.
      `mis_split` and the "Try --frames-per-strip" retry in `generate_frames_analysis/4` now
      only arise for 120 and 620, whose spacing is the camera's.
    - **The roll sets the colour and a frame only its exposure** (the `film` block: base,
      a power per channel, white). Developing frame by frame is what tinted thin negatives.
      `develop` also removes small white dust specks unless told `--no-dust`.
    - The whole archive was re-analysed and every sheet rebuilt that day.
    - **Glass is never film** (2026-10-09; the copy it replaced is in
      `~/film-pipeline-backups/2026-10-09/`). A strip from the scanner studio is the whole
      holder slot, so there is bare glass beyond the film's ends, and the holder's grey edges
      down its sides pass the tool's film test. Three things went wrong from that: the film's
      extent ran on over the glass, the "film base" was read off it (238 where the film's is
      about 170, so no gap between frames ever read as bare), and the 38 mm grid was hung on
      the glass just past the film's end. Roll 035's first strip (two night frames, a third,
      and a fogged leader) had every frame cut 9 mm late. Now `glass_level/1` finds the glass,
      `film_on_glass/5` reads the strip down the middle of its width only, stops the film where
      the glass starts and measures base on the film, and `grid_35mm` looks for gaps on the
      film: between frames, and in the last millimetre inside each end (a cut between frames
      ends on rebate, a leader does not). **A scan that shows no glass (every roll before 031)
      is read exactly as before**, checked strip by strip. The frame is named
      (`FRAME_35MM = 36`, the gap is what the pitch leaves) and `analyze --frame-mm 18` is a
      half-frame camera. Rolls 031 to 036 were analysed by the old rule and are not redone;
      re-analysing one moves its frames by up to 2 mm, and by more on its short strips.
    - **Slide film is a third mode** (2026-10-09, for a roll of E100). `film-develop` has
      `color`, `bw` and `slide`; a slide is already the picture, so nothing is inverted or
      colour-balanced (the roll's brightest highlight is white, the same in all channels, and
      a frame may only nudge its own black and white), frames are found by their **dark**
      gaps, and dust removal is skipped. **The site does not know the mode exists, and the tool tells
      by looking** (`film_look/1`): a roll the page calls colour is a slide when the
      clearest film down the middle of its strips is neutral (a colour negative's orange mask
      makes it far redder than blue) and at least 2% of it is true black. All eleven colour
      negative rolls in the archive read as negatives by it. `roll.json` outranks the look
      either way: a reversal stock under Film or `"process": "slide"` makes it a slide,
      `"process": "negative"` keeps it a negative. The page's own detection still has to call
      the roll **colour** (`Web.Scanner.Detect` knows only colour and black and white, and a
      roll taken for black and white is stored grey). 35mm only.
    - **A slide developed badly is balanced channel by channel** (2026-10-09, six rolls of
      E100 that came out dense with a red black). The slide branch of `film_model` reads, per
      channel and pooled over the roll's pictures, a **black** (taken off: the film's read
      about 7, 2, 2 and every shadow wore it), a **contrast** (`power`: the film is crossed,
      red at twice green and blue through the midtones and level only near white, so each
      channel is bent until the roll's midtones agree, `SLIDE_BALANCE` of the way) and a
      **white** (held further back, since a roll's highlights are lamps and signs). A frame
      then sets its own white and raises its own midtones; one with nothing lit stays night.
      The roll decides the colour, never a frame. `roll.json` may overrule it:
      `"slide": {"lift": 1.2, "balance": 0.6, "warmth": 0.5}`. `film-develop redevelop ROLL`
      develops every single again, but **on a published roll go through
      `Web.Scanner.Pipeline.develop_keeper/2`** (by `bin/web rpc`), which also turns the print
      and remakes its previews. A slide's singles are scanned at **16 bits**
      (`Driver.band_args/5` `deep: true`, when `Scanner.slide?/1`); the print is 8.
    - **Medium format's frame count is read off the film** (`count_by_template/4`): 120 and
      620 are one film in different cameras, and a 620 roll of 6x9 (two to a strip) was being
      cut in three. On a strip on glass, each count from 2 to 6 is laid cut to cut and the one
      whose gaps are all gap wins; `--frames-per-strip` still insists. Scans without glass
      (every roll before 031) are counted as before.
    - **The frame is 36 mm; the spacing is the camera's** (2026-10-09, roll 048, a camera
      that wound 41.8 mm on one strip and 467, 467, 430 px on the next). "38.00 mm apart
      whatever the camera" was wrong. On a strip on glass, a 38 mm grid that puts picture in
      one of its own gaps (`grid_cuts_a_picture/7`; only gaps with a frame kept on each side,
      since past the last frame there may be a fogged leader) gives way to
      **`walk_frames/6`**: the plainest frame is found first (gap outside, picture inside, at
      both ends of a 36 mm window, `_frame_score/5`) and the strip is walked each way from it,
      each next frame looked for from touching the last to 10 mm on, and a frame with no edge
      of its own set one spacing on so the count stays right. The walk is believed only where
      it differs from the grid by more than 2.5 mm, so an evenly wound roll keeps its grid.
      Every strip on glass is then cut as whole 36 mm frames, and **`snap_frames/6`** moves a
      frame up to 5 mm onto its own picture, but only for an edge at *both* its ends (a thin
      frame has edges inside it that pass for one).
    - **A roll's contrast is the whole roll's when few frames score well**, and a dense
      frame may be darkened further (`GAMMA_LIMITS` low end 0.5, was 0.72). "Well exposed" is
      the spread of the *scan's* values, which a dense, overexposed negative squeezes, so on
      roll 048 one thin frame set the contrast for all seven and the rest printed blown.
      Under a third of the roll scoring well, `film_model` reads every frame. **The page's
      small positives and a developed single are the same recipe**: a preview that is too
      bright means the single will be.
    - **A strip's film base is read off its film** when it is on glass. The whole-strip
      reading that feeds `film_model` took in the holder's grey edges, so a colour negative's
      base came out nearly neutral (blue 65 where the film's is 38) and every shadow printed
      blue. Scanner-era colour negatives analysed before this (031) carry that cast until
      analysed again.
    - **Dark film is placed by a template of the frame, not by counting black lines**
      (`grid_by_template/6`, 2026-10-09, roll 037: night pictures on E100). Between two night
      frames a slide's gap is a third of a brightness level darker than the pictures, and a
      dark corner of a picture is exactly as black as a gap, so "is this line black" hung the
      grid on the pictures' shadows and every frame came out 4 to 7 mm off. The strip is now
      read as brightness with its fractions (`middle_trace/2`) and a grid of 36 mm frames and
      2 mm gaps is slid along it under two rules: **nothing of a picture may lie in a gap**
      (a gap is at the strip's own gap level within 6%, or that grid is out), and **a picture
      edge beside a gap is the score**. Frames it places stay on its grid, all the same size.
      A slide is always placed this way; **a negative on glass is, when its gaps do not read
      bare** (thin, fogged or expired film), and otherwise as before. With no evidence at
      all, a strip a whole number of frames long is laid end to end between its cuts
      (`whole_strip/3`). The page's own finder (`Web.Scanner.Detect`) also had to learn that
      a slot showing bare glass past the film's ends holds film even when the film is as
      black as the holder; film that dark is taken for reversal film, in colour.
 Written against a slide made by inverting a
      negative strip, not yet against real E100.
  - **Two pieces in one slot, and a camera that winds unevenly** (2026-10-11, roll 055; the
    copy replaced is in `~/film-pipeline-backups/2026-10-11/`). Two short pieces of film
    laid end to end in one slot are two strips: `film_on_glass` now keeps each stretch of
    film parted by 2.5 mm of glass (`PIECE_GAP_MM`) and each is laid out by itself; one grid
    across both cut the second piece at the first's spacing. **A studio strip that fills
    its slot shows no glass**, so it was read by the oldest rule (a fixed 38 mm grid from
    the film's start, "unaligned"): it is now read line by line like a strip on glass
    (`strip_source` knows it by the studio's mark; scans from Epson's program are left as
    they were). And where the clear film between pictures is plain to see,
    **`frames_by_gaps/4` reads the pictures straight off it**, believed only when every
    stretch is one frame long: strip 4 had a blank stretch after its first frame, and
    every grid and the walk put the rest half a frame out. Thin film falls through to the
    template as before.
  - **The tool looks at its own answer** (2026-10-11, roll 060, his ask: "a feature that
    retries the frame selection… so I'm not always prompting for the fix"). After a 35mm
    strip on glass is laid out, `frames_miss/4` measures how much picture was left outside
    every frame; 12 mm or more and `retry_frames/10` lays the strip every other way (the
    plain grid, the template, the gaps, and `frames_by_runs/5`, which sets frames on each
    stretch of picture and knows nothing of spacing) and keeps the one that leaves least
    out. `frames.json` records it under `relaid` and the run prints "laid again by …".
    **Only pictures left out count as wrong**: thin film reads as bare through its
    pictures, so bare film inside a frame proves nothing. The page does not show `relaid`
    yet, and has no button to ask for another cut.
  - **The bath is read off the clear film** (2026-10-15, rolls 069 and 071: "the fixer
    period was too short"; the copy replaced is in `~/film-pipeline-backups/2026-10-15/`).
    Work in density: fog and the veil of a short fix or wash are density *added* to all
    the film, gaps included, while development is a *gain* on the picture, so blank film
    measures the first and never the second. Three things follow, black and white only:
    - **Each strip may have its own clear film** (`strip_veils`, `gap_level`): read in the
      gaps between its frames, never the brightest of the whole strip (which moves with a
      fogged leader or a strip with no clear stretch, and moving bases on that wrecked
      sound rolls), and used only when the strip's gaps agree among themselves and sit 20%
      off the roll's (`VEIL_STEP`). The roll's contrast is still the roll's, read with every
      strip brought to the roll's base. On the roll's base a clearer strip printed black
      end to end: roll 069's second, roll 059's first three (Dodger Stadium).
    - **`frames.json` carries a `diagnosis`** (`diagnose`) and the page says it after a look
      or an analysis (`Pipeline.bath_notes/1`): `veil` (clear film over D 0.50; the
      archive's sound rolls read 0.22 to 0.39, at the scanner's gamma of 1.8), `uneven`
      (strips' gaps more than 0.20 apart: fog at the roll's start, or fixed apart) and
      `blocked` (over 5% of the pictures under 8-bit 5, where the scan reads noise). Only
      said: a veil of undissolved halide comes off in fresh fixer and **darkens for good
      under any lamp, the scanner's included**, so the advice is to test a cut piece and
      refix before the singles. A veiled or blocked roll's singles are 16-bit
      (`Pipeline.deep?/1`, as a slide's). Nothing digital recovers what lies at the
      scanner's floor: roll 071 (clear film at D 2.0) printed blank from its look.
    - **A negative denser than the holder's black is still film**: read off the glass
      alone, as a slide is, when that finds far more film, and a strip with a quarter of
      its film under `BLACK` keeps those pixels (`DENSE_STRIP_SHARE`). Analysed as black
      and white, roll 071 crashed on an empty gap reading before this.
    - **A negative as black as a slide is told by its gaps** (2026-10-15; the copy replaced
      is in `~/film-pipeline-backups/2026-10-15-slide/`). Roll 071 was filed colour by the
      page and developed as a slide, because both took film mostly darker than the holder
      for reversal film. The film between frames has nothing on it, so it is a negative's
      clearest and a slide's blackest: where film is that dark, gaps are laid on it at the
      35mm pitch, and gaps 2.5 times as bright as the pictures' median (about 0.7 in
      density) make it a negative. `Web.Scanner.Detect` reads the look that way, a row to
      the millimetre between the glass at the film's ends (071 read 3.5 and 4.5 on looks
      rebuilt from its strips, no slide strip past 1.9), and then reads its colour as any
      other film's. `film-develop`'s `film_look/1` lays its frame template as a negative's
      (`clear_gaps`: 071 read 4.4 and 3.7, and only two of the 34 slide strips took such a
      grid at all, at 1.3 and 1.4), and calls a dense negative black and white when its gaps'
      channels part by under 0.4 in density (`MASK_DENSITY`: C-41 reads 0.65 to 1.26, 071
      about 0.2). **Roll 027's pink base reads 0.19**, so a colour roll that dense would be
      taken for black and white: `"process": "negative"` in `roll.json` keeps it colour. Old
      and new tools gave byte-identical `frames.json` for every other roll in the archive.
  - **Medium format, and a strip scanned again** (2026-10-10, roll 023: "a disaster"). Three
    things went wrong at once when one strip of an August roll was scanned again on the site.
    **The strip was the whole bed.** No holder rectangle is configured for 120, so `add_pass/6`
    cut 242 mm: the holder's own plastic past the glass (black in the scan, a block of white on
    the sheet) and 60 mm of glass, which also shrank every picture on the sheet by a quarter.
    With no rectangle, each strip is now cut to its own film and 4 mm of glass either end
    (`film_rows/5`, `film_run/2`); `film-develop strips` paints out any holder left in an older
    file (`holder_mask`). Rolls 023 and 047 were trimmed by hand that day (originals in
    `~/film-pipeline-backups/2026-10-10/`). **The colour was another scanner's.** Epson's own
    program set its levels scan by scan; the site takes what the scanner gives. The same film
    base read 224, 141, 107 in the August strips and 177, 102, 75 in the new one, the roll's
    base is the middle strip's, and the new strip and its three singles printed lavender.
    `film-develop` now reads a roll scanned on two instruments as two (`strip_source/2`:
    "glass" when the strip shows glass or carries the mark the site writes into every scan it
    makes, `@studio_mark`, in the TIFF's description; "plain" otherwise), keeps both models in
    `frames.json` (`films`), and `film` is the glass's, since a single is always scanned on
    the glass. **A single off the glass of a frame whose strip is plain** (singles added to an
    old roll) is developed on the roll's glass model when it has one and read by itself
    otherwise; that second case is not yet checked against a real roll. **The end frames kept
    their rebate**: `trim_to_pictures` stopped at the first line a shade less than bare, so a
    strip's first picture kept 4 mm of clear film (a black bar on the print); it now carries
    over such lines. And **a deleted strip is set aside** in the archive's `.trash`
    (`set_aside/2`), not destroyed: deleting the strip to scan it again took its only scan.
    Still as it was: a strip scanned again joins the end of the roll and has to be moved back
    into place under Strips.
  - **What the author knows of a roll is `roll.json` in its folder** (`Web.Negatives.RollMeta`,
    2026-10-07): when it was shot, camera, film stock, place, notes. **Shot is as exact as is
    known**: `2023`, `2023-06` or `2023-06-14`, and nothing invents the rest. It is typed under
    Roll on the scanner page (saved on change; said before the roll has a folder, it is held
    and written when the first preview makes one) and shown on the roll's page on `/negatives`
    (`.sheet-about`). **The roll is still filed by its scan date** everywhere (folder name,
    index, almanac, day pages, feeds): his choice, so nothing published moves. Other keys in
    the file are kept; `roll001` has the catalog row there from the `negatives` command.
  - **Nothing after a scan holds the bench** (2026-10-07, "it has to move faster after the scan
    is made"). A band's frames are cut and developed in their own `start_async` (`{:develop,
    id}`, three at a time), so the scanner goes straight to the next band and the page is back
    at Load when the last band is in, developed or not. `developing` is frames per roll
    folder, since by then the bench may hold another roll. `film-develop` writes `frames.json`
    whole (beside, then moved) because a frame can be developing while the next look analyses.
  - **A sleeve holds so many strips** (`scanner_strips_per_roll` in site settings, default 7,
    under Roll; blank is saved as the word `off`, since a setting cannot be saved empty and
    blank used to leave the old number in force). **Nothing is decided at the look and
    nothing is published until Publish is pressed** (reworked 2026-10-09, his words: "the
    whole process just needs a rehaul"). It used to give the full roll the left slot's strip,
    start the next roll with the right slot's before anything had been seen, keep that
    strip's singles out of reach until the full roll was settled, and then publish the full
    roll unasked.
  - **Where one roll ends is asked after the load is worked.** The holder takes two strips,
    so the strip that fills a roll often shares the glass with the next roll's first. Every
    strip of a look joins the roll on the bench, past the count if need be, and their singles
    are chosen and scanned together. When the load is settled, `settle_roll/1` looks at the
    count: one strip over, and the page asks which of the roll's last two begins the next
    roll (`#roll-end`; the last is chosen, the other may be picked, and Preview is refused
    until it is answered); the `"end_roll"` event swaps them if need be
    (`Scanner.reorder_strips/2`, singles carried) and cuts with `Pipeline.split_roll/2`,
    which takes the strip's singles, selections and place on the glass with it. A roll with
    exactly its count is simply full: the next Preview opens the next roll. Rolls complete
    and not yet in the catalog are listed on the bench (`#waiting-rolls`,
    `Pipeline.unpublished_rolls/1`) with Publish and Open. Only Publish pressed with frames
    still ticked publishes by itself, after scanning them. "New roll from here" on a strip
    is still there for any other case.
  - The Epson backend sometimes refuses a scan with `sane_start: Invalid argument` when asked
    right after another; the page asks once more after 2.5 s before calling it a failure.
  - **A run cut short is found again** (`Pipeline.owed_singles/1`). The run of scans lives in
    the LiveView and the scan in `Bed`, so a restart of the service kills both; on 2026-10-07
    two deploys landed seconds after Scan was pressed and ten chosen singles were silently
    never made. What was chosen is written to `selects.json` before the scanner starts, so
    "chosen and no print" is exactly what an interrupted run leaves. On opening a roll those
    frames are put back up, ticked, with a notice, if their strips are still on the glass;
    otherwise they are listed over the collection. **`redeploy.sh` waits for the scanner to
    be idle at the moment of the restart**, asking the serving node through the kept copy of
    its release (the build replaces the cookie), and gives up after 15 minutes.
  - **Singles are added to any published roll from one button** ("Add singles to an old
    roll", `Pipeline.identify/5`): the same look and the same comparison as below, made
    against every roll of that width of film, and the roll that fits best is opened with
    those strips up to choose from. Nothing is proposed, only singles owed come back
    ticked, and the prints are on the roll's page as soon as they are developed (the site
    reads `frames/` at request time; no republish). One roll per load. **Publish with
    frames ticked scans them first** (`then_publish?`): it used to publish and drop them.
  - **A strip laid back in the holder is found, not assumed** (`Pipeline.relocate/5`, "Find
    this roll's strips on the glass"). A look that adds nothing: each piece of film on the
    glass is compared with every strip the roll has, by a small picture of it (8 across, a
    row every 0.5 mm, **each row less its own mean**), at every offset within 45 mm and both
    ways up. Taking the row mean off matters: brightness along a strip is mostly frame gaps,
    which all five-frame strips share (0.87 between different rolls); what is left is the
    picture (same film 1.00, any other at most 0.37 on the scanner, line drawn at 0.6). The
    offset goes into the strip's place in `holder.json` and "other way up" into `flipped`,
    which `glass_rect/3` and `cut_from_band/6` honour. It replaces the old put-back path's
    assumption that a strip sits where it first did.
  - **What is on the glass is one thing for the whole archive** (`<archive>/.on-glass`): a
    roll's `holder.json` holds only while it belongs to the most recent look, into any roll.
    Roll 032 once went on claiming its last strips through the whole of roll 033.
  - **Deleting, reordering or turning a strip carries its singles with their frames**
    (`Pipeline.carry_singles/3`): prints are filed by frame number and those operations
    renumber frames, which once left six prints attached to the wrong pictures. A roll with
    singles is re-analysed inside the operation to learn the new numbers. Where strips lie on
    the glass survives a reorder (renamed) but not a turn. "Discard this load" takes a pending
    load back out, and a look that reads frame for frame like a strip already on the roll
    says so.
  - **Only the tab that started a scan acts on its result** (jobs carry `owner: self()`).
    Every open studio hears the scanner on PubSub, and two tabs each cut the same pass into
    the roll before this.
  - One sticky bar (`#hardware-scan`) holds the roll's name, Roll, Strips, Publish and the
    primary button. The roll's settings (`#roll-config`) and the strips (`#strips`) are
    drawers, one open at a time, **hidden with the `hidden` attribute and kept in the DOM**,
    since their forms are still what the events and the tests address.
    `.adm-page:has(.adm-scan-bench)` lifts the admin's 1120px limit for this page only. **A
    reload opens the roll in progress** (`Pipeline.roll_in_progress/0`: the newest roll folder
    the catalog does not list), not the next free number.
  - Styled only by `adm-scan-*` rules in `assets/css/admin/darkroom.css`.

- **The print editor** (`/admin/darkroom`, "Prints" under Darkroom; `Web.Darkroom`,
  `WebWeb.AdminLive.Darkroom` and `.DarkroomEditor`, 2026-10-17, his ask: "the Lightroom
  clone… so that I may edit single photos"). A developed print is finished by hand with
  LightCraft's sliders, crop and straightening.
  - **The engine is LightCraft** (github.com/storytold/lightcraft, MIT or Apache-2.0, Rust,
    alpha). `lightcraft-cli` is built from a pinned checkout (`cargo build --release -p
    lightcraft-cli`, stripped) and installed in `~/.local/bin` like `film-develop`
    (`:lightcraft_bin`). It was chosen over RapidRAW (AGPL: copying its shaders would make
    this MIT site AGPL) and over writing the adjustments twice (WebGL to look, numpy to print).
    **There is one implementation of every adjustment**: the previews and the print are both
    LightCraft's, given the same commands (`Darkroom.commands/1`).
  - **`Web.Darkroom.Session`** holds one `lightcraft-cli mcp --compact <picture>` open per
    editor over stdio (MCP's JSON-RPC, a line each; edits go through its `run_command` tool).
    The first picture takes about 300 ms, each after about 65 ms; starting the program costs
    a quarter of a second, which is why it is held open. Only the newest preview asked for is
    drawn (the mailbox is drained before each). Pictures go to a 0700 folder under the system
    tmp dir named by a random token, served to the admin session alone by
    `DarkroomController.picture/2`; the folder is env-specific (`:darkroom_scratch`) because
    the suite and a dev server run on the server too and clear theirs at boot. `lightcraft-cli
    run --script` reads all of stdin before it starts, so it is used only for the one-shot print.
  - **An edit is a recipe, never a change to the picture**: `edits/NN.json` (sliders off their
    default, by LightCraft's control id, and `crop: {rect: [x0, y0, x1, y1], angle}`, the rect
    in fractions of the picture, the angle in degrees clockwise). The picture it applies to is
    the print as `film-develop` made it, set aside as `developed/NN.png` on the first save;
    `frames/NN.png` is rendered from it. Revert puts it back. `develop_keeper/2` re-applies the
    recipe to a new development (`reapply/2`), `turn_frame/2` and `carry_singles/3` turn the
    developed picture and **turn the crop's rect with it** (`turn_crop/2`), and `remove_print/2`
    deletes both. `film-develop redevelop` by hand bypasses all of this.
  - **The sliders are LightCraft's own schema** (`develop.controls`: id, section, range, step,
    default and the track's colours), cut to the sections a print from film needs
    (`Darkroom.sections/2`): no optics, calibration, profile, `hdr.*` or the AI denoiser, and
    **no colour sections on a grey print**, since white balance on grey only tints it. Values
    from the browser are checked against the schema (`clean_controls/2`): an unknown id fails
    LightCraft's whole `develop.set`. LightCraft writes colour, so a grey print is put back to
    grey after (`grey?/1`).
  - **The crop is drawn over the whole picture**: while it is open the preview is asked for
    uncropped (`%{recipe | crop: nil}`) and the browser turns it by the angle about its middle,
    as LightCraft does, with the box (`.CropBox`) in the picture's own fractions. A rect that no
    longer fits once straightened is shrunk by LightCraft, not by the page.
  - **An edited print's address carries its print's time** (`Negatives.list_frames/1`,
    `?v=`), so an edit is seen at once instead of when a browser's day-old copy expires;
    unedited prints keep their address. A blog embed builds its own frame address and still
    waits out the day.
  - **Dust** (`spot.findDust`, LightCraft's own PatchMatch healing, grain kept) is the recipe's
    `spots`, in fractions of the whole picture (LightCraft places a spot so whatever the crop),
    healed after the crop and turned with the frame like the crop. It finds dark specks: dust on
    a slide or a B&W print. White specks on colour negatives are `film-develop`'s.
  - **Repair** (`Web.Darkroom.Repair`, 2026-10-18, his choice of LaMa for marks and Stable
    Diffusion for large damage) is a mask (`edits/NN.mask.png`, white where marked, painted in
    the browser by the `.MaskPainter` hook or found by `find_lines/2`) and a picture made from
    it (`developed/NN.repaired.png`), which the sliders then work on (`source_path/2`). The work
    is `priv/repair/film_repair.py` in a Python of its own (`:film_repair_python`, numpy,
    OpenCV, onnxruntime; `test/support/stub_film_repair` in the suite) with LaMa's ONNX port
    (`:lama_model`). **A scanner line is corrected, not painted**: rows the mask covers the
    whole way along get a gain and offset per channel fitted against the rows on both sides,
    and LaMa gets only what that cannot bring back (clipped pixels, a blanked row, a row no
    gain and offset explains, such as a scratch along the film). On the Powell Camera print
    LaMa alone painted out a reflection in a picture frame and dented a camera. Lines are found
    as rows that differ from both sides along 60% of their length, then grown over a line's
    echo (16 to 22 rows on that print) **in the channels the line is in only**: that one is a
    loss of red, and green and blue kept every row under the bar. LaMa works in 512-pixel
    windows at full resolution, at most 1.2 GB. Turn, revert, redevelop and deleting a print
    carry or remove the mask and the repair.
  - **Stable Diffusion fills large damage as a candidate** (`Repair.diffuse/2`,
    `developed/NN.candidate.png`, shown in the editor with Show before, Keep, Discard): it
    invents (over a shelf it stood a canister that was never there), so nothing it makes is
    used until kept. SD 1.5 inpainting in its own Python (`:sd_python`, `:sd_model`). **It runs
    under `systemd-run --user --scope -p MemoryMax=3G -p MemorySwapMax=0 nice -n 19`**
    (`:sd_memory_max`, nil in the suite): its first try loaded whole, needed 5 GB, and the
    kernel's global OOM killer took it on this machine, which is also the server. Under the cap
    the kernel stops it alone. It fits in 2.1 GB by loading its parts one after another with
    `malloc_trim` between, and by working each layer at full precision on a borrowed copy of its
    half-precision weights (`lift/1`); diffusers' own layerwise casting hooks the whole UNet
    when given nothing to skip, and rewrites every layer after use, which crept past 3 GB.
    About two minutes a window; one at a time on the machine (`:global.trans`).
  - **A crop's edges are snapped to whole pixels** (`Darkroom.commands/2` with the picture's
    size): LightCraft resamples a crop whose edge falls between pixels, and a measured slide lost
    two fifths of its fine detail that way.
  - **The film suggests where colour starts** (2026-10-17, his ask: "an equation where some
    attunement is approached over the average color balance of a film given its expected
    reciprocity and exposure condition"). `Web.Darkroom.Prior`'s moduledoc has the equation, in
    `{rg, bg}` = `log10(R/G), log10(B/G)`: the print's near-neutral cast (`Stats`) blended with
    its film's average over the archive (`Archive`, cached in `<archive>/.darkroom/stats.json`,
    grouped by the stock `roll.json`'s `film` names, else by process), moved toward a target,
    plus the datasheet's reciprocity filter for an exposure time typed per frame
    (`roll.json` `"exposures"`, `RollMeta.exposure/2`). **`priv/film/stocks.json` holds only
    figures read from the maker's sheet**, each with its source; Kodak publishes nothing past
    1 s for Portra 400 and Ektar 100 (`"unpublished"`), and third-party tables are not used.
    A CC filter is its density × 100. Temp and Tint move the ratios as **measured** on
    LightCraft (`Film`'s moduledoc; `test/web/darkroom_film_test.exs` measures it again).
    The exposure part of reciprocity is not applied: `film-develop` exposes each single itself.
    In the archive as of 2026-10-17 no roll named its stock, and colour negatives average
    neutral because `film-develop` balances each roll on its base.
  - **His taste** (`Web.Darkroom.Taste`) is learned from saved edits and from choices on
    `/admin/darkroom/taste` (two grades of a random print, one moved a visible step along one
    slider, sides hidden; kept in `<archive>/.darkroom/choices.jsonl`, a choice half an edit).
    Colour: a per-film target shrunk (k = 3) toward one fitted rule `α m + o`. Other sliders:
    `y = μ + W f + a_s + b_k` by weighted ridge (penalties are the shrinkage), predicted only
    once moved in three examples. A recipe stores only sliders off their default, so a missing
    one is read as the schema's default. The Film section's button applies both.
  - Styled by `adm-dr-*` rules in `assets/css/admin/darkroom.css`. The slider tracks take the colours the schema
    gives (temperature, tint, the mixer's eight bands, a gradient's two ends) as literal colour,
    since they are what the slider does. `test/support/stub_lightcraft` answers both modes.

- **Search** (2026-10-07). `Web.Search.search/1` answers one query across every section, grouped
  by section (Blog, Captain's logs, Exercise wiki, Activities, Photographs, Saints, The Bible,
  How it works). **There is no index**: each query reads the same public list functions the
  pages read, so drafts, unpublished logs and `/food` cannot turn up, and a source that is
  missing answers nothing. Every word must appear **at the start of a word** (`pull` finds
  "Pull-Ups", not "controlled"); a name that is the query leads, text matches come last with
  the line they were found on. `/search?q=` (`PageController.search/2`) is a plain GET form,
  `noindex`, out of the sitemap, and rate-limited per address because a query reads files.
  **Every page is in the search, always** (his rule, 2026-10-07): a page with no content of its
  own to list goes in `Web.Search`'s `@fixed` (title, path, what it is, other words for it),
  and `search_test.exs` walks the router and fails on a public address that is not findable.
  Only `/food` and `/england2026` are held back (`Search.unlisted/0`). Frames are found after
  their rolls.
  **The field offers names as it is typed in**: `Search.suggest/1` (eight nearest by name
  across all sections, no body is read) behind `GET /search/suggest` (JSON, its own looser
  rate limit), drawn by a `DOMContentLoaded` block in `app.js` as an ARIA combobox. It is
  enhancement only; the form works without it.
  The way in is a magnifier in the header of every page: `blog_header/1` on the inner pages
  and the homepage's own top bar. In `blog_header/1` it is a square at every width. On the
  homepage it is a square on a wide screen, and **on a phone it is the bar**: a field-shaped
  control leading the row and taking the width the three marks (guestbook, profile, contact)
  leave, since a fourth square among squares read as clutter (2026-10-07). **Icons are an allowlist**
  (`@source inline(...)` in `app.css`): `<.icon>` with a name not on it renders an empty
  square, with no error anywhere, which is how the magnifier first shipped. **The exercise wiki has its own filter** (`/fitness/wiki?q=`, patched as you type)
  over name, group, anatomy and category; it is a narrowing of one page, not `Web.Search`.

- **Speed** (2026-10-07; measured with headless Chrome on a throttled phone profile, and
  pinned by `test/web_web/speed_test.exs`). The server was never the slow part.
  - **Type is served from here**: `assets/css/fonts.css` + `priv/static/fonts/*.woff2` (latin
    and latin-ext of the seven families (the admin's IBM Plex Sans and Fraunces among them, not preloaded: only /admin draws with them), SIL OFL, `LICENSES.md` beside them). No page asks
    Google. The root layout **preloads the two files the header draws with** (Goudy regular,
    Plex Mono 600) with `crossorigin`; `~p` gives the digested address, the same one
    `phx.digest` rewrites into the stylesheet, and they must stay the same or the font is
    fetched twice. A new family needs its files, its `@font-face` rules, and nothing else.
  - **The next page is fetched ahead**: `SEO.speculation_rules_tag/0` has the browser
    *prefetch* a same-site link when the pointer rests on it. **Never prerender**: that runs
    the page, opening LiveView sockets and counting views nobody made. A prefetch carries
    `Sec-Purpose: prefetch` and **`WebWeb.Plugs.Analytics` does not count it**; the browser
    makes no second request when the link is followed, so `app.js` posts `/seen?p=<path>`
    (`WebWeb.SeenController`, outside `:browser` because a beacon has no CSRF token) when a
    prefetched page is actually shown. Both doors count through `Analytics.record/2`.
    Break either half and "witnessed" silently over- or under-counts.
  - `@view-transition { navigation: auto }` (`header.css`): the header keeps its place
    between pages.
  - The homepage hero is asked for at 480/960 with `fetchpriority="high"`, never lazy (it was
    the full preview, 410 KB of a 586 KB page). Negatives images with `?v=` are kept a month.
  - **`Web.Warm`** runs once after the Endpoint starts and reads everything that is parsed on
    first use into `:persistent_term` (lectionary, calendars, saints, the day's Bible books,
    the manual), so the first visitor after a deploy does not wait for it: `/Christ` was
    260 ms cold and 5 ms warm. `Web.Docs.render_file/1` keeps a rendered document until its
    file's mtime changes.
  - The service worker precaches icons only; it used to fetch the undigested stylesheet and
    script that no page uses.

- **The guestbook shows every approved signature**, newest first. It used to stop at sixty
  days, which emptied the page on 2026-10-07. Signatures 2–8 predate the July move off the
  container stack and were restored that day from its old databases
  (`~/.local/share/containers/storage/volumes/sqlite_data/_data/` and
  `~/streetscissors-backups/repo-root-2026-10-04/`); ids 1 and 3 were tests and id 7 is in no
  copy that survives.

- **A signer may leave an email address or phone number** (optional, 2026-10-07), and it is
  the most protected thing on the site. `Web.General.Contact` encrypts it under a key derived
  from `SECRET_KEY_BASE` and `guestbook_entries.contact_sealed` holds only ciphertext, so
  every database copy (nightly snapshots, pre-migration copies, the unencrypted mirror) is
  free of it; `.env` is in no backup. **Rotating `SECRET_KEY_BASE` makes every sealed contact
  unreadable for good.** The column is `load_in_query: false`: only
  `General.guestbook_contact/1` reads it, for `/admin/guestbook`, which opens one contact at
  a time on a click and can forget one without deleting the signature. It never reaches the
  public page, PubSub, the notification letter (which sits in `oban_jobs`) or a log
  (`contact` is in `:filter_parameters`; both schema fields are `redact: true`). Don't add
  it to an export, a search source or an email. `test/web/guestbook_contact_test.exs` pins
  each of these. Known gap: a LiveView crash while the form is being filled in can write the
  last event, field included, to the local journal.

- **Keywords** are the one filtering vocabulary shared by both sections, normalized through
  `Web.Keywords` (`parse/1`, `normalize/1`, `tally/1`, `slugify/1`) so `"New York"` and
  `"new-york"` are one token. A post's keywords live in its frontmatter (`keywords:`, or Obsidian's
  `tags:`; `Blog.set_keywords/2` rewrites the line in place from the admin); a log's live in the
  `audio_logs.keywords` column, normalized in the changeset. Both sections sort by **most recent**
  or by their count, with the sort and `?keyword=` filter in the URL. The two counts differ.
  **Posts are "witnessed"**: people, not loads — distinct `ip_hash` in `analytics_hits` unioned
  across every address the post has lived at. **Logs have "views", counted the way a video site
  counts them** (2026-10-07; they were distinct witnesses, and read 0 everywhere): every
  `audio_plays` row is a view. The `.LogPlayer` hook sends one only after 30 s have actually
  played (half the entry if shorter) and again after the entry has run to its end;
  `Audio.record_play/4` takes at most one per browser per log per 30 minutes (`:throttled`
  otherwise), the browser being `audio_plays.witness`, an anonymous id kept in `localStorage`.
  Never recorded for an admin session. Plays from before 2026-09-22 have no token and count as
  views. `/logs?sort=viewed`; `?sort=witnessed` still answers. Figures print short
  (`Format.format_count/1`: `1.2K`).

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

- **Tending the content** (2026-10-04), both under **Writing** in the admin's rail:
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
  - **The daybook** (`/daybook`) **is an engagement calendar** (his direction, 2026-10-07; it
    was "the almanac", a year page with day pages behind it, and he renamed it the same day
    because an almanac looks ahead and this keeps a record). `/almanac*` 301s there
    (`LegacyRedirectController.almanac/2`); **the code keeps the old name** (`Web.Almanac`,
    `AlmanacController`, `almanac.css`, `.almanac-*`), as the prayer pages kept `Faith*`.
    **`/daybook` is this week** and `/daybook/:year/week/:n` any ISO
    week (`Almanac.week/3`, `week.html.heex`): a plate on one side (a roll or recording from
    that week, else a roll from the archive picked by the week's number, so a week always
    shows the same picture) and seven ruled days on the other. A day row carries what the
    Church keeps when it is more than a weekday (`Web.Liturgy.Calendar`, as a printed
    calendar marks holidays), the work made, and **from today on only**, the regimen's
    `theme:` word for that weekday ("Training: legs"). `/daybook/:year` is now "the year at a
    glance". The current week is always a page; any other empty week is a 404.
  - **The daybook's data** (`Web.Almanac`, `AlmanacController`): `/day/:date`, weeks and
    `/daybook/:year` are built from dates every section already has. Posts use their `date`, logs `recorded_on`, rolls the
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

- **The admin — "the studio"** (redesigned 2026-10-18 from "the composing room"). **The programs are
  the point**: the Darkroom (Scanner, Prints, Taste), the Cutting room (the cutting room and the
  Captain's Logs booth), Writing (Blog, Keywords, Content health), Training (Fitness, Activities)
  and Mail (Inbox, Guestbook, Citations, Newsletter); figures are instruments read in passing
  (`status_strip/1`), never tiles. The rail groups them in that order under a **Studio** link
  (the overview, `/admin/dashboard`) and puts **Settings** at the foot; each group wears its
  program's colour as a small mark, and the waiting counts (open messages, letters included, held
  signatures, held citations, failed transcodes) are small pills. It folds to a Menu bar at ≤900px.
  `WebWeb.AdminNav.sections/0` is the rail's data (groups with `:id`, `:program`, `:heading`,
  `:links`); `program/1` names a path's program (the group of the nearest link) and
  `program_class/1` its class, which the admin layout puts on `.adm-main`.
  - **CSS is one file per area under `assets/css/admin/`**, imported by `app.css` in this order
    (`base.css` first, every rule under `.admin-layout`, `adm-` prefix): `base.css` (tokens, layout,
    the rail, every shared component class: buttons, panels, page head, tabs, rows and tables,
    pills, stats, forms, drop zones, flash under the admin, the login dialog, `st-card`/`st-strip`),
    `overview.css` (the dashboard), `darkroom.css` (scanner `adm-scan-*`, prints and the print
    editor `adm-dr-*`, Taste), `cuts.css` (the cutting room `adm-cut-*` and the logs booth
    `adm-booth`/`theater-*`), `write.css` (blog manager and editor, fitness, keywords, content
    health), `mail.css` (inbox, guestbook, citations, newsletter), `sync.css` (activities) and
    `settings.css`. A class used by two areas is in `base.css`; a few cross-uses remain by name
    (the cutting room uses `adm-dr-section-head`, `-hint`, `-reset`, `-error` from `darkroom.css`,
    the print editor `adm-cut-check` from `cuts.css`). No `<style>` blocks, no inline colour, no
    literal colour in a rule (the slider tracks and the cutting room's title overlay are the
    exceptions: they are what the picture means).
  - **Tokens and themes**: the `--st-*` tokens (`bg surface raised line line-strong ink ink-2 ink-3
    bay`, the program colours `darkroom cuts writing training mail`, `ok warn fail`, `on-accent`,
    `shadow`, the type scale `--st-fs-*`, a 4px `--st-space-*` scale, radii) are defined once on
    `.admin-layout`, dark by default and the light set under `@media (prefers-color-scheme:
    light)`; the admin follows the system and has no switch. Every text pairing is at least
    4.5:1 on bg, surface and raised (measured; keep it so). **The old names are aliases**
    (`--paper` `--paper-raised` `--paper-sunk` `--paper-deep` = bg, surface, raised, bay;
    `--ink`…`--ink-4`, `--rule`, `--rule-strong`, `--adm-act`, `-live`, `-held`, `-fail`, `-info`
    point at the new ones, and `--font-ui`/`-data`/`-heading`/`-body` at the three voices), so a
    rule written against them still wears the palette in both themes; new rules use `--st-*`.
  - **The accent follows the program**: `.adm-main` carries `st-program--<program>` (`darkroom`,
    `cuts`, `writing`, `training`, `mail`; the Studio and Settings carry none, so their accent is
    ink), which sets `--st-accent`. A primary button is filled with it (text `--st-on-accent`),
    and links, the active tab, checkboxes, progress bars, the rail's mark and the 2px focus ring
    (offset 2px, always on keyboard focus) read it. A rail group and a `program_card` carry their
    own program class, so what is inside them wears theirs.
  - **Editing bays stay dark in both themes**: the darkroom bench (`.adm-dr-bench`), the cutting
    room (`.adm-cut-bench`), Taste (`.adm-taste`), the booth's `.theater`, the scanner's
    `.adm-scan-look` and `.adm-scan-sheet`, and anything carrying `st-bay`. The dark token set
    is re-declared on those selectors (the list is at the top of `base.css`, zero specificity,
    and again at its foot for the surround), so everything inside, text and controls too, reads
    dark; `--st-accent-dk` (set beside `--st-accent` by the program class) keeps the accent
    legible on it. A new bay is an element with `st-bay` on it, and a picture or video sits on
    `--st-bay`, never on white.
  - **Type** (served from here, `fonts.css`): **IBM Plex Sans** 400/500/600 and 400 italic is the
    interface (`--st-font-ui`, sentence case, 15px; 14px in dense tables; no letter-spaced
    uppercase labels), **IBM Plex Mono** the figures, timecodes, ids and file names
    (`--st-font-data`, `tabular-nums`), and **Fraunces** (one variable file, weight and optical
    size) the page titles and the words people wrote (`--st-font-display`; a post's title, a
    log's caption, a letter, a signature). Goudy is no longer used in the admin.
  - **`WebWeb.AdminComponents`** is the vocabulary: `rail`, `page_head` (eyebrow `slug`, title,
    one-line lede, actions at the right, under the title on a phone), `panel` (a card; pass
    `class="adm-panel--bare"` for the head without the card), `tabs`, `rows` (a table that stacks
    into labelled blocks on a phone; each `td` carries `data-label`), `pill`, `stat` (quiet:
    a small mono figure over a muted label), `empty` (a sentence and its button), `drop_zone`,
    `copy_field`, and the two that compose the studio floor: **`program_card/1`** (a program's card:
    `program`, `title`, `href`, slots `picture` on the `--st-bay` surround, `state` lines with an
    optional `tone`, `actions`; the title is the one link, stretched over the card by CSS, and
    anything pressable in the slots sits above it) laid out in a `<div class="st-cards">`, and
    **`status_strip/1`** (`items` of `label`, `value`, optional `tone` ok/warn/fail, `href`,
    `spark`: one wrapping line of small muted Plex Mono figures; only a warn or a fail shows its
    tone). theme.css styles bare `button`s, so `base.css` neutralises them under the admin and
    every button class states its hover in full. Buttons: `adm-btn` is the secondary (outlined),
    `--primary` filled with the accent, `--quiet` text only, `--danger`, `--small`; targets are at
    least 40px (44px on phones). Tables stack on a phone; **nothing scrolls sideways at 390px**.
  - **View state is in the URL** here too: `?box=` (inbox), `?show=` (guestbook, keywords),
    `?filter=missing|drafts` (blog), `?tab=` (fitness). `/admin/dashboard` is **the studio**
    (the rail's "Studio"): "Needs you" first (calm lines, each a link to where the thing gets
    done, shown only when something waits; red only for a real failure), then a
    `program_card/1` per program built from **`Web.Studio.floor/1`** (the roll on the scanner's
    bench, singles owed, rolls waiting to publish, the newest edited prints as a contact strip,
    Taste choices; cuts in progress and logs unpublished, transcoding or failed; drafts, the
    last post, posts missing a description or keywords; today's regimen word, the newest
    activity, Komoot's last pass; open messages, held signatures and citations), then the
    passive `status_strip/1`: the machine as **one** item (all well, or how many checks need
    him, in the worst tone, linking to the checks; each check is already a "Needs you" line),
    traffic, and what is on file. `Web.SystemStatus`'s full list ("The machine in full") and
    the most viewed pages sit in closed `<details>` under it. The page reads only stored state
    (`Web.Monitor.last/0`, folder listings, counts); content health is a link, never computed,
    and the year of traffic (`Analytics.get_biweekly_trends/0`, which loads every hit of 56
    weeks: 0.6 s for 50,000) comes by `assign_async` after the page is up. **Prints**
    (`/admin/darkroom`) is a shelf of roll cards with a "Recently edited" row, not the newest
    roll as it was; a roll is `?roll=`. Contact messages live at `/admin/inbox`,
    and site settings at `/admin/settings` (the Spotify playlist, the newsletter's test address).
    The newsletter page holds drafts (`newsletter_drafts.status = "draft"`, which becomes the
    send's record when sent), a sandboxed preview built from `Web.Email.preview_page/2`, a `[Test]`
    send, and the subscriber list. New guestbook signatures are announced on `"guestbook:admin"`
    so the approval queue fills live; the public `"guestbook"` topic still hears only approvals.
    The blog manager keeps its batch `.md` drop and keyword editing, and `/admin/content` 301s to
    `/admin/blog`. The logs booth's `.LogRecorder` hook and its `data-role` markup are
    load-bearing (see above); restyle around them.

- **The manual** (`docs/how-to.md`, `/how-to`, `Web.Docs`) **is live the moment it is saved**:
  the release reads it from the checkout and renders it again when its mtime moves, so write
  it beside and rename it over. Parts 1 to 4 assume nothing; parts 5 to 9 are for someone
  running the site and have to be kept true to the code (the versions, the scheduler's table,
  the environment table, the deploy's steps, the rate limits). Three things about the page it
  is drawn on: **a table's first column never wraps** (`how-to.css`), so it holds a short name
  and never a sentence; **a code word with no space or hyphen cannot break**, and one over
  about 24 characters outside a table or a fenced block pushes a phone's page sideways; and
  its headings are in the search, so a heading with a word beginning `push` breaks the
  suggestion test that expects only Push-ups. The page tests want at least eight parts, a
  table, and a heading with "keywords" in it. It is a public page: no host addresses, no
  names, nothing about the unlisted pages, and nothing about a weakness that is still open.

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
  **Back goes to the last thing the reader was looking at** (`assets/js/trail.js`,
  2026-10-09), not to the page's parent and not to the browser's previous page. The link in
  the markup (`data-back`) is the parent and stays the fallback; the script keeps a trail of
  *things* per tab in `sessionStorage`: a thing is a path without its query, and the
  negatives archive, the regimen's days and the daybook's weeks are each one thing however
  far the reader walks inside (`FAMILIES`: also the days read one after another and the
  Bible's chapters), remembered at the last address seen. A new section that is walked rather
  than visited belongs in that list. **A page that came out of somewhere goes back there
  whatever the trail says** (`UP`): a single photograph to its contact sheet. **A thing is
  remembered with the reader's place on it**: how far down, and which link was pressed, put
  back on return (the link is the surer mark; a folded `<details>` it sat in is reopened,
  and a sideways shelf is scrolled to it). The place is put back several times over four
  seconds, because a LiveView page is redrawn after it loads (the day's checklist threw the
  page to its top when its ticks arrived), and dropped the moment the reader scrolls. A 404
  is never put on the trail. It leans on every piece having one address and every view of
  it living in the query.
  **A tab left open across a deploy reloads itself** (`WebWeb.FreshAssets`, an `on_mount` of the
  public `live_session`, with `phx:stale-assets` in `app.js`): it used to reconnect, take the
  new markup and keep the old digested stylesheet, so new parts of a page showed unstyled.
  **Flash notices** are said once, by the layouts: `Layouts.app` (every `:default` LiveView via
  the router's `live_session` layout, and controller pages via `put_layout`) and
  `admin.html.heex` both render `Layouts.flash_group/1`, pinned under the sticky header and styled
  by hand in `flash.css` — the generator's daisyUI classes never generated, so every flash used to
  print as bare text below the page. Don't add flash markup to page templates. The group sits
  outside `.steel`/`.darkroom`, so it keeps paper tokens there like the header does; inside
  `.admin-layout` it is the studio's own floating card (`admin/base.css`). Only the full-screen dialogs above it (the dispatch overlay, admin
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
  plate mat behind contact sheets (`negatives.css`), and the admin's editing bays (the rest of the admin follows the system's light or dark setting). esbuild bundles
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

**The unit files are kept in `ops/systemd/`**, with `%h` and `%u` for the home directory and
the user so that neither is published. The installed copies are in `~/.config/systemd/user/`,
and a change to one belongs in the other. `start_prod.sh` starts the release by hand with the
same exports (change both together) and refuses to run while the unit is up. **The container
path (`Dockerfile`, `docker-compose.yml`, `deploy.sh`, `Caddyfile.prod`) is stale**: it predates
the data folders, the scanner and the film tools, and must not be run on the host.

Production secrets/config resolve at runtime in `config/runtime.exs` (`:admin_password`, mailer,
etc. come from env there). That file is packed into the release, so an edit to it is a deploy;
only a changed *value* in `.env` or the unit is a restart. **The release listens on
`127.0.0.1:4000` only** (Caddy and the deploy's health checks reach it as `localhost:4000`):
bound wider, a caller on the house network could go round the proxy and write its own
`x-forwarded-for`, which is the address every rate limit counts by. The session cookie is
`Secure` in prod (`:secure_cookies?`, compile-time, `config/prod.exs`). The live database is
outside the checkout (`DATABASE_PATH`, exported by the unit); `web_dev.db` and `web_test.db` in
the repo root are the development and test databases. Migrations auto-run on release boot via
the supervised `Ecto.Migrator`.

**This machine is both the server and the workbench**, so `config/dev.exs` keeps a development
server off the live site's ground: its backups go to `tmp/dev_backups/` rather than the real
backup folder (where a snapshot of `web_dev.db` would become the newest "live" snapshot), and
it sends no webmentions. To poke at code without booting the app at all, use
`mix run --no-start -e …`; against the live release, `_build/prod/rel/web/bin/web rpc '…'`.
