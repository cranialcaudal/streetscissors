# Get Sharp — Self-Auditing Autonomous Claude Code Playbook (v4)

## 0. Claude Self-Audit Protocol & Live-Host Errata Ledger

Because `content/` (the Obsidian vault), `scripts/`, and the live SQLite database (`*.db`) are gitignored in the public repository, this document was authored against the tracked application code and test fixtures. You (Claude) have permission and responsibility to audit and edit this document (`docs/get-sharp-handoff.md`) in place whenever live-host files, line numbers, or database rows differ from what is written here.

### 0A. How to Audit This Document (Run Session 0 Before Session 1)

1. Before starting Session 1, run the single diagnostic command in Session 0 (Section 4) to inspect:
   - Exact exercise wiki folder names and `.md` slugs in `~/streetscissors/content/fitness/exercise-wiki/*/`
   - Current structure and `modules:` frontmatter of `~/streetscissors/content/fitness/weekly/{tuesday,thursday,friday,saturday}.md`
   - Real historical `metrics` JSON shapes inside `exercise_logs` in the live SQLite database
   - Installed R / Quarto binaries and packages (`RSQLite`, `DBI`, `ggplot2`, `jsonlite`)
   - Whether any file line numbers in Section 2A have shifted due to recent commits on `main`
2. Patch this document in place (`Edit` tool):
   - Fill in the Live-Host Errata & State Ledger below (Section 0B).
   - If a live wiki slug differs from a placeholder in Section 3 or Section 4 (for example, `hexbar-rdl` instead of `hexbar-deadlift`, or `farmers-walk` instead of `farmers-carry`), update the slug directly inside this document so every downstream session reads the verified slug.
   - If you discover a contradiction between a task instruction and an existing ExUnit test or `ContentHealth` check, the test/check wins: update this document's instruction and record the reason in Section 0B.
3. End-of-Session Handover Gate (Every Session):
   - Before ending any session (Sessions 0–8), update the Session Progress Tracker in Section 0B with the commit SHA, any shifted line ranges in modified files, and any edge cases discovered, so the next `/clear` session starts with zero re-discovery cost.

### 0B. Live-Host Errata & Session Progress Ledger (Claude Updates This Block)

| Session | Status | Commit / Artifact | Verified Live Slugs / Line Shifts / Notes |
|---|---|---|---|
| Session 0: Self-Audit | [x] Done 2026-10-19 (one open item, below) | docs/get-sharp-handoff.md (audited against `site-revamp` @ `404b31e`) | See "Session 0 findings" below the table. |
| Session 1: Block & Thu Content (A.1–2) | [x] Done 2026-10-19 | content/fitness/blocks/get-sharp.md, content/fitness/modules/lower-durability.md, content/fitness/weekly/thursday.md (gitignored; live on save) | Block file written per §3.1, with 6 `[[links]]` (none broken). The `lower-durability` module gains a `#### Power primer: 3 x 3` block with `[[box-jumps]]` ahead of `#### Hinge`; the hinge range already read 5–8. `thursday.md` gains `block: get-sharp`. Thursday renders the line with its Log button. Edge case: checklist ticks are keyed by index (`vault_gym_<day>_<n>`), so the new first line shifts any Thursday ticks left from before the weekly reset. |
| Session 2: Security + Progression (B.3) | [x] Done 2026-10-19, committed, **not deployed** | `332083a` lib/web/fitness/block.ex, lib/web/fitness/progression.ex | **Security:** `Vault.get_exercise_raw/1` (L418) goes through `exercise_path/2`. `Figure.path/1` (L174) is nil for a non-wiki slug, and the new `Figure.read/1` (L182) is used by `load/1` and `clip.ex` L98/L240. **New code:** `Fitness.recent_exercise_logs/2` (fitness.ex L110). `Block.current/1` (L40) and `Block.parse/2` (public for tests). `Progression.next_target/3` (L63) skips entries dated in a Deload week, which §3.1 originally missed: without that, week 5 would step up from the deload's lighter sets. **Page:** `index.ex` is now 526 lines. It adds `target/2` (L190), `log_line/1` (L206), the `#block-week` label in `.day-page-head` and `#log-target` in the modal, both admin-only. **Frontmatter:** `Vault.parse_frontmatter/1` is public now, and it reads flat `key: value` lines with no `#` comments. **Tests:** the fixture block `test/support/fixtures/fitness/blocks/test-block.md` spans 520 weeks from 2026-01-05 (the page tests read the real clock; it holds until 2036). **`mix precommit`:** 1565 tests, with 2 failures from code this change didn't touch. One is a flaky scanner test that passes on rerun; the other is the private `week.md` hours test, which was already failing. |
| Session 3: Charts, Stress & Bios (B.4–8, D.10) | [x] Done 2026-10-19 | `8b1ff3e` lib/web/fitness/training.ex, lib/web_web/components/fitness_charts.ex | **`Web.Fitness.Training`** is the single source of figures (entries, e1RM by week, weekly volume, `acwr/3`, compliance, history). A planned day is a weekday whose rendered page has a Log button for a block lift (from `Vault.get_day/1`). **Charts** are HEEx SVG (`line_chart/1`, `bar_chart/1`, `block_charts/1`); their CSS is `assets/css/fitness_charts.css`, using `--st-*` tokens with the site's pigments as fallback. **Pages:** `/admin/fitness?tab=progress`, and the admin-only `#wiki-history` panel on `/fitness/wiki/:slug`, where `show.ex` now reads the session. `Block.latest/1` covers the time before and after a block runs. |
| Session 4: Guardrails & Changelog (E.11, F.12) | [x] Done 2026-10-19 | `9ebd35e` migration `20261019232434_create_fitness_checkins` + `Web.Fitness.Checkin`, guardrails.ex, changelog.ex | **Check-ins:** `/admin/fitness?tab=checkin`, one per day (a second one replaces the first). **Guardrails:** pain counts only from a check-in in the last 2 days. `Guardrails.apply_to/3` turns a step up into a hold. **Block file:** gains `substitutes:` (box-jumps → step-ups; calf raises → holds at the top). **Changelog:** `content/fitness/changelog.md` (gitignored), seeded with 2026-10-19 and 2026-10-26 entries; `entries_until/1` hides entries dated in the future. The heading regex needs the `u` flag for the em dash. |
| Session 5: Tue/Fri/Sat Proposals (M, N, O) | [x] Drafted 2026-10-19, **awaiting the author** | content/notes/fitness-proposals/{tuesday-arms,friday-arms,saturday-kb}.md (gitignored) | All 23 links resolve. Nothing in `weekly/` or `modules/` has changed. Proposal N narrows Friday's press pick to the two tracked presses, which double progression needs. Proposal O finds that the 14-move KB circuit runs before both lift days. |
| Session 6: Block Report & Photos (C.9, G.13, H.14) | [x] Done 2026-10-19 | `d6aceeb` lib/web_web/live/admin_live/block_report.ex (not `block_report_live.ex`), lib/web/fitness/photos.ex, lib/web/backup/fitness_photos.ex | **Report:** `/admin/fitness/block`; `Training.report/5` gives the week rows, the lift changes and the verdict (shown from week 8). **Photos:** stored in `fitness-photos/<date>/NN.ext` beside the uploads root (0700/0600) and served by `FitnessPhotoController` at `/admin/fitness/photos/:date/:file`. "Set aside" moves a photo to `.trash`. **Backup:** a nightly copy at 03:23 UTC beside the snapshots, plus the drive mirror via `MirrorWatcher`. The scheduler table in `docs/how-to.md` is updated. The photos are kept out of the content archive on purpose, since each of its 30 versions would carry all of them. |
| Session 7: Homepage Happening (I.15) | [x] Done 2026-10-19 | `4538189` lib/web/happening.ex | **Process:** a supervised GenServer owning an ETS cache (10 min; `:happening_ttl_ms` is 0 in tests). **Rides:** `Rides.latest_clear/0`, with no health data attached. **Witnessed:** counts `/blog/`, `/logs/` and `/negatives/roll/` hits, resolved through `Web.Pieces` and a roll lookup. **Phone layout:** only the Now line shows, because the page is locked to the screen there. `now.md` is read from a `reading:` frontmatter key, or else its first line; there is no such file yet. |
| Session 8: R / Quarto & Stage 0 ML (P, Q.0) | [x] Done 2026-10-19 | `2b2e95f` export.ex, `mix fitness.export`; scripts/fitness_models.R, fitness_report.qmd, fitness_synthetic.R, content/notes/fitness-methods.md (gitignored) | **Installed:** RSQLite 3.53.3 into `~/R/x86_64-redhat-linux-gnu-library/4.5`, and Quarto 1.10.19 at `~/.local/opt/quarto` (symlinked from `~/.local/bin`). **Banister:** with fewer than 15 sessions τ is held at 42/7, because the free fit ran to its bounds. **Weeks:** counted as weeks with data, so a full block counts 8. **Synthetic check:** on the invented block, GESD/IQR finds exactly the planted bad day (2026-12-03). **Achilles retrospective:** runs on real rides once `flare_date` is given. **Render:** `quarto render scripts/fitness_report.qmd --output-dir ../tmp/fitness-report -P db:$HOME/streetscissors-data/streetscissors.db`, run after `mix fitness.export`. Stage 1 and Stage 2 are gated. |

