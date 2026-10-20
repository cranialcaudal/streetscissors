# CLAUDE.md

How this app is wired, and the rules that are easy to break. The plain-language manual is
`docs/how-to.md` (live at `/how-to`); what's next is `docs/roadmap.md`.

## Project

**Street Scissors** is a single-author personal website + CMS on Phoenix 1.8 / LiveView 1.1
(Elixir ~> 1.15), backed by **SQLite** (`ecto_sqlite3`). The OTP app is `:web`; the web layer
namespace is `WebWeb`. Contexts and schemas are in `lib/web/<context>/`; controllers, LiveViews,
components and plugs in `lib/web_web/`.

**This machine is both the live server and the workbench.** Never run `mix phx.server` or
`iex -S mix phx.server` to poke at something: use `mix run --no-start -e …`, or against the live
release `_build/prod/rel/web/bin/web rpc '…'`. The working tree is what gets deployed, so keep it
deployable at all times (no half-finished migrations).

Live data, backups and Caddy's log are in `~/streetscissors-data/` (`backups/`, `logs/`, `old/`).
The film tools are in `tools/film/`, linked into `~/.local/bin` by `tools/install.sh`, so **an
edit there is live at once**. Kept
but unused things (spikes, old tool copies, the admin redesign harness) are in
`~/streetscissors-attic/`.

## Commands

```bash
mix setup                       # deps.get + ecto.setup + assets.setup + build
mix test                        # creates/migrates the test db, then the suite
mix test test/web/general_test.exs:42         # one test by line
mix test --failed                             # rerun last failures
mix precommit                   # compile --warnings-as-errors + deps.unlock --unused + format + test
mix ecto.gen.migration name_in_snake_case     # always generate migrations this way
mix assets.build                # tailwind + esbuild (dev)
ops/redeploy.sh                   # the deploy (see Deployment)
```

**Run `mix precommit` before considering any change done.**

## Phoenix conventions

These are what this codebase follows. Where Phoenix's generator defaults disagree, this list
wins.

- **No Tailwind utility classes.** Tailwind v4 runs with `source(none)`, so none generate. All CSS
  is hand-written, read from tokens (see Frontend). No `@apply`, no daisyUI, no `<style>` blocks,
  no inline `<script>`. Only `app.js`/`app.css` are served: vendor code is imported into them.
- **Icons:** `<.icon name="hero-…">` only, and the name must be on the allowlist
  (`@source inline(...)` in `app.css`). An unlisted name renders an empty square with no error.
- **Layouts** are applied by the router's `live_session` layout and `put_layout`, not by wrapping
  templates in `<Layouts.app>`. Flash is rendered only by the layouts (`Layouts.flash_group/1`);
  never add flash markup to a page.
- **Forms:** build them with `to_form/2` in the LiveView and drive the template from `@form[:field]`
  with `<.input>`. Never `<.form let={f}>`, never touch a changeset in a template.
- **Lists that grow:** use streams (`stream/3`, `phx-update="stream"`, the DOM id from the stream).
  Streams aren't enumerable: to filter, refetch and `stream(..., reset: true)`.
- **JS interop:** colocated hooks (`<script :type={Phoenix.LiveView.ColocatedHook} name=".Name">`,
  name starting with a dot) or `phx-hook` with a unique DOM id. An element whose hook owns its DOM
  needs `phx-update="ignore"`.
- **Elixir:** lists don't take index access (`Enum.at/2`, not `list[i]`); bind the result of
  `if`/`case` rather than rebinding inside it; never `String.to_atom/1` on input; predicates end
  in `?` (no `is_` prefix outside guards). For HTTP use `Req` (not HTTPoison or Tesla).
- **HEEx:** `{...}` in attributes and for values in bodies; `<%= ... %>` only for block
  constructs (`if`, `for`, `case`). Use `:if`/`:for` on tags. Class lists are `class={["a", @b && "c"]}`.
  Comments are `<%!-- --%>`.
- **Ecto:** preload associations a template reads. Fields set by the program (ids, owner) are
  never in `cast/3`; set them explicitly.
- **Tests:** `Phoenix.LiveViewTest` with `element/2`, `has_element?/2` and DOM ids. Assert on
  outcomes, not raw HTML. Give key elements ids so tests can address them.

## Architecture: the non-obvious parts

### Private by default

The public GitHub repo is the site's code only. `content/` (apart from `content/templates/`),
photos and the `/pc` reading files are gitignored and live only on the host. **Never
put personal details in code**: they belong in `content/` or `.env`, with a neutral fallback so a
fresh clone still builds and boots. Examples: `content/england2026/trip.json` and `call.md`,
`content/emails/welcome.md`, `content/fitness/meals-week.json`, and `AUTHOR_NAME`,
`MACHINE_NAME`, `NEGATIVES_PATH` in `.env`.

- The vault's root holds only `about.md` and folders. `content/notes/` is private planning: no
  public page renders it (`notes/calendar.md` shows at the admin-only `/admin/fitness/calendar`).
- `/food` and `/england2026` are public but unlisted: out of the sitemap, disallowed in robots.txt,
  `noindex, nofollow`, and held out of search. `/Christ` is unlisted the same way but searchable.
- `config/test.exs` points the vault, trip, emails, blog and negatives paths at invented fixtures
  in `test/support/fixtures/`. Checks against the real content go in the gitignored
  `test/private/`. Anything read at compile time (`Web.Blog.Embeds`' `emissions.R`, `PcLive`'s TXT
  files) must tolerate the file being absent.

### Admin auth