#### Session 0 findings (2026-10-19)

- **Branch.** The working branch is `site-revamp`, not `main`. Line numbers below are from `site-revamp` @ `404b31e`.
- **Wiki folders.** `boxing cardio core forearms legs mobility swim upper`. There is no `glutes` folder; glute and quad work is in `legs/`. Farmer's walk is in `core/`.
- **Day → module map** (from `modules:` frontmatter; the exercises are in `content/fitness/modules/*.md`, and the day files contain no `[[links]]`):
  - Tuesday: `tt-ride-in, kb-mat-circuit, upper-taper`
  - Thursday: `tt-ride-in, kb-mat-circuit, lower-durability`
  - Friday: `friday-lift`
  - Saturday: `adventure-day, half-century-ride` (neither links to any exercise)
  - `lower-durability` links: back-extensions banded-kickbacks bulgarian-split-squat couch-stretch hexbar-rdl hex-flat-side-deadlift hip-thrusts pallof-press pigeon-pose reverse-lunges side-planks single-leg-calf-raises single-leg-rdl step-ups
  - `kb-mat-circuit` links: goblet-squats hollow-hold kb-half-kneeling-press kb-halos kb-lunges kb-pullover kb-russian-twist kb-side-plank-reach kb-single-arm-row kb-swings plank push-ups single-leg-calf-raises y-t-w-raises
  - `upper-taper` links: bfr-arm-finisher captains-chair-knee-raises dumbbell-rows incline-dumbbell-press landmine-press lat-pulldown machine-pec-fly push-up-plus weighted-dips zercher-hold zottman-curls
  - `friday-lift` links: band-external-rotations band-pull-aparts bench-press bicep-curls face-pulls hammer-curls incline-dumbbell-press landmine-press lateral-raises shoulder-press tricep-pushdowns y-t-w-raises
- **Slug verification.**
  - Present: `box-jumps` (legs; it is in the wiki but **not** in any Thursday module today), `single-leg-rdl`, `single-leg-calf-raises`, `side-planks`, `weighted-dips`, `pull-ups`, `lateral-raises`, `face-pulls`, `hammer-curls`, `pallof-press`, `push-ups`, `hollow-hold`.
  - Renamed (patched in Section 4): `hexbar-deadlift` → `hexbar-rdl` (the conventional hex-bar pull is `hex-flat-side-deadlift`; both are in `lower-durability`), `farmers-carry` → `farmers-walk`, `kettlebell-swings` → `kb-swings`.
  - **No wiki page:** `dumbbell-rdl`, `overhead-triceps-extension`, `kettlebell-clean-and-press`. Invariant 2B.3 means these cannot be logged until a wiki `.md` exists (must pass `Web.Fitness.WikiCheck`). Nearest existing pages: `hexbar-rdl`/`single-leg-rdl`, `tricep-pushdowns`, `kb-half-kneeling-press`. Whoever proposes them (Sessions 1/5) either writes the page or substitutes an existing slug; the author decides.