Login (`AdminSessionController`) checks one password via `Plug.Crypto.secure_compare` against
`:admin_password` and sets `session["admin_user"] = true`. The `/admin/*` LiveViews sit in
`live_session :admin` with `on_mount {WebWeb.AdminAuth, :ensure_admin}`, which halts non-admins.
**New admin routes belong in that live_session.** `WebWeb.AdminNav` runs second and feeds the rail;
it skips views the router didn't mount (`socket.router == nil`), because the root layout's sticky
newsletter overlay inherits the session's hooks. The `SetCurrentUser` plug only exposes
`@admin_mode` to templates and **does not protect routes**. Public pages with admin-only actions
(the fitness log buttons) gate each event on the session flag.

### Requests, processes, jobs

- **Every browser request runs** `Analytics` → `SetCurrentUser` → `FetchStats` →
  `LoadSiteSettings` (the `:browser` pipeline). Analytics and the guestbook store client IPs.
  Site settings are key/value rows (`SiteSettings.get_setting/2`) read on every request.
- **No-pipeline scopes:** `GET /health`, `/share/*`, `POST /webmention` and `/seen` set no cookie
  and log no hit.
- **Supervision tree** (`lib/web/application.ex`): Repo; an `Ecto.Migrator` that runs migrations
  **only in releases** (`RELEASE_NAME` set); PubSub; `Finch` (named `Swoosh.Finch`); a
  `Task.Supervisor`; **Oban** on `Oban.Engines.Lite` (stock Oban emits Postgres-only SQL);
  `Web.Scheduler` (Quantum cron); `Web.Media.Transcoder`; `Web.Darkroom.Sessions` (a
  `DynamicSupervisor` of LightCraft processes, one per open print editor).
- **`Web.Warm`** runs once after the Endpoint starts and loads what is parsed on first use into
  `:persistent_term` (lectionary, calendars, saints, the manual), so the first visitor after a
  deploy doesn't wait. `Web.Docs.render_file/1` keeps a rendered doc until its mtime changes.

### Backups

`Web.Backup` (`lib/web/backup/`) keeps four things, each its own way. The manual's Part 7 has the
full account.

- The database: a nightly `VACUUM INTO` snapshot, reopened and integrity-checked, 14 kept.
- The written content (`Backup.Content`: `content/`, the `/pc` files, the recipe seed,
  `test/private/`; **never `.env`**): a `tar.gz`, unpacked and compared hash for hash, and written
  only when the manifest's fingerprint changed, so the 30 kept are 30 versions.
- The negatives (`Backup.Photos`) and log media (`Backup.Uploads`, minus `staging/`): rsync
  mirrors with no `--delete`. Fitness photos: `Backup.FitnessPhotos`.
- `Backup.MirrorWatcher` copies to the external drive when it is plugged in. The database's and
  negatives' mirror folders are **never created** (their presence is the "drive is in" signal).
  Mirror paths come from the systemd unit, not `.env`. `Backup.catch_up/0` runs at boot for missed
  nights. `Backup.Drill` rehearses a restore weekly and stores the result in `restore_drill`.

### The machine watches itself

`Web.Monitor` runs every 15 minutes. `Web.Monitor.Probe` checks the certificate (warns under 21
days), the proxy (`GET /health` on the site's own name), DNS (asked of public resolvers directly,
because `/etc/hosts` maps the domain to loopback here), the disk, and the units in
`MONITOR_UNITS`, plus `SystemStatus.local_checks/0`. Results go in the `monitor_state` setting,
and the overview reads that (`Monitor.last/0`), never probing on mount. Only a `:fail` is mailed
(through `Web.Notify`), and a lookup that couldn't be made is a `:warn`. Probes take their outside
world as options; `test.exs` runs none.

- `.github/workflows/uptime.yml` checks `/health` from outside. **GitHub runs schedules only from
  the default branch (`master`)**, so the check doesn't exist while the file lives only on a work
  branch.
- There is no dynamic DNS (the registrar has no API); a changed address is mailed with the value
  to type in.

### The blog

Markdown in `content/blog/` (`BLOG_PATH`), read at request time and served at `/blog/<slug>`
(`Web.Blog`). The slug is the filename. A title-shaped filename ("Tide's Out") 301s to its
`Keywords.slugify/1` form, and view counts are keyed by the slugified form. Frontmatter is
title/description/date/keywords (`content/templates/blog-template.md`).

- **Embeds** (`Web.Blog.Embeds`, after Earmark): `![[roll012]]` a contact sheet,
  `![[roll012/3|Caption]]` a frame, `![[ride:123]]` a ride card (with Komoot's map when clear).
- **Drafts:** `draft: true`. `Blog.list_posts/0` and `get_post/1` never see drafts, so nothing built
  on them does (index, feeds, sitemap, daybook, `/pc`, letters). Only the admin passes
  `drafts: true` or calls `list_all_posts/0`. The author can open a draft at its address
  (marked, `noindex`).
- **The editor** (`AdminLive.BlogEditor`) edits the whole file. `Blog.write_source/4` **refuses to
  save over a file whose revision (SHA-256) moved**, since Obsidian edits the vault too; saving
  over anyway puts the old text in the vault's `.trash/` first. Saves are written beside and
  renamed over.
- **Images** live under the uploads root at `/uploads/images/` (`Web.Blog.Images`).
- Keywords live in frontmatter, not the database.
- The index's styles are in `writing.css`, scoped to `.writing`. The `blog-bento-*` classes still
  serve the fitness pages.

### Keywords and counts

`Web.Keywords` (`parse/1`, `normalize/1`, `tally/1`, `slugify/1`) is the one vocabulary, so
`"New York"` and `new-york` are one token. Posts keep theirs in frontmatter (`keywords:` or
Obsidian's `tags:`; `Blog.set_keywords/2` rewrites the line), logs in `audio_logs.keywords`.
`/admin/keywords` (`Web.Keywords.Index`) renames a keyword everywhere, drafts included; renaming
onto an existing one merges them.

- **Posts are "witnessed":** distinct `ip_hash` in `analytics_hits`, across every address the post
  has had.
- **Logs have "views":** each `audio_plays` row. The `.LogPlayer` hook sends one after 30 s of real
  play (or half a short entry) and again at the end. `Audio.record_play/4` takes at most one per
  browser (`audio_plays.witness`, an id in `localStorage`) per log per 30 min, and none from an
  admin session.
- **Prefetch must not count:** `SEO.speculation_rules_tag/0` prefetches on hover (**never
  prerender**: that would open sockets and count views). The Analytics plug skips
  `Sec-Purpose: prefetch`, and `app.js` posts `/seen?p=` when a prefetched page is actually shown.
  Break either half and the counts drift.

### Captain's logs

`Web.Audio`, DB-backed video or audio at `/logs/<slug>`. An entry is titled by its date: the slug
*is* `recorded_on` (`2026-09-18`, then `-2` for a second that day via `seq`); `caption` is an
optional line, never the title. The section's look is `logs.css` (`.nx01`; **under it `--ink` is
light**).

- **Delivery is one progressive file.** `Web.Media.Transcoder` (concurrency 1, `nice`-d) runs ffmpeg
  through a `Port` and broadcasts progress on `"log:<id>"`. Video becomes a 720p `video.mp4`
  (`+faststart`, **pinned to `fps=30` and `-level:v 4.0`**: the booth's WebM has no frame rate and
  Safari refused the 1000 fps result). Audio becomes `.m4a` plus a waveform poster.
  `Web.Media.FFmpeg` owns every argument list; binaries resolve through `:ffmpeg_bin` and
  `:ffprobe_bin`, so tests run against stubs in `test/support/`.
- The transcoder doesn't use Oban (retries would re-encode a bad source forever). It requeues
  `pending`/`processing` rows at boot.
- **Sources are deleted after a transcode**, so a trim is final. Re-encode a ready entry from its
  own rendition with `Web.Media.reencode/1` (on prod via `bin/web rpc`).
- Each entry owns `logs/<slug>-<token>/`. A re-transcode writes a new directory and swaps the
  pointer, so the one-year `immutable` header stays honest.
- **Caddy serves `/uploads/*` straight off disk** with Range. `WebWeb.Plugs.MediaServe` does the
  same in dev.
- The player (`LogEntry.plate/1` + `.LogPlayer`) is `phx-update="ignore"`; its class only mirrors
  the media element's own events. `start()` calls `play()` inside the click with nothing awaited
  first, because Safari refuses otherwise. `/logs` mounts no player (a test pins it).
- **The booth** (`/admin/logs`): record, then trim in/out and pick a poster frame. These are
  numbers that ffmpeg applies server-side. The `<.live_file_input>` **must stay inside the form**
  (outside it the chunked upload fails silently), and the recorder's choices are staged into
  their own assign before bytes move. The `.LogRecorder` hook and its `data-role` markup are
  load-bearing.

### The cutting room

`/admin/cuts` (`Web.Cuts`, `AdminLive.Cuts` and `.CuttingRoom`) edits a cut (`log_cuts`): a
timeline and a bin of files (`cut_media`), rendered into a captain's log.

- **The timeline is data** (`Web.Cuts.Timeline`). `clips` play in order on one track (a take with
  `in`/`out`/`gain`, or a print `still` with `frame: "065/6"`, `duration`, `move`); `titles` and
  `sounds` sit at their own `at`. **Everything from the browser goes through `normalize/2`**, which
  drops dangling refs and clamps numbers, so a saved timeline always renders.
- **The render is one ffmpeg command** from `Web.Cuts.Render.args/3` (pure; the graph is in its
  moduledoc). `test/web/cuts_render_test.exs` renders a real cut with real ffmpeg.
- `Cuts.publish/2` stages the render as a booth upload would, so a log never knows it came from a
  cut.
- **The bin is kept** in `cutting-room/<cut id>/` **beside** the uploads root (which the proxy
  serves) and is **in no backup**. Proxies (480 lines, keyframe every 0.5 s) are served to the
  admin by `CutMediaController`; the original never is.
- The `.Cutting` hook plays the program and turns drags into events; the server saves and
  re-renders. The assign is `plan`, not `layout` (LiveView reserves that). Old logs can't be
  brought into a bin: their sources are gone.

### Negatives: the public archive

`/negatives` is one LiveView in three modes: the sheet, the index
(`?mode=index&sort=format&dir=asc`), and a frame (`/negatives/roll/:roll/frame/:n`).

- **The URL is the whole view state and every control is a link.** A roll's address is
  `/negatives/roll/013` (padded; `13` and `roll013` canonicalise to it), and `handle_params/3` is
  the only place state is set. `WebWeb.NegativesLive.Format` builds every destination and **omits
  defaults** so controls don't clobber each other. Arrows stop at the ends. ← → and Escape are one
  `phx-window-keydown` element per key.
- The contents rail folds at **1200px, which is geometry**: rail + gap is 280px, and a landscape
  sheet needs 775px.
- **A frame is a finished print**, `frames/NN.png` from `film-develop develop`, numbered 1..N across
  the roll as `frames.json` numbers them. The index's Frames column counts these
  (`Sheet.frame_count/1`); `catalog.csv`'s `frames` is the *strip* count.
- **Grease-pencil rings** circle printed frames and are the links. `Web.Negatives.SheetLayout`
  re-implements the GIMP assembler (`tools/film/gimp/film-contact-sheet.scm`, installed into
  `~/.config/GIMP/*/scripts/`) to map `frames.json` rectangles onto the sheet. `Web.Negatives.Sheet` shows
  marks only if **both gates** pass: the strip files still match `strips[].file`, and a paper size
  composes to the sheet's real pixels. A failed gate means no rings, never misplaced ones;
  `test/private/negatives_layout_test.exs` names the roll and the `negatives --analyze NNN` that
  fixes it. Rings come from `phash2({slug, frame})`, so they are fixed per frame.
- The rings sit on `.sheet-plate`, which carries the sheet's aspect ratio. It specifies **width
  only** (a height voids `aspect-ratio`) and its mat is a border, not padding.
- **Sized images:** `Web.Negatives` makes `<name>-<width>.webp` at `widths/0` (480, 960) and 2000 on
  first request. **A `?w=` not in the list gets the full preview**, which keeps the disk from
  filling. Build URLs with `Negatives.sized_url/2` and `srcset/1`.
- **Roll metadata** is `roll.json` in the roll's folder (`Web.Negatives.RollMeta`): shot (`2023`,
  `2023-06` or `2023-06-14`, never filled in further), camera, stock, place, notes, exposures.
  Rolls are still **filed by scan date** everywhere; other keys in the file are preserved.