- **Live DB.** Production file is `/home/cesar/streetscissors-data/streetscissors.db` (`DATABASE_PATH` in the systemd unit), not `web_dev.db` (empty). Read it with `sqlite3 "file:…?mode=ro"` only. `exercises` has 107 rows; **`exercise_logs` has 0 rows.** There are no historical `metrics`/`note` formats to accommodate: Session 2's `Progression.parse_log_metrics/1` only has to handle what `FitnessLive.Index.log_metrics/1` writes today, and Session 3's charts and Session 8's models start from empty data.
- **R / Quarto.** R 4.5.3 is at `/usr/bin/R`. Installed: `DBI ggplot2 jsonlite dplyr tidyr`. **Missing: `RSQLite`** (which Section 3.5's `DBI::dbConnect(RSQLite::SQLite(), …)` needs), `brms glmnet bsts outliers`. **Quarto is not installed.** Session 8 needs the author to install `RSQLite` and Quarto first, or it reads the CSV from `mix fitness.export` and renders with plain `Rscript`. GESD has to be written by hand or use `outliers`, which is also missing.
- **Security note for Session 2.** `Figure.load/1` (figure.ex L176) still has no slug guard. It goes through `Figure.path/1` (L170), and `lib/web/fitness/clip.ex` L98/L240 also calls `Figure.path/1`, so the format guard belongs in `path/1`, not `load/1`.
- **Test anchors (2B).** The unknown-slug test is at `fitness_landing_test.exs:250` and matches the substring `"no exercise by that name"`. The flash comes from `index.ex:124`. On the homepage, `bento-fitness-sub-row--three` is at `home.html.heex:153` and `home-about` at L166.
- **Resolved 2026-10-19.** The author asked Claude to finish the playbook. Claude wrote Section 1's seven rules, §3.1, §3.2, §3.4, the §3.5 install note and the Session 1–8 prompts, each marked as Claude's and open to the author's overrule.
- **Decisions the author gave on 2026-10-19:**
  - The block starts Mon 2026-10-26.
  - Progress photos are private and backed up.
  - RSQLite and Quarto may be installed (in Session 8).
  - This run stops after Session 2.

## 1. Token & Session Discipline (Read First — Saves ~75% of Context Spend)

Claude Code re-sends the entire conversation transcript on every turn (input token growth). Three habits blow the Pro $20 5-hour window: (1) spawning Opus subagents to find files, (2) reading 600-line files in full when only 40 lines change, and (3) dumping 300 lines of unfiltered `mix test` output into the transcript on every edit.

Follow these 7 rules in every session:

*Written by Claude on 2026-10-19 at the author's request ("finish the playbook with what you think is best"). The author may overrule any of these.*

1. **Read by range.** Use `grep -n` to find something and `sed -n 'A,Bp'` to read it. Read a file whole only if it is under ~150 lines.
2. **Filter test output.** Use `mix test <files> 2>&1 | tail -30`, `mix test --failed` to rerun failures, and `mix precommit 2>&1 | tail -40`. Never paste a full run into the transcript.
3. **Never boot the app.** This machine is both the server and the workbench. To poke at code, use `mix run --no-start -e …`. For the live release, use `_build/prod/rel/web/bin/web rpc '…'`.
4. **No deploys, and keep the tree deployable.** The author may run `./redeploy.sh` mid-session, and never deploys while he is scanning. Commit a migration together with the code that uses it, never alone.
5. **A test or check beats this document.** If an ExUnit test, `WikiCheck` or `ContentHealth` disagrees with an instruction here, follow the test and record the conflict in 0B.
6. **Visitors see no training data.** That means no logs, weights, targets, guardrail states, check-ins, photos or clock times. Everything here is admin-only unless a deliverable says it is public. The public items are the block's name, week and phase, and the changelog titles.
7. **Close every session the same way:** `mix precommit` green, one commit on the working branch (no push unless asked), and that session's 0B row filled in with the SHA, line shifts and edge cases.

Content under `content/` is live the moment it is saved. Code waits for the next deploy.

## 2. Pre-Extracted Codebase Map & Test Invariants (Zero-Grep Reference)

### 2A. Exact File & Line Map

Re-verified 2026-10-19 against `site-revamp` @ `404b31e`. Lengths and function starts were checked. Where the end of a range wasn't checked, the range shows only a start (`L63…`).

| File | Lines | What Is There & How It Works |
|---|---|---|
| lib/web/fitness.ex | 1–127 | Web.Fitness context. loggable_exercise(slug) (L63–91, with a catch-all `:error` clause at L91) checks Repo.get_by(Exercise, slug: slug); if nil, reads Vault.get_exercise_raw(slug) and inserts an %Exercise{} row. create_exercise_log/1 (L93…), last_exercise_log/1 (L100…), list_exercise_logs/0 (L123…). |
| lib/web/fitness/exercise.ex | 1–28 | exercises schema: name, slug, description, video_url, resources, muscle_group, settings (:map). Slug regex: ~r/^[a-z0-9-]+$/. |
| lib/web/fitness/exercise_log.ex | 1–20 | exercise_logs schema: belongs_to :exercise, field :date, :date, field :metrics, :map, field :note, :string. Because metrics is a JSON :map, new keys ("sets", "reps", "rpe") need zero DB migrations. |
| lib/web/fitness/vault.ex | 1–748 | base_path/0 (L10), list_days/0 (L17…), get_day/1 (L39…), audit/0 (L293…), get_exercise_by_slug/1 (L339…), get_exercise_raw/1 (L418…). The remaining functions have moved from v4's line numbers; grep for `def` before editing. |
| lib/web/fitness/figure.ex | 1–1461 | path(slug) (L170) is Path.join([Vault.base_path(), "figures", slug <> ".json"]); load(slug) (L176) calls it. Also used by lib/web/fitness/clip.ex L98, L240. Needs a slug format guard in path/1. |
| lib/web_web/live/fitness_live/index.ex | 1–474 | Serves /fitness and /fitness/day/:day. handle_event("open_log") (visitor clause L110, admin L114; unknown-slug flash L124), handle_event("save_log") (visitor L134, admin L138), render/1 (L215…; log form at L384). |
| lib/web_web/live/fitness_live/show.ex | 1–272 | Serves /fitness/wiki/:slug. mount/3 (L7, currently ignores session), handle_params/3 (L12…), Figure.load call at L62. |
| lib/web_web/controllers/fitness_controller.ex | 1–121 | GET /fitness/export/csv (export_csv/2). Checks get_session(conn, "admin_user") == true. Exports R-friendly CSV (date,week_num,year,quarter,month,exercise_name,muscle_group,weight_lbs,distance_miles,time_str,height_result,notes). |
| lib/web_web/components/fitness_subnav.ex | 1–49 | Renders Regimen (/fitness), Wiki (/fitness/wiki), Activities (/fitness/rides) tabs. |
| lib/web/fitness/wiki_check.ex | 1–138 | Validates every wiki .md file: requires @keys ~w(title muscle_group anatomy functional_category short_description) (L34), **Goal:**, ### Execution, ### Programming notes, and ### Why it works (if references: set) or ### Why it works (theory) (if no references:), and forbids weekday names (Monday..Sunday) in the body. |
| lib/web/content_health.ex | 1–445 | /admin/content checker. vault_links/0 (L297…) scans every .md file under content/fitness/ for [[slug]] and reports broken links if slug is not in Vault.exercise_slugs(). unused_vault_files/0 (L359…) reports any content/fitness/modules/*.md not listed in a day's modules: or option_N: frontmatter. |
| lib/web/blog/embeds.ex | 1–520 | Server-side SVG chart generator (emissions_svg/2, nice_ticks/1 at L394–, line_series_svg/3 at L431–, bar_row_svg/3 at L462–). Copy this exact zero-JS SVG pattern for fitness charts. |
| lib/web/almanac.ex | 1–365 | entries/0 (L45…) aggregates posts() ++ logs() ++ rolls() ++ rides() sorted newest-first by local Pacific date (Web.Clock). |
| lib/web/analytics.ex | 1–238 | all_hits_by_prefix/1 (L206…) and visitors_by_prefix/1 (L217…) count distinct ip_hash per URL-decoded slug from analytics_hits. |
| lib/web_web/controllers/page_controller.ex | 1–317 | home/2 renders lib/web_web/controllers/page_html/home.html.heex (1–184, styled by assets/css/home.css). |
| lib/web_web/router.ex | 1–298 | Public fitness routes (L142–159; /fitness/:slug catch-all must stay last at L159) and live_session :admin (L169…; /admin/fitness at L186). |

### 2B. ExUnit Test Invariants You Must Not Break

1. DOM order on `/fitness` (`test/web_web/live/fitness_landing_test.exs`, 341 lines; v4's line refs not re-verified):
   - `href="/fitness/wiki"` and `href="/fitness/rides"` must appear before `class="day-strip"`, which must appear before `data-day="<weekday>"`, which must appear before `id="the-week"`.
   - Inside `#weekly-routine`, `class="day-details day-page"` must appear before `"Additional Modules"`, which must appear before `class="fuelling-rail"`, which must wrap `class="day-details" data-day="nutrition-module" open`.
2. Checkbox persistence (`assets/js/gym_routine.js` & `fitness_landing_test.exs`):
   - `GymRoutine` keys `localStorage` ticks as `vault_gym_<data-day>_<checkbox_index>` inside `#weekly-routine`. Never add `<input type="checkbox">` or `.day-details[data-day]` elements for admin progression/guardrail UI.
3. Unknown wiki slugs must be refused (`fitness_landing_test.exs:250`):
   - `open_log` for a slug not in the wiki must flash `"There is no exercise by that name in the wiki."` and make no DB row. Do not weaken `Fitness.loggable_exercise/1` to accept non-wiki slugs; instead, create wiki `.md` files for any new loggable exercise.
4. Visitor privacy on `/fitness` (`fitness_landing_test.exs`):
   - Visitors (`@is_admin == false`) must never see `"Logged today"`, logged weights/reps, progression targets, guardrail states, or clock times (`~r/\d{1,2}:\d{2}/` inside `#the-week` or `.day-page-head`).
5. Homepage structure (`test/web_web/controllers/page_controller_test.exs:4-45`; checked lines 12, 15, 18, 42):
   - `<nav class="home-top-bar">` is checked by `Regex.scan(~r/class="top-bar-link"/, bar) |> length() == 2` (`Guestbook` and `Newsletter and Contact`; search uses `class="top-bar-link top-bar-link--search"`). Do not touch `<nav class="home-top-bar">`. Line 77 also checks that `/Christ`, `/food` and `/england2026` stay out of the bar.
   - `<div class="bento-fitness-sub-row...">` must contain `href="/Christ"` and must not contain `"/how-to"`.
   - `<footer class="home-footer">` must contain `href="/how-to?from=home"`.
   - Place the new "Happening" `<section class="home-happening">` inside `.bento-section` after `<div class="bento-fitness-sub-row bento-fitness-sub-row--three">...</div>` (opens at `home.html.heex:153`) and before `<p :if={@site_description} class="home-about">` (L166).
6. Router & Search invariant (`test/web/search_test.exs`, 259 lines):
   - Every static public `GET` route (without `:` params and not starting with `/admin/`, `/dev`, `/api`, `/health`, `/share`, `/uploads`) must be listed in `Web.Search.pages/0` (`@fixed`). Any new admin route must start with `/admin/` (and sit inside `live_session :admin` for LiveViews).

## 3. Canonical Domain Specification (Deliverables A–Q)

### 3.1 The 8-Week Block & Progression Rules (Deliverables A.1–2, B.3–8)

*Written by Claude, 2026-10-19. The author may overrule it.*

- **The block file** is `content/fitness/blocks/get-sharp.md`. It is the only source of block facts; code holds no dates or lifts. Frontmatter is flat YAML, the shape `Vault.parse_frontmatter/1` reads:
  ```yaml
  title: Get Sharp
  start: 2026-10-26
  weeks: 8
  phases: 1 Baseline; 2-3 Accumulate; 4 Deload; 5-7 Intensify; 8 Test
  lifts: hexbar-rdl 5-8 +5 hinge; bulgarian-split-squat 8-10 +5 squat; incline-dumbbell-press 6-10 +5 push; weighted-dips 6-10 +5 push; dumbbell-rows 8-12 +5 pull; shoulder-press 6-10 +5 push; single-leg-calf-raises 12-15 +5 plyo_locomotion; box-jumps 3-3 +0 plyo_locomotion
  ```
  The parser reads one `key: value` per line and has no inline comments, so a `#` would become part of the value. `start` must be a Monday; week n covers `start + 7(n−1)` to `+6`. Each `lifts` entry is `<slug> <low>-<high> +<increment_lbs> <pattern>`, and every slug must be a wiki page. An increment of `+0` means the lift is tracked but its weight never progresses (box jumps are scored by height). The block runs from 2026-10-26 to 2026-12-20.
- **Phases:**
  - **Baseline** (week 1): find working weights at RPE 7–8. No targets are given.
  - **Accumulate** (weeks 2–3) and **Intensify** (weeks 5–7): double progression.
  - **Deload** (week 4): 2 sets at 90% of the last top-set weight.
  - **Test** (week 8): one top set to RPE 9 for the e1RM, then back-off sets.
- **The body** of the block file holds the experiment framing (C.9):
  - The hypothesis: two strength days alongside ~30 mi/week of riding raises e1RM on the hinge and press with no Achilles flare.
  - The question it answers.
  - The stopping rules, which are the guardrails in §3.2.
- **Logging fields:** `weight`, `distance`, `time`, `result` and `note` stay as they are, so the CSV export doesn't change. Three keys are added: `sets`, `reps` and `rpe`. All are stored as strings in the `metrics` JSON, so no migration is needed. `reps` is the reps of the top set (the hardest set).
- **`Progression.parse_log_metrics/1`** turns a stored entry into numbers:
  - `"200 lbs"`, `"200 lb"` or `"200"` → 200.0. `"90 kg"` → 198.4.
  - `sets` and `reps` come from their own keys, else from `result` (`"3 x 8"` → 3 sets of 8, `"20 reps"` → 20 reps).
  - `rpe` accepts `"8"` or `"8.5"`.
  - Anything unreadable becomes nil. It never raises.
- **The progression rule** (`Progression.next_target/3`, which gets a lift rule, its logs newest first, and the phase):
  - With no usable log, or in Baseline, there is no target.
  - **Deload:** 2 sets × the bottom of the range at `round5(last weight × 0.9)`.
  - **Up:** if the last entry reached the top of the range at RPE ≤ 8 (RPE not recorded counts as 8), add the increment and drop the reps to the bottom of the range.
  - **Hold:** if the last entry fell below the bottom of the range, or the last two were RPE ≥ 9.5, keep the same weight.
  - **Cut:** after three misses below the bottom of the range in a row, use `round5(weight × 0.9)`.
  - **Otherwise:** the same weight, aiming for one more rep than last time, capped at the top of the range.
  - Sets default to 3. Weights are rounded to the nearest 5 lb.
- **e1RM** uses Epley, `w × (1 + r/30)`, and only for 1 ≤ r ≤ 12. Otherwise it is nil.
- **Volume load** is `sets × reps × weight` per entry. (The top set's reps stand in for every set, so the figure is an upper bound.)
- **Compliance** is the share of a day's block lifts logged on that day.
- **ACWR** per pattern is the 7-day volume load divided by the 28-day average weekly load. It is undefined until 28 days of logs exist.

### 3.2 Guardrails, Changelog, Experiment Reports & Visual Check-Ins (Deliverables C.9, E.11, F.12, G.13, H.14)

*Written by Claude, 2026-10-19. The author may overrule it.*

- **Check-ins (E.11).** One row a day in the new `fitness_checkins` table: `date` (unique), `pain` 0–10 (Achilles or the worst joint), `sleep_hours`, `soreness` 0–10, `energy` 0–10 and `note`. The migration ships in the same commit as its schema and form. The form is admin-only on `/admin/fitness?tab=checkin`, and visitors never see a check-in.
- **Guardrail states** (`Web.Fitness.Guardrails.state/2`, worst state wins):
  - **green**: no rule fires.
  - **hold**: today's pain is 3–4, or the lift's pattern ACWR is > 1.5. The target is the last weight, with no increase.
  - **stop**: pain ≥ 5, or pain has risen three check-ins running. `plyo_locomotion` lifts get no target and show their substitutes instead (box jumps → `step-ups`, calf raises → isometric holds noted in the wiki). The other patterns behave as for hold.
  - The state is shown only inside the admin's log modal and the admin's fitness page, and never as a checkbox or a `data-day` element (2B.2).
- **Changelog (F.12).** `content/fitness/changelog.md` is the program's history. It has one `## YYYY-MM-DD — Title` heading per change, with a short paragraph after it. `Web.Fitness.Changelog.entries/0` parses it newest first. The titles are public (Happening's "fitness update"). Entries carry no times.
- **Block report (G.13).** `/admin/fitness/block` is `AdminLive.BlockReport` inside `live_session :admin`. For each week it shows compliance, e1RM change per lift against Baseline, volume load per pattern, the check-in averages and the guardrail days. At week 8 it gives the experiment's answer against the hypothesis.
- **Visual check-ins (H.14).** Progress photos, at most one set per week. They are stored in `fitness-photos/` **beside** the uploads root, never under it (the proxy serves the uploads root), with mode 0700. They are served to the admin session alone by a controller that copies `DarkroomController.picture/2`. A new `Web.Backup.Photos`-style rsync mirror carries them to the drive, and they go in the nightly content backup's file list. They are never in the search, a feed, the almanac or a share card.

### 3.3 Homepage "Happening" Module (Deliverable I.15)

- `Web.Happening` (`lib/web/happening.ex`):
  - Now: Current block + week/phase (`Get Sharp · Week 1 of 8 — Baseline`), newest clear Komoot activity from `Web.Rides` (date, sport, distance — never clock time or coordinates), and current reading from `content/now.md` (omitted when absent).
  - Fresh: Newest published blog post, ready Captain's Log, negatives roll, and fitness update.
  - Witnessed (7d): Top 3 most-viewed public pieces in the last 7 days from `analytics_hits` (distinct `ip_hash`). Never surface `/food`, `/england2026`, `/Christ`, `/admin`, or drafts.

### 3.4 Dual-Purpose Arms & KB Primer/Conditioning Proposals (Deliverables M, N, O)

*Written by Claude, 2026-10-19. These are proposals only. Nothing goes into `weekly/` or `modules/` until the author approves it.*

Each proposal is a file in `content/notes/fitness-proposals/` (private, rendered by no page), and each uses only slugs that already exist:
- **M — Tuesday arms that also serve the press** (`tuesday-arms.md`): swap the end of `upper-taper` for `zottman-curls` + `tricep-pushdowns` as a superset, keeping `bfr-arm-finisher` as the last-week option. Grip and elbow work then carries into the Friday press.
- **N — Friday dual-purpose arms** (`friday-arms.md`): `hammer-curls` and `tricep-pushdowns` after `shoulder-press`, with `face-pulls` kept for shoulder health. The weekly arm total is no larger than today's.
- **O — Saturday KB primer vs conditioning** (`saturday-kb.md`). Two variants, of which the author picks one or neither:
  - (a) **primer**, 15 minutes before the hike: `kb-swings`, `kb-half-kneeling-press`, `goblet-squats`.
  - (b) **conditioning**, 20 minutes on a non-ride Saturday: `kb-swings`, `farmers-walk`, `medicine-ball-slams` as EMOM.
- **Exercises without wiki pages.** The v4 names `kettlebell-clean-and-press`, `overhead-triceps-extension` and `dumbbell-rdl` have no wiki page, and the nearest pages are used instead: `kb-half-kneeling-press`, `tricep-pushdowns` and `hexbar-rdl`/`single-leg-rdl`. A page is written only if the author asks for the exact exercise.
- **On approval:** edit the module, add a changelog entry (§3.2), and run `ContentHealth`, which must show no broken links.

### 3.5 R / Quarto Pipeline & Gated N-of-1 ML (Deliverables P & Q)

> Session 0 (2026-10-19): `RSQLite`, `brms`, `glmnet`, `bsts` and Quarto are **not installed** on the host. `exercise_logs` is empty. See 0B.
>
> The author approved installs (2026-10-19). Session 8 starts with:
> - `Rscript -e 'install.packages("RSQLite", lib = Sys.getenv("R_LIBS_USER"), repos = "https://cloud.r-project.org")'`. Create the `R_LIBS_USER` directory first if it is missing.
> - The Quarto CLI tarball unpacked into `~/.local/opt/quarto`, with `~/.local/bin/quarto` symlinked to it. No sudo.
> - Stage 1/2 packages are **not** installed until their gates open.
>
> Since `exercise_logs` is empty, the Achilles retrospective (item 2 below) is computed from `rides` (Komoot distance and duration per day, as `plyo_locomotion`/endurance load). The author supplies the date of the October 2026 flare-up. Until then the check is skipped and the report says so.

- Data bridge (`Web.Fitness.Export` + `mix fitness.export`): Exports CSV with `exercise_slug,sets,reps,rpe,e1rm_lbs,volume_load_lbs` without needing a browser cookie; R scripts also connect directly via `DBI::dbConnect(RSQLite::SQLite(), db_path, flags = RSQLite::SQLITE_RO)` (requires `install.packages("RSQLite")` first).
- Stage 0 (Build Now in `scripts/fitness_models.R` & `scripts/fitness_report.qmd`):
  1. Banister Impulse-Response (Banister et al., 1975): Fit per lift via `stats::optim(..., method = "L-BFGS-B")`. The residual is the readiness signal.
  2. Movement-Pattern ACWR (Gabbett 2016): 7d / 28d ratio per pattern (`hinge`, `squat`, `push`, `pull`, `plyo_locomotion`) with retrospective validation confirming the October 2026 Achilles spike.
  3. Residual Anomaly Detection: GESD / IQR outlier detection on detrended session residuals.
  4. Question of the Week & Methods Notes: Quarto section testing one concrete N-of-1 hypothesis per week (e.g., 24h endurance-to-strength interference or accessory-to-compound lagged mediation) + publishable methods notes in `content/notes/fitness-methods.md`.
- Stage 1 (Gated until 8 weeks of data) & Stage 2 (Gated until 6 months of data): `brms` Bayesian dose-response, `glmnet` LASSO assistance-lift transfer, `bsts` forecasting, and guardrail readiness model — guarded in code by an explicit sample-size check (`if (n_weeks < 8) stop_or_skip()`).

## 4. Copy-Paste Autonomous Session Prompts (Run One Per Session, `/clear` Between Sessions)

### Session 0 — Claude Pre-Flight Self-Audit (Audits & Patches This Playbook)

<!-- v4 refers to "the single diagnostic command" here, but it was never written. Session 0 on 2026-10-19 ran the equivalent checks by hand. -->

1. Compare the output against Sections 2, 3, and 4 of `docs/get-sharp-handoff.md`:
   - Check the exact wiki slugs for the Thursday lower block (`box-jumps`, `single-leg-rdl`, `dumbbell-rdl` *(no wiki page)*, `single-leg-calf-raises`, `hexbar-rdl`, `side-planks`) and Friday/Saturday proposals (`weighted-dips`, `pull-ups`, `lateral-raises`, `face-pulls`, `hammer-curls`, `overhead-triceps-extension` *(no wiki page)*, `farmers-walk`, `pallof-press`, `kb-swings`, `push-ups`, `kettlebell-clean-and-press` *(no wiki page)*, `hollow-hold`).
   - Check how historical `exercise_logs.metrics` and `note` strings are formatted so Session 2's `Progression.parse_log_metrics/1` regex handles every real historical format in the database.
   - Check which R packages are installed so Session 8 uses only installed packages for Stage 0.
2. Use `Edit` on `docs/get-sharp-handoff.md`:
   - Mark `Session 0: Self-Audit` as `[x] Done` in Section 0B and fill in the verified folders, slugs, historical `metrics` patterns, and R package availability.
   - Update any mismatched exercise slugs or regexes directly in Section 3 and Section 4 of `docs/get-sharp-handoff.md`.
3. Summarize what you updated in `docs/get-sharp-handoff.md` and stop.

*Sessions 1–8 written by Claude, 2026-10-19. Every session ends with Section 1, rule 7.*

### Session 1 — The Block File & Thursday Content (Deliverables A.1–2)

1. Create `content/fitness/blocks/get-sharp.md` exactly as in §3.1: the frontmatter, plus a body with `## Hypothesis`, `## Question` and `## Stopping rules` (pointing to §3.2's guardrails). Every `[[link]]` in it must be a real wiki slug, because `ContentHealth.vault_links/0` scans all of `content/fitness/`.
2. In `content/fitness/modules/lower-durability.md`:
   - Add a `#### Power primer: 3 x 3` block holding `[[box-jumps|Box Jumps]]` before `#### Hinge`.
   - Make the hinge range read `3 x 5–8`, as the block says.
3. In `content/fitness/weekly/thursday.md`, add the frontmatter line `block: get-sharp`. That is the only change to the day file.
4. This is content only, and it goes live as soon as it is saved. Check it with `mix run --no-start` (Vault reads the module and the links resolve). No commit except this doc.

### Session 2 — Security Fix, Structured Log Metrics, `Web.Fitness.Block` & `Web.Fitness.Progression` (Step 0 + Deliverable B.3)

1. **Step 0, security.**
   - `Vault.get_exercise_raw/1` must find its file through the guarded `exercise_path/2`, as `get_exercise_by_slug/1` already does.
   - `Figure.path/1` must refuse any slug outside `~r/^[a-z0-9-]+$/`. Callers are `Figure.load/1` and `clip.ex`.
   - Test both with `"../…"`.
2. **`Web.Fitness.Block`** (`lib/web/fitness/block.ex`):
   - `load/0` parses the block file(s) under `Vault.base_path()/blocks/`.
   - `current/1` takes a date and returns `%{title, slug, week, weeks, phase, start, finish, lifts}`, or nil.
   - `lift/2` returns a lift's rule.
   - Bad or missing input gives nil and never raises.
3. **`Web.Fitness.Progression`** (`lib/web/fitness/progression.ex`): `parse_log_metrics/1`, `e1rm/2`, `volume_load/1` and `next_target/3`, all as in §3.1.
4. **`FitnessLive.Index`:**
   - The log form gains Sets, Reps and RPE fields (text, `inputmode`). There are no checkboxes and no `data-day`.
   - `log_metrics/1` stores them.
   - `log_line/1` reads `185 lbs · 3 x 8 @ RPE 8`.
   - The admin gets a target line in the modal and a block label (week and phase) on the day page.
5. **Tests:**
   - A fixture block under `test/support/fixtures/fitness/blocks/`.
   - `test/web/fitness_block_test.exs` and `test/web/fitness_progression_test.exs`.
   - Admin and visitor cases in `fitness_landing_test.exs`, covering invariants 2B.2–2B.4.

### Session 3 — e1RM Trends, Volume Load, Compliance, Stress/ACWR, History & Wiki Biographies (Deliverables B.4–8 & D.10)

1. **`WebWeb.FitnessCharts`** (`lib/web_web/components/fitness_charts.ex`):
   - Zero-JS inline SVG copying `Web.Blog.Embeds`' `nice_ticks/1`, `line_series_svg/3` and `bar_row_svg/3` (copied, not called: they are private).
   - It draws an e1RM line per lift, weekly volume load per pattern, compliance per week, and ACWR per pattern with a 0.8–1.3 band and a 1.5 rule.
   - Colours come from steel tokens only.
2. Add a `?tab=progress` panel to `/admin/fitness` (`AdminLive.FitnessManager`) to show them.
3. **Wiki biographies (D.10).** `/fitness/wiki/:slug` reads `session["admin_user"]` in `mount/3`. For the admin only, it shows "Your history" on the page: first and last entry, best e1RM, and the last five entries. Visitor HTML must not change, so add a test.
4. Tests cover the chart maths (ticks, empty data) and admin vs visitor on the wiki page.

### Session 4 — Guardrail Check-Ins & Program Changelog (Deliverables E.11 & F.12)

1. Generate the migration with `mix ecto.gen.migration create_fitness_checkins`. It ships with `Web.Fitness.Checkin` and its context functions in **one commit**.
2. **`Web.Fitness.Guardrails`** (`lib/web/fitness/guardrails.ex`):
   - `state/2` takes a lift rule and a date and returns `{:green | :hold | :stop, reasons}`, as in §3.2.
   - `Progression.next_target` takes the guardrail state into account.
3. The check-in form goes in `/admin/fitness?tab=checkin`. In the log modal the guardrail shows as plain text, never as a checkbox.
4. **`Web.Fitness.Changelog`** (`lib/web/fitness/changelog.ex`) parses `content/fitness/changelog.md` per §3.2. Seed the file with `2026-10-26 — Get Sharp begins`.
5. Tests: each guardrail rule, changelog parsing (missing file → `[]`), and the visitor privacy test extended to the new state.

### Session 5 — Regimen Revisions: Dual-Purpose Arms & KB Primer/Conditioning Split (Deliverables M, N, O)

1. Write the three proposals of §3.4 into `content/notes/fitness-proposals/`. Each one has the change as a diff of the module, the reasoning, and what it costs in time.
2. Check every slug in them exists. Do not touch `weekly/` or `modules/`.
3. Stop and ask the author. Apply only the proposals he approves, each with a changelog entry and a clean `ContentHealth` run.

### Session 6 — Experiment Framing, Block Reports & Universal Visual Check-Ins (Deliverables C.9, G.13, H.14)

1. **`AdminLive.BlockReport`** (`lib/web_web/live/admin_live/block_report_live.ex`) at `/admin/fitness/block`, inside `live_session :admin`. It contains the weekly table and charts from §3.2, with the block file's hypothesis and question at the head.
2. **Photos:**
   - Upload on the report page (`allow_upload`, jpg/png/heic, ≤ 15 MB) into `fitness-photos/<YYYY-MM-DD>/` beside the uploads root, mode 0700.
   - Serve them through an admin-only controller action, modelled on `DarkroomController.picture/2`, under `/admin/…`.
   - Add the folder to `Web.Backup`, both nightly and on the drive mirror.
3. Tests:
   - A non-admin gets a 404 for a photo.
   - The path is not under the uploads root.
   - The backup includes the folder.
   - `search_test.exs` stays green (`/admin/` routes are exempt).

### Session 7 — Homepage "Happening" Module (Deliverable I.15)

1. **`Web.Happening`** (`lib/web/happening.ex`):
   - `now/0`: `Block.current/1`, the newest `Rides.clear?/1` ride (date, sport, distance only), and `content/now.md` if present.
   - `fresh/0`: the newest from `Blog.list_posts/0`, the newest ready published log, the newest roll, and the newest `Changelog` entry.
   - `witnessed/1`: the top 3 public pieces over 7 days by distinct `ip_hash`, through `Web.Pieces.from_path/1`. Exclude `/food`, `/england2026`, `/Christ`, `/admin` and anything that doesn't resolve.
   - Each part degrades to nothing on error.
2. `PageController.home/2` assigns it, and `home.html.heex` places `<section class="home-happening">` between the `bento-fitness-sub-row--three` div and `p.home-about`. Style it in `assets/css/home.css` with tokens.
3. Tests:
   - The section's position.
   - The exclusions.
   - No clock time anywhere in it.
   - The existing `page_controller_test.exs` assertions still pass.

### Session 8 — R / Quarto Pipeline & Stage 0 N-of-1 Models (Deliverables P & Q Stage 0)

1. Do the installs from §3.5.
2. **`Web.Fitness.Export`** holds the CSV rows, and `FitnessController.export_csv/2` uses it. Add the new columns `exercise_slug, sets, reps, rpe, e1rm_lbs, volume_load_lbs` at the end so existing R code doesn't break. `mix fitness.export [path]` writes the same file with no cookie.
3. **`scripts/fitness_models.R`:**
   - Banister model by `optim(L-BFGS-B)`.
   - ACWR per pattern, with rides as the endurance load.
   - IQR/GESD residual outliers, the GESD written by hand.
   - Stage 1/2 behind `if (n_weeks < 8)` / `< 26` gates that skip with a message.
4. **`scripts/fitness_report.qmd`** renders with `quarto render`. Its "Question of the week" section runs one hypothesis, and the methods notes go to `content/notes/fitness-methods.md`.
5. Verify on a synthetic CSV (8 weeks, seeded) because the real table is empty. The real report says "not enough data" until the gates open.

---

## Addendum — Jiminy (2026-10-19)

Two gaps found when v4 was saved; patched here rather than in the body so Session 0's self-audit stays clean.

**1. Model assignments per session.** Section 1 covers token discipline but never says which model runs each session. On the Pro ($20) plan, subagents inherit the main model (Opus 5.5) unless set explicitly — an Opus file-read costs ~12x a Haiku one.

| Session | Model | Why |
|---|---|---|
| 0 — Self-Audit | Haiku 5.5 | Read-only inspection; the canonical cheap-subagent case. |
| 1 — Block & Thu content | Haiku 5.5 / by hand | Content files, no code. |
| 2 — Security + Progression | Opus 5.5 plans → Sonnet 5.5 builds | Security-sensitive design deserves Opus; implementation is routine. |
| 3 — Charts, stress, bios | Sonnet 5.5 | Straightforward component + query work. |
| 4 — Guardrails & changelog | Sonnet 5.5 (Opus on standby) | Escalate to Opus only if the guardrail schema design stalls. |
| 5 — Regimen proposals | Sonnet 5.5 (author reviews) | Reasoning-heavy drafting; every proposal needs author approval anyway. |
| 6 — Reports & photos | Sonnet 5.5 | Assembly of B + C outputs. |
| 7 — Happening module | Sonnet 5.5 | Assembly of existing sources. |
| 8 — R/Quarto + Stage 0 ML | Opus 5.5 designs → Sonnet 5.5 implements; author refines | The math matters (Banister fitting, GESD); author is the R expert and owns the stats. |

**2. Section 1's "7 rules" are not enumerated in the text.** The section ends at "Follow these 7 rules in every session:" with no list following. Session 0 should confirm the intended rules with the author before treating any inferred list as canonical — do not hallucinate them.

**4. Running the sessions (2026-10-19).** Sessions 1–2 were run inline by the main session, without subagents, so the model table above is advisory for later runs.

**3. Placement.** Placed at `docs/get-sharp-handoff.md` in `~/streetscissors` on 2026-10-19 by local Claude Code (Session 0). Not yet committed.