- Theme: `negatives.css`, `.darkroom`. **Under it `--ink` is light**, so dark surfaces key off
  `--paper-*`.

### The scanner studio

`/admin/scanner` (`AdminLive.Scanner`) takes a roll from the glass of the Epson V550 to a sheet
on `/negatives`. The detailed behaviour of `film-develop` that it relies on is in
`docs/negatives-pipeline.md` §9.

- **`Web.Scanner.Bed`** owns the scanner: one `scanimage` `Port` at a time (`{:error, :busy}`
  otherwise), progress on PubSub `"scanner"`, a hard timeout. A scan is written as `.partial` and
  renamed only on exit 0. **Only the tab that started a scan acts on its result** (`owner: self()`).
  The Epson backend sometimes answers `sane_start: Invalid argument` right after a scan; the page
  retries once after 2.5 s.
- **`Web.Scanner.Driver`** is pure argument building. Every scan is `--source "Transparency Unit"
  --film-type "Positive Film"` (the backend's "Negative Film" pre-corrects the mask that
  `film-develop` removes itself). **The V550 scans film only at 400, 800, 1600 and 3200 dpi** and
  silently rounds anything else, so strips are scanned at 400 and resampled to the archive's 300.
  SANE lists webcams first: only a `:scanner` is used (`Driver.pick/1`; `SCANNER_DEVICE` pins one by
  id prefix).
- **`Web.Scanner.Pipeline`** runs the real tools: `film-develop` and `digital-contact-sheet-maker`
  (`:film_develop_bin`, `:contact_sheet_bin`, on the PATH, which is why the unit's PATH has
  `~/.local/bin`). **Nothing stands in for them.** A missing tool is an error the page shows.
  Never bring back a fallback that invents `frames.json`: it put the public rings in the wrong
  place.
- **The flow:** a *look* scans the whole holder at 400 dpi (28 s). `Detect.read/2` finds the film
  type and strips, `add_pass/6` cuts each strip and records where it lies in `holder.json`, and
  the roll is analysed. **Approved singles are scanned at 1600 dpi in bands**: `Driver.bands/2`
  groups neighbouring frames into one crossing, because scan time goes with the length of glass
  crossed. Each frame is then cut out (`cut_from_band/6`) and developed in its own `start_async`,
  three at a time, so the scanner moves on.
- **`selects.json` records what was proposed and chosen before the scanner starts**, so "chosen
  but no print" is exactly what an interrupted run leaves; `Pipeline.owed_singles/1` puts those
  back up on opening the roll. **`redeploy.sh` waits for the scanner to be idle** before it
  restarts (up to 15 min), because a restart kills a run.
- **Strips move with their singles:** reordering, turning or deleting a strip renumbers frames, so
  `Pipeline.carry_singles/3` carries the prints and the roll is re-analysed inside the operation.
  These also delete `frames.json` (and `holder.json` on a turn). A deleted strip goes to the
  archive's `.trash` (`set_aside/2`).
- **What is on the glass is one record for the whole archive** (`<archive>/.on-glass`). A roll's
  `holder.json` counts only while it belongs to the latest look. `Pipeline.relocate/5` finds a
  strip laid back in the holder by comparing pictures (each row less its own mean).
- **Nothing is published until Publish is pressed.** A sleeve holds `scanner_strips_per_roll`
  strips (default 7; blank saves as `off`). When a load runs one strip past the count, the page
  asks which strip begins the next roll (`#roll-end`, `Pipeline.split_roll/2`). Publish with frames
  ticked scans them first. `publish_roll/4` re-checks both sheet gates itself.
- "Add singles to an old roll" (`Pipeline.identify/5`) matches a look against every roll of that
  film width. A reload opens the roll in progress (`Pipeline.roll_in_progress/0`).
- The roll's settings and strips drawers are hidden with the `hidden` attribute but **kept in the
  DOM**, since events and tests address their forms. Styled by `adm-scan-*` in
  `assets/css/admin/darkroom.css`.
- On a published roll, redevelop through `Web.Scanner.Pipeline.develop_keeper/2` (via
  `bin/web rpc`), not `film-develop redevelop` by hand: it also re-applies the print's edit and
  remakes previews. Slides and veiled or blocked rolls get 16-bit singles (`Pipeline.deep?/1`).

### The print editor

`/admin/darkroom` (`Web.Darkroom`, `AdminLive.Darkroom` and `.DarkroomEditor`) finishes a
developed print with sliders, crop, straightening, dust and repair.

- **The engine is LightCraft** (`lightcraft-cli`, built from a pinned checkout into `~/.local/bin`,
  `:lightcraft_bin`). **There is one implementation of every adjustment**: previews and the print
  are both LightCraft, given the same commands (`Darkroom.commands/1`).
- `Web.Darkroom.Session` holds one `lightcraft-cli mcp --compact` open per editor over stdio. Only
  the newest preview asked for is drawn. Previews go to a 0700 tmp folder (`:darkroom_scratch`,
  per env) served to the admin by `DarkroomController.picture/2`.
- **An edit is a recipe, never a change to the picture**: `edits/NN.json` (sliders off their
  default, and `crop: {rect, angle}`). It applies to `developed/NN.png` (the print as
  `film-develop` made it, set aside on first save), and `frames/NN.png` is rendered from it.
  `develop_keeper/2` re-applies it; turns rotate the crop too (`turn_crop/2`).
- Sliders come from LightCraft's own schema, cut to what film needs (`Darkroom.sections/2`; no
  colour sections on a grey print). Browser values are checked with `clean_controls/2`, because
  one unknown id fails the whole `develop.set`. Crop edges are snapped to whole pixels.
- An edited print's URL carries `?v=` (its time), so edits show at once.
- **Repair** (`Web.Darkroom.Repair`): a mask (`edits/NN.mask.png`) and `developed/NN.repaired.png`.
  `priv/repair/film_repair.py` corrects scanner lines by per-channel gain/offset and gives LaMa
  only what that can't fix. **Stable Diffusion makes a candidate only** (`developed/NN.candidate.png`;
  Keep or Discard), and **runs under `systemd-run --user --scope -p MemoryMax=3G -p MemorySwapMax=0`**
  (`:sd_memory_max`), because uncapped it got the server OOM-killed. One at a time (`:global.trans`).
- **Film prior** (`Web.Darkroom.Prior`, equation in the moduledoc): where colour starts, from the
  print's cast, its stock's average and reciprocity. `priv/film/stocks.json` holds **only figures
  from the maker's datasheet**, with sources. **Taste** (`Web.Darkroom.Taste`) learns from saved
  edits and `/admin/darkroom/taste` choices.
- Styled by `adm-dr-*` in `admin/darkroom.css`. `test/support/stub_lightcraft` stands in for the CLI.

### Fitness

`Web.Fitness` and `Web.Fitness.Vault` read the regimen and wiki from `content/fitness/`.

- **`/fitness` is one day to a page**: today by `Web.Clock` (a tzdata-free US-Pacific helper), and
  `/fitness/day/<weekday>` any day. Days link with `navigate`, never `patch` (a patch carries one
  day's ticks onto the next). The strip of days prints each day's `theme:` word.
- **Logging** (admin only): the wiki decides what can be logged. `Fitness.loggable_exercise/1`
  creates the `exercises` row on first log. **A modal's backdrop must not carry `phx-click`**:
  LiveView hands every click inside it to that ancestor.
- **The Week** (`Web.Fitness.Week`, `content/fitness/week.md`): visitors see untimed chips, and only
  the admin sees clock times, so the public page never says when the author is out.
- **Training blocks** (`content/fitness/blocks/*.md`, `Web.Fitness.Block`): the block file is the
  only place a block's dates, phases and lifts are written. Its frontmatter is flat `key: value`
  (`Vault.parse_frontmatter/1`; **a `#` becomes part of the value**). The rules are in the module
  docs: `Progression.next_target/3` (double progression by phase), `Training` (e1RM, volume,
  compliance, ACWR), `Guardrails` (check-ins from `content/fitness/checkins.md` via `Checks`),
  `Prescription` and `Coach` (a day's lines → targets and log form). **The first line naming a
  slug is its plan**, so a primer must never link a block lift.
- The weekly report renders `analysis/fitness_report.qmd` with Quarto (`Web.Fitness.Report`) to
  `fitness-reports/`, and progress photos live in `fitness-photos/`. Both sit **beside** the
  uploads root, are admin only, and are never in search, feeds or share cards.
- `content/fitness/changelog.md` (`Web.Fitness.Changelog`): dated headings, never times. Titles are
  public (the homepage's "fitness update").

### Activities: Komoot and Apple Health

`/fitness/rides` mirrors every recorded Komoot tour (`Web.Rides`, `Web.Rides.KomootSync`). **Komoot
is the only input**: no GPX, planned routes or live tracking. Activities under 0.2 mi are dropped
at the query (`list_rides/0`, `get_ride/1`), but `komoot_index/0` still sees them.

- **Komoot draws the route** (`Rides.embed_url/1`), and cards use its static map, cached by
  `Web.Rides.Thumbs`. **Everything a visitor sees comes from a read made with no login**
  (`Client.public_tour/2`), so Komoot's own privacy zone is applied. The owner's view is never
  fetched, and a thumbnail is named by a hash of the stranger's map URL.
- **`rides.stranger_view`** decides what's shown; **only `"clear"` shows Komoot content**
  (`Rides.clear?/1`):
  - `"exposed"`: the start or end is within 100 m of `RIDE_PRIVACY_ZONES` (**`.env` only, never in
    code or tests**). This is the alarm. `SystemStatus.ride_privacy/0` fails on it.
  - `"passing"`: the ends are trimmed but the route passes back within 100 m. Held back, not a fault.
  - `"hidden"`: Komoot refuses strangers (`403 AccessDeniedPrivacyZone`). **An answer, not a
    failure.**
  - `nil`: not asked yet.
- Private tours are shown through share tokens (`Client.share_token/2`).
- **Heart rate comes from Apple Health** (`Web.Rides.Workout`), paired to the nearest ride start
  within 10 min at read time. It arrives two ways, both via `Rides.store_workouts/1`:
  - Apple's export uploaded on `/admin/rides`: streamed with `unzip -p`, written by
    `HealthExportWriter` into a 0700 inbox **beside** the uploads root (never `/tmp`, never
    `uploads/`), and **deleted whatever happens**.
  - `POST /api/health/ingest`: closed until a token is made. Only its SHA-256 is kept, and a
    workout's `route` is never read.
- **The hourly pass costs nothing when nothing changed.** The token lives in `Web.Komoot.Auth`
  (logging in is what can lock the account), and the listing is a conditional GET on the stored
  ETag (`komoot_etag_tour_recorded`, a plain md5 of the body). The ETag is stored only after a pass
  with zero failures. Tours that leave the listing are deleted, **except when the listing comes
  back empty** (treated as a glitch). `KomootSync.last_run/0` feeds the overview.
- `rides.css` gives back rounded corners under `.steel.activities`. `Web.Rides.Units` speaks
  Komoot's vocabulary and formats Pacific dates.

### The exercise wiki and its figures

`/fitness/wiki`, from `content/fitness/exercise-wiki/<group>/<slug>.md`. Every page has the same
five frontmatter keys and sections (`**Goal:**`, `### Execution`, `### Why it works`,
`### Programming notes`). Three conventions break easily:

- `### Why it works` only on a page with `references:`, otherwise `### Why it works (theory)`.
  Citations come only from `references.md`, each checked against PubMed.
- **A page never names a weekday**, only the session ("the lower day").
- `functional_category` is a fixed vocabulary of thirteen.

`Web.Fitness.WikiCheck.problems/0` finds these and more, and `/admin/health` lists them. Unlinked
pages live in `content/archive/exercise-wiki/`. `Vault.update_exercise/3` carries unknown
frontmatter through. The wiki's own filter (`?q=`) narrows one page and is not `Web.Search`.

**Figures** (`Web.Fitness.Figure`, `Web.Fitness.Clip`, `WebWeb.FitnessFigure`): every page with
`figures/<slug>.json` in the vault leads with a figure.

- A figure file is a few **poses that say where the body is** (pelvis, back lean and curl, where
  each hand and foot is), never joint angles. `build/1` **refuses** a figure that can't reach, goes
  through the floor, pops a joint, or names an unknown key. A refused file shows nothing and is
  listed on `/admin/health`.
- **A film is drawn once and played as video** (~100 KB H.264 loop with a poster). `mix fitness.film`
  feeds `Figure.track/2` joints to `priv/figure/render.mjs`, which drives headless Chrome through
  `render.html`/`figure3d.js` (a ray-marched body of ~100 shapes), then ffmpeg. About 85 s a figure.
- **Films are content, not code**: they live in `figures/` under the uploads root, with
  `clips.json`. For the live site run with `UPLOADS_PATH=$HOME/streetscissors-data/uploads`; no
  deploy is needed. **A film shows only for the figure it was made from** (`Clip.find/2` hashes the
  figure file and the lit muscles). Edit a figure or a page's `anatomy:` and that page falls back to
  the flat SVG drawing until filmed again (`Clip.unfilmed/0`).
- **A figure key the running release doesn't know shows nothing live**, so a new key waits for a
  deploy.
- The film's ground is steel's `--paper-sunk` written as a number in `render.html`. Change one,
  change the other.
- `figure3d.js` and `priv/figure/measure.mjs` share `FIELD` (the distance field). **Keep them in
  step.** `mix fitness.film --measure` compares 31 body measurements to ANSUR II lean men, and
  `test/web/fitness_measure_test.exs` holds the proportions.
- **Frames are drawn in bands** (`BANDS`), because the i915 driver resets any GPU job over 640 ms
  and the WebGL context is lost (black frames). If black frames return, read
  `journalctl -k | grep "preemption time out"` first.
- `Clip.muscles/1` maps the wiki's free-text anatomy onto the camera's seventeen muscles.
- The video plays by `autoplay` (no wait for the socket). Reduced motion is honoured in the markup:
  the `<source>` carries `media="(prefers-reduced-motion: no-preference)"`.

The commands, one at a time (**never two renders at once**):

```bash
mix fitness.film --check <slug>                                          # rules, no drawing
timeout -k 5 150 mix fitness.film --stills /tmp/figure-stills <slug> < /dev/null   # a PNG per pose
UPLOADS_PATH=$HOME/streetscissors-data/uploads timeout -k 5 300 mix fitness.film --all <slug> < /dev/null  # film it live
mix fitness.film --tiers <slug>                                          # which muscles light
```

**A file that validates is not thereby right: look at every pose.** Start a new figure from the
pose of a finished figure in the same position.

### Prayer pages (`/Christ`)

`WebWeb.FaithController` (the code keeps the old name `Faith*`; `/faith/*` and `/christ/*` 301
here). **Nothing is fetched from another site**, and the page is the same for every reader.

- **`Web.Bible`** reads one translation from `priv/bible/<name>/`. The committed one is the CPDV
  (public domain). **A licensed text (RSV-CE) must never be committed**: lay it out outside the
  checkout and set `BIBLE_PATH`. `Web.Bible.Versification` maps lectionary numbering onto Vulgate
  numbering.
- **`Web.Liturgy.Calendar.day/2`** computes the day: seasons with US movable days, over layered
  calendars in `priv/liturgy/` (General Roman, then `usa-en.txt`, then `ocd-en.txt`); a later
  layer replaces an entry by id. `Web.Liturgy.Lectionary` is citations only. `Web.Liturgy.Hours`
  lays out Lauds, Vespers and Compline from the psalter; the approved English office is under
  copyright, so there are no antiphons or collects, and prayers are public-domain wordings.
- **`/Christ` is the day and only the day**: no explanatory essays. Each prayer sits behind its own
  `<details>`. Inside an hour, what people know by heart is just a name (`FaithHTML.known/1`). The
  Rosary is the order and the mysteries; the prayer texts are listed once at the foot. Don't write
  them back out. `app.js` only enhances. Nothing is stored.
- `Web.Liturgy.Saints` (`priv/liturgy/saints.json`): Wikipedia summaries (CC BY-SA) matched by
  hand. **Don't regenerate from search results without checking each.** Pictures in
  `priv/static/images/saints/` are gitignored.
- Theme: `faith.css`, `.faith` (brown scapular). **Under it `--ink` is light.** `--accent-ink` is at
  the edge of 4.5:1 on `--paper-raised`, so check contrast before changing it.
- `priv/faith/guide.md` is kept on disk but rendered nowhere.

### Search

`Web.Search.search/1` answers across every section. **There is no index**: each query reads the
same public list functions the pages read, so drafts and unlisted pages can't leak. Words match
**at the start of a word**. `/search?q=` is a plain GET form, `noindex`, rate-limited.

- **Every public page is in the search, always.** A page without listable content goes in
  `Web.Search`'s `@fixed`, and `search_test.exs` walks the router and fails on an unfindable public
  address. Only `/food` and `/england2026` are held back (`Search.unlisted/0`).
- `Search.suggest/1` (names only) behind `GET /search/suggest`, drawn in `app.js` as an ARIA
  combobox. Enhancement only.

### The social side

- **`Web.Pieces`** is the one vocabulary for "a piece": `"post:<slug>"`, `"log:<slug>"`,
  `"frame:<roll>/<n>"`. `resolve/1` checks that the piece exists and is public. Letters, webmentions
  and the admin all go through it.
- **The daybook** (`/daybook`; code keeps `Web.Almanac`, `AlmanacController`, `almanac.css`) is a
  week page: a plate and seven ruled days with the liturgical day, the work made, and from today on
  the regimen's `theme:` word. `/day/:date` and `/daybook/:year` are built from dates every section
  has. **Never times.** An empty day or year is a 404, and prev/next skip empty days, so crawlers
  can't walk forever.
- **Letters** (`Web.Letters`, `LettersLive`, nested via `live_render` under posts, logs and frames).
  Publishing needs both `may_publish` (the writer's consent) and `published_at` (the author's
  choice). **A nested LiveView can't read connect_info**, so the host passes `"remote_ip"` in the
  session. The frame view keys its id per frame so it remounts.
- **Feeds:** `/feed` is everything (logs with `<enclosure>`), newest 30, excerpts only.
  `/feed?keyword=` follows a keyword; an unknown one is a 404.
- **IndieWeb:** `h-entry`/`h-card` via `WebWeb.Microformats`; the name comes from `AUTHOR_NAME`.
  `rel="me"` is opt-in via `REL_ME_URLS`.
- **Webmentions in** (`POST /webmention`, no pipeline, rate-limited): stored `pending`, verified by
  `WebmentionVerifier` through an **SSRF guard** (non-public addresses refused, every redirect hop
  re-checked, 10 s, 1 MB). Verified becomes `held` until approved at `/admin/citations`. A
  rejection sticks. The suite never touches the network (`WebmentionsTestResolver`, `Req.Test`).
- **Webmentions out** (`Web.Webmentions.Outgoing`): hourly, each external `<a href>` in published
  posts is queued once. A removed link sends a final `withdrawn`. `:webmention_send` false turns it
  off (as in dev).

### The guestbook

All approved signatures show, newest first. **An optional email or phone is the most protected
data on the site**: `Web.General.Contact` encrypts it under a key derived from `SECRET_KEY_BASE`
into `contact_sealed` (`load_in_query: false`, `redact: true`, in `:filter_parameters`). Only
`General.guestbook_contact/1` reads it, one at a time on `/admin/guestbook`. **Rotating
`SECRET_KEY_BASE` makes every contact unreadable for good.** Never add it to an export, search,
email, PubSub or a log. `test/web/guestbook_contact_test.exs` pins each rule.

### Admin tools

- **`Web.ContentHealth`** (`/admin/health`): broken links and images, unresolved embeds, posts
  missing a description or keywords, unused images and modules, rolls whose rings are withheld,
  wiki problems, unfilmed figures. **Links are checked by dispatching through `WebWeb.Endpoint`**
  (`ContentHealth.ask/1`), so there's no second list of routes to drift. Built with `start_async`.
- **The 404** (`WebWeb.NotFound.render/1`) is a whole document with layouts off. Use it for any "not
  here". `Web.Nearby.suggest/1` offers up to three real things, and **an address outside the site's
  sections costs no file read or query** (most 404s are scanners).
- **Share cards** (`Web.ShareCard`, `/share/*`, no pipeline): 1200x630 cards drawn by ImageMagick
  on first fetch, named by a fingerprint carried as `?v=`. Titles reach ImageMagick through
  `caption:@file`, never as an argument. A page only names its card and never shells out.

### The admin: the studio

The programs are the point: Darkroom (Scanner, Prints, Taste), Cutting room (cuts, the logs
booth), Writing (Blog, Keywords, Content health), Training (Fitness, Activities), Mail (Inbox,
Guestbook, Citations, Newsletter). `WebWeb.AdminNav.sections/0` is the rail's data, and
`program/1` names a path's program. `/admin/dashboard` builds from `Web.Studio.floor/1` and **reads
only stored state** (content health is a link, never computed; traffic arrives by
`assign_async`).

- **CSS is one file per area** under `assets/css/admin/` (`base.css` first; every rule under
  `.admin-layout` with the `adm-` prefix). A class two areas use goes in `base.css`. No literal
  colour, except slider tracks and title overlays, which *are* the picture.
- **Tokens are `--st-*`**, defined once on `.admin-layout`: dark by default, light under
  `prefers-color-scheme: light`. Every text pairing is ≥4.5:1, so keep it so. The old names
  (`--paper*`, `--ink*`, `--rule*`, `--adm-*`) are aliases; new rules use `--st-*`.
- **The accent follows the program** (`st-program--<program>` on `.adm-main` sets `--st-accent`).
- **Editing bays stay dark in both themes** (`.adm-dr-bench`, `.adm-cut-bench`, `.adm-taste`,
  `.theater`, `.adm-scan-look`, `st-bay`). A new bay just needs `st-bay`, and
  pictures sit on `--st-bay`, never white.
- **Type:** IBM Plex Sans for the interface, Plex Mono for figures and ids (`tabular-nums`),
  Fraunces for titles and people's words. No letter-spaced uppercase labels.
- **`WebWeb.AdminComponents`** is the vocabulary (`page_head`, `panel`, `tabs`, `rows`, `pill`,
  `stat`, `empty`, `drop_zone`, `program_card/1`, `status_strip/1`). Buttons are `adm-btn` with
  `--primary`, `--quiet`, `--danger` or `--small`. Targets are ≥40px (44 on phones), and **nothing
  scrolls sideways at 390px**.
- View state is in the URL (`?box=`, `?show=`, `?filter=`, `?tab=`, `?roll=`).
- New guestbook signatures go out on `"guestbook:admin"`; the public `"guestbook"` topic hears only
  approvals.

### The manual (`docs/how-to.md`)

**Live the moment it's saved** (the release re-renders it when the mtime moves), so write it
beside and rename it over. Parts 1–4 assume nothing. Parts 5 onward must be kept true to the code
(versions, scheduler table, env table, deploy steps, rate limits). Constraints of its page:

- **A table's first column never wraps**: a short name, never a sentence.
- A code word with no space or hyphen over ~24 characters outside a table or fence pushes a phone
  sideways.
- Its headings are in the search: a heading word beginning `push` breaks the suggestion test that
  expects only Push-ups.
- Tests want ≥8 parts, a table, and a heading containing "keywords".
- **It is public**: no host addresses, no names, nothing about unlisted pages or open weaknesses.

### Frontend

- **Design:** "UC Press / Valley print". Paper tokens (`--paper`, `--paper-raised`, `--paper-sunk`,
  `--paper-deep`), ink (`--ink` … `--ink-4`), `--rule`/`--rule-strong`, pigments (`--color-orange`,
  `--color-jade`, `--color-dodger`). **Pages read tokens, never literal hex**; all are in one `:root`
  in `app.css`. Sorts Mill Goudy for headings and body, IBM Plex Mono for UI (`--font-ui`) and data
  (`--font-data`).
- **Ink reads, poppy acts:** anything pressable wears `--accent-ink` (`#a73b19`) at rest, not only on
  hover. Targets ≥44px.
- **Section themes** re-ink the same tokens: `.darkroom` (`/negatives`), `.steel` (every `/fitness*`
  page; League Spartan; hot metal for figures and interaction only, headings stay `--ink`), `.nx01`
  (logs), `.faith`. **Under `.darkroom`, `.nx01` and `.faith`, `--ink` is light.** The `/pc` terminal
  is a deliberate dark exception.
- **Fonts are served from here** (`assets/css/fonts.css`, `priv/static/fonts/*.woff2`, OFL). The root
  layout preloads Goudy regular and Plex Mono 600 via `~p`, and that address must match what
  `phx.digest` writes into the stylesheet, or the font loads twice.
- **The wordmark** (`CoreComponents.wordmark/1`): one span per letter with fixed offsets, and
  `aria-label="streetscissors"` on the wrapper (tests assert it). `baker_wordmark/1`'s geometry is
  **measured from the rendered font** with canvas `actualBoundingBox*`, never `getBBox()`.
- **The header** (`blog_header/1`, styled only in `header.css`). **Back goes to the last thing
  read** (`assets/js/trail.js`): a trail of things per tab in `sessionStorage`, with `FAMILIES`
  (sections walked as one thing) and `UP` (a frame goes back to its sheet). A new walked section
  belongs in `FAMILIES`.
- **A tab left open across a deploy reloads itself** (`WebWeb.FreshAssets` + `phx:stale-assets`).
- `@view-transition { navigation: auto }` in `header.css`. The homepage hero is 480/960 with
  `fetchpriority="high"`, never lazy.
- Print rules: the post page's are at the end of `writing.css`, the year's in `almanac.css`.

## Deployment

The live site is a `MIX_ENV=prod` release under the systemd user unit `streetscissors.service`,
behind Caddy (`caddy-streetscissors.service`, `ops/caddy/Caddyfile`). The manual's Part 6 walks through it.

- **`ops/redeploy.sh` is the deploy**: assets, release, restart, health gate. It keeps the serving
  release as `_build/prod/rel/web.previous` (only while the site answers), and **`ops/rollback.sh`
  swaps the two**. Run twice, it swaps back. It doesn't touch the checkout or undo a migration.
- **Don't deploy while a scan is running** or the owner is mid-session. Deploy only at a pause they
  name. Content and the manual need no deploy.
- Unit files are kept in `ops/systemd/` (`%h`, `%u` instead of real paths). The installed copies
  are in `~/.config/systemd/user/`: change both together. `ops/start_prod.sh` starts the release by
  hand with the same exports and refuses while the unit is up.
- **Never run `site up` or `sudo caddy start`**: Caddy runs under its user unit.
- `config/runtime.exs` is packed into the release, so editing it means a deploy. A changed value in
  `.env` or the unit only needs a restart.
- **The release listens on `127.0.0.1:4000` only.** Bound wider, a caller on the LAN could bypass
  the proxy and forge `x-forwarded-for`, which every rate limit counts by. The session cookie is
  `Secure` in prod (`:secure_cookies?`, compile-time).
- The live database is outside the checkout (`DATABASE_PATH`, exported by the unit). Read it only
  read-only (`sqlite3 "file:…?mode=ro"`). `tmp/db/web_dev.db` and `tmp/db/web_test.db` are dev
  and test. Migrations run at release boot.
- `config/dev.exs` keeps a dev server off the live site's ground: backups go to `tmp/dev_backups/`
  and it sends no webmentions.
