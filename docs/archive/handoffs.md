# Archived handoffs

These are briefs written for other agents between 2026-10-10 and 2026-10-19: a general
handoff for an agent new to the repo, the exercise-figure procedure, the Get Sharp
playbook, and the scanner GUI blueprint. They are kept for the record. **They are not
instructions.** Line numbers, file paths, and task lists in them date from when they were
written. The rules that still hold have moved to `CLAUDE.md` and `docs/how-to.md`.

- [Working on this site (2026-10-11)](#working-on-this-site-instructions-for-another-agent)
- [Exercise figures (2026-10-10)](#exercise-figures-handoff-to-another-agent)
- [Get Sharp playbook (2026-10-19)](#get-sharp--self-auditing-autonomous-claude-code-playbook-v4)
- [Scanner GUI blueprint (2026-10-02)](#custom-flatbed-scanner-gui-architectural-blueprint--specification)


---

## Working on this site: instructions for another agent

Written 2026-10-11 for an agent that has never seen this repository (Gemini Flash in Google
Antigravity). Read all of it before you run anything. It is short on purpose. When this
document and your own judgement disagree, follow this document and say so in your report.

The exercise figures have their own guide: [`figures-handoff.md`](figures-handoff.md). Do
not start it unless the owner asks for figure work. It is the one job done in the owner's
folder and not in your copy, because the pose files are not in git.

### 1. What this is

A personal website: writing, spoken logs, film photographs, a training plan, a prayer page.
Phoenix 1.8 and LiveView 1.1 (Elixir), SQLite, hand-written CSS. One author, one machine.

**The machine you are on is the live web server.** The folder `~/streetscissors` is what gets
deployed, by the owner, whenever he likes. Anything half-finished in that folder can go live.
That is why rule 1 exists.

### 2. Rules. Breaking one of these is worse than not finishing

1. **Work only in your own copy.** Never edit a file under `~/streetscissors`. Make the copy
   once (section 3) and do everything there.
2. **Never deploy, start, stop or restart anything.** Do not run `./redeploy.sh`,
   `./rollback.sh`, `./start_prod.sh`, `systemctl`, `site`, `caddy`, `mix phx.server` or
   `iex -S mix phx.server`. You check your work with tests, not by running the site.
3. **Never push, fetch or pull.** No `git push`, no `gh`. Commit in your copy only. The owner
   merges.
4. **Never delete or rename a file you did not create**, and never run `rm -r`, `git reset
   --hard`, `git clean` or `git checkout .`.
5. **Never touch**: `.env`, anything under `content/`, `priv/static/images/`, `priv/bible/`,
   `priv/liturgy/`, `priv/repo/migrations/`, `ops/`, `Caddyfile`, `config/runtime.exs`,
   `config/prod.exs`, the scanner (`lib/web/scanner/`, `lib/web_web/live/admin_live/scanner.ex`).
6. **No new dependencies, no database migrations, no new JavaScript libraries.**
7. **No personal details in code or tests**: no names, addresses, places, times of day.
8. **CSS is hand-written.** There are no utility classes (no Tailwind classes, no daisyUI).
   Use the tokens (`var(--ink)`, `var(--paper)`, `var(--rule)`, `var(--accent-ink)`), never a
   colour written as hex. Put rules in the stylesheet the page already uses.
9. **An icon must be on the allowlist** in `assets/css/app.css` (`@source inline(...)`), or
   `<.icon>` draws an empty square with no error.
10. **One task at a time, one commit per task.** Do not start a task until the one before it
    passes section 5.
11. **If a command fails twice, or a task needs something these rules forbid, stop.** Write
    down what happened and go to the next task. Do not improvise.
12. **Never report a task as done because the tests pass.** Say what you changed, and what
    you could not check.

### 3. Setting up your copy (once)

```bash
cd ~/streetscissors
git worktree add ../streetscissors-gemini -b gemini/ux site-revamp
cd ../streetscissors-gemini
ln -s ../streetscissors/deps deps
mix compile 2>&1 | tail -3
mix test 2>&1 | tail -3
```

The last line must say `0 failures`. (In the owner's folder one private test fails; your copy
does not have the private tests, so yours must be clean.) If it is not `0 failures` before you
have changed anything, stop and report.

From now on every command is run in `~/streetscissors-gemini`.

### 4. Finding your way

| You want | Look in |
|---|---|
| Every address the site answers | `lib/web_web/router.ex` |
| A page drawn by a controller | `lib/web_web/controllers/<name>_html/*.heex` |
| A live page | `lib/web_web/live/<section>_live/*.ex` (markup is inside `render/1`) |
| Shared pieces: header, icons, flash | `lib/web_web/components/core_components.ex` |
| The page frame, `<title>`, fonts | `lib/web_web/components/layouts/root.html.heex` |
| The fitness tabs | `lib/web_web/components/fitness_subnav.ex` |
| The 404 page | `lib/web_web/controllers/error_html/not_found.html.heex` |
| Stylesheets | `assets/css/*.css` (`header.css`, `writing.css`, `negatives.css`, `steel.css`, …) |
| The site's own JavaScript | `assets/js/app.js`, `assets/js/trail.js` |
| Data and rules (no HTML) | `lib/web/<area>/` |
| Tests | `test/web/` (rules), `test/web_web/` (pages) |
| How everything is wired, in full | `CLAUDE.md`. Long. Search it, do not read it whole |
| Coding conventions for Phoenix | `AGENTS.md` |

The table in section 4a says where each section lives. To find the code behind something
you see on a page, search for its words.

```bash
grep -rn "Written Work" lib/ assets/ | head
```

How to see what a page sends without running the site: read its test. Page tests fetch the
page and assert on its HTML (`get(conn, ~p"/blog")`, `live(conn, ~p"/fitness")`), and you can
add an assertion of your own the same way.

**Words that mean something here.** Do not rename these in code; you may only change what a
visitor reads when a task says so.

| Word | Meaning |
|---|---|
| Dispatch | the newsletter |
| Witnessed | how many different people read a post |
| Daybook | the calendar of what was made each day. In code it is `Almanac` |
| Captain's logs | recorded video or audio entries. In code `Web.Audio`, `LogsLive` |
| Regimen / Wiki / Activities | the three fitness pages: the week's plan, the exercise pages, the rides |
| Roll, sheet, frame | a roll of film, its contact sheet, one photograph |
| `/Christ` | the prayer pages. In code `Faith*`. The capital C is the real address |

### 4a. The whole site, section by section

Every public section, where its code is, where its content comes from, and the trap that
catches newcomers. "Content" means files or rows the owner writes; you never edit those, only
the code that reads them. The test suite uses invented content in `test/support/fixtures/`,
so a test never sees the owner's real pages.

| Section (address) | Code that draws it | Rules and data | Stylesheet, theme class | The trap |
|---|---|---|---|---|
| Home (`/`) | `controllers/page_html/home.html.heex` | `PageController.home` | `home.css` | Two tests look for the wordmark's `aria-label`. The layout is the owner's: do not rearrange it |
| Blog (`/blog`, `/blog/:slug`) | `controllers/blog_html/` | `Web.Blog`: markdown files with frontmatter, read at each request | `writing.css`, `.writing` | A draft (`draft: true`) must never appear anywhere. Use `Blog.list_posts/0`, which leaves drafts out |
| Captain's logs (`/logs`) | `live/logs_live/`, `components/log_entry.ex` | `Web.Audio` (database), `Web.Media` (ffmpeg) | `logs.css`, `.nx01` | The list page must not load a player. The player element is `phx-update="ignore"`: do not put changing markup inside it |
| Photographs (`/negatives`) | `live/negatives_live.ex`, `live/negatives_live/` | `Web.Negatives` reads scans from a folder outside the repo | `negatives.css`, `.darkroom` | The address is the whole state: every control is a link built by `NegativesLive.Format`. Never keep view state in an assign that the address does not carry |
| Fitness plan (`/fitness`, `/fitness/day/:day`) | `live/fitness_live/index.ex` | `Web.Fitness`, `Web.Fitness.Vault` (markdown) | `steel.css`, `.steel` | Days link with `navigate`, never `patch`. Never show a time of day to a visitor |
| Exercise wiki (`/fitness/wiki`) | `live/fitness_live/wiki.ex`, `show.ex`, `components/fitness_figure.ex` | `Web.Fitness.Vault`, `Web.Fitness.Figure`, `Web.Fitness.Clip` | `fitness_wiki.css`, `.steel` | The moving figure is a film made elsewhere. See `figures-handoff.md` |
| Activities (`/fitness/rides`) | `live/rides_live/`, `components/activity.ex` | `Web.Rides` (database, synced from Komoot hourly) | `rides.css`, `.steel` | **Privacy.** A ride is shown through Komoot only when `Rides.clear?/1`. Never show a map, a start point or a time yourself |
| Daybook (`/daybook`, `/day/:date`) | `controllers/almanac_html/` | `Web.Almanac` (built from the other sections' dates) | `almanac.css` | An empty day or week is a 404 on purpose. Never link one |
| Prayer (`/Christ/...`) | `controllers/faith_html.ex`, `faith_html/` | `Web.Liturgy.*`, `Web.Bible` (files in `priv/`) | `faith.css`, `.faith` | Nothing is fetched from another site, ever. Do not add explanation text. Do not edit `priv/liturgy` or `priv/bible` |
| Search (`/search`) | `PageController.search`, `page_html/` | `Web.Search` | `search.css` | **Every public page must be findable**: a test walks the router and fails if a new address is missing from `Web.Search` |
| Guestbook (`/guestbook`) | `live/guestbook_live.ex` | `Web.General` | `guestbook.css` | A signer's contact detail is encrypted. Never print, log, export or email it |
| Newsletter (`/newsletter`, `/contact`) | `live/newsletter_live.ex`, `newsletter_overlay_live.ex` | `Web.Newsletter`, `Web.Contact` | `glass.css` | The overlay lives in every page's frame. What it assigns affects every page |
| Letters (foot of posts, logs, frames) | `live/letters_live.ex` | `Web.Letters`, `Web.Pieces` | `letters.css` | A nested live view: it gets the visitor's address from its session, not from the socket |
| Manual (`/how-to`), roadmap | `PageController`, `Web.Docs` | `docs/how-to.md`, the roadmap file | `how-to.css` | The manual is public and live the moment the file is saved. A table's first column must be short |
| Terminal (`/pc`) | `live/pc_live.ex` | `Web.Pc` | `pc.css` | Reads optional files at compile time: must compile when they are absent |
| Feed, sitemap, share cards | `feed_controller.ex`, `sitemap_controller.ex`, `share_controller.ex` | `Web.ShareCard` | none | Unlisted pages (`/food`, `/england2026`) stay out of all three |
| 404 | `error_html/not_found.html.heex`, `not_found.ex` | `Web.Nearby` | `not_found.css` | It is a whole HTML document with no layout. It must never raise |
| Admin (`/admin/...`) | `live/admin_live/`, `components/admin_components.ex` | each area's own module | `assets/css/admin/` (`adm-` classes; `base.css` is shared) | A new admin page goes inside `live_session :admin` in the router, or it is open to the world |

Behind the pages (no HTML of their own): `Web.Backup` (nightly copies), `Web.Monitor` (the
machine checks itself), `Web.Scheduler` (timed jobs), `Web.Analytics` (counting readers),
`Web.Webmentions`, `Web.Komoot`, `Web.Scanner`. Leave these alone unless a task names one.

#### How much care each part needs

- **Free to change with tests:** the public pages' markup and stylesheets, `core_components.ex`,
  `Web.Search`, `Web.Almanac`, `Web.Nearby`, `Web.Keywords`, the blog's and wiki's reading
  code, tests, `docs/`.
- **Change only when a task names it, and say so in your report:** anything in `Web.Rides`
  (privacy), `Web.General` (the guestbook's sealed contact), `Web.Analytics` and the `/seen`
  beacon (reader counts), `Web.Audio` and `Web.Media`, the admin pages, `assets/js/app.js`
  and `trail.js`, the root layout, `router.ex`.
- **Never** (rule 5): the scanner, deploy scripts, configuration that the live site boots
  from, migrations, the owner's content, the prayer pages' data.

#### Recipes

**Add a public page.**
1. Add the route in `router.ex` beside its section's other routes, inside the `:browser`
   scope. A live page goes in the existing public `live_session`.
2. Put its outermost element in the section's theme class (`steel`, `darkroom`, `nx01`,
   `faith`, or none for paper) and draw the header with `<.blog_header ... />` as a
   neighbouring page does. Copy a neighbour; do not invent a frame.
3. Add it to `Web.Search` (its `@fixed` list: title, path, one line, other words for it), or
   `test/web_web/search_test.exs` fails.
4. Add it to `sitemap_controller.ex` if a search engine should find it.
5. Test: the page answers 200, shows its heading, and is found by a search for its name.

**Add something to an existing page.** Find the function that already supplies that page's
data (`grep -n "def " lib/web/<area>.ex`). Use it. Do not read files or query the database
from a template or a component.

**Add a style.** Find the page's stylesheet in the table above. Use tokens. Give the class a
prefix the file already uses. If the page is under a theme class, look at the result in that
theme's terms: under `.darkroom`, `.nx01` and `.faith` the ink is light and the paper dark.
After any CSS change run `mix assets.build 2>&1 | tail -3`; it must end without an error.

**Add a click or a key that needs JavaScript.** First try without: a link, a `<details>`, a
form. If it must be a script, a live page uses a colocated hook (search for `phx-hook=".`
to see one); a controller page uses a delegated listener in `assets/js/app.js`. Never add a
`<script>` tag to a template and never add a library.

**Add an icon.** Use `<.icon name="hero-..." />` and add that exact name to the
`@source inline(...)` list in `assets/css/app.css`. Then run `mix assets.build`.

**Add a site setting.** `Web.SiteSettings.get_setting(key, default)` reads one. The form is
`live/admin_live/settings.ex`. A setting cannot be saved empty. No migration is needed.

**Change how content files are read** (a new frontmatter key, a new embed). Change the
reading module, keep every existing file valid, add a fixture under `test/support/fixtures/`
that uses the new thing, and never write to `content/`.

**Count or measure readers.** Do not. The counting has two halves (the plug and the `/seen`
beacon) that must agree, and a test pins both.

#### Things that look like bugs and are not

- Class names from an older design (`blog-bento-*`, `almanac-*`, `faith-*`, `Faith*`,
  `Almanac*`) on pages now called something else. Leave the names.
- `/almanac`, `/faith`, `/christ`, `/audio`, `/manuscripts`, `/rides`, `/archive`: old
  addresses that redirect. Leave them.
- Tailwind is installed but generates nothing. That is deliberate.
- One test fails in the owner's folder (a private one about the week's timetable). In your
  copy it does not exist.
- Tables named `blog_posts`, `tags`, `post_tags`: nothing reads them. Leave them.

### 5. The loop for every task

1. Read the task. Open every file it names. Search for anything it does not name.
2. Find the test file for that page (`grep -rln "<a word from the page>" test/`). Read it.
3. Make the smallest change that does the task. Match the code around it.
4. Add or change a test that would fail without your change.
5. Run, in this order, and fix until all three are clean:
   ```bash
   mix format
   mix compile --warnings-as-errors 2>&1 | tail -5
   mix test 2>&1 | tail -5
   ```
6. `git add` only the files you changed, then `git commit -m "<task number>: <what changed>"`.
7. Write three lines in `tmp/gemini-report.md`: the task, the files, what you could not check.

If step 5 is not clean after three tries, undo your change to those files with
`git checkout <file>` (one file at a time, only files you edited for this task), record the
failure in the report, and move on.

### 6. The tasks, in order

These come from a first-time visitor's review of the site on 2026-10-11. Each was checked
against the code. Where the review was wrong, the task says so. **Do not do anything from
the review that is not in this list.**

#### A. Plain bugs (do these first)

**A1. Every browser tab says "Dispatch".** The newsletter panel that lives in every page's
frame sets the page title. In `lib/web_web/live/newsletter_overlay_live.ex` remove the
`page_title` it assigns (leave `newsletter_live.ex` alone: that one is the newsletter's own
page). Test: a page other than `/newsletter` has a `<title>` that is not "Dispatch".

**A2. The fitness tabs hide the page you are on.** `fitness_subnav.ex` leaves out the current
page's tab, so each page shows a different pair. Show all three, always in the order Regimen,
Wiki, Activities, and mark the current one with `aria-current="page"` and the existing
"current" look of the section (search `steel.css` for how a current choice is styled: solid
ink). Test: each of the three pages shows three tabs.

**A3. A day page has no way forward.** Find the day page (`grep -rn "rel=\"prev\"" lib/`).
It links the previous day that has work. Add the next day that has work, the same way, with
`rel="next"`. `Web.Almanac` already knows which days have work; reuse what "previous" uses.
Never link an empty day.

**A4. The prayer page prints words twice.** "Morning Morning Prayer", "Psalm Psalm 117". In
`lib/web_web/controllers/faith_html/` find where a label is put before a name and do not add
the label when the name already begins with it. Add a test with one such name.

**A5. A reading can be printed twice.** When a day offers a longer and a shorter form of the
same Gospel, both are printed in full. Print the longer one, and offer the shorter as a
closed `<details>` under it, as the page does for other optional text. Also: a psalm citation
such as "1-3, 3-4" prints verse 3 twice; print each verse once. If you cannot find where
either happens within ten minutes of searching, skip A5 and say so.

**A6. Small text errors.** Fix exactly these and nothing else:
- `/how-to` gives a frame's address as `/negatives/roll/7/frame/3`. The real form is
  `/negatives/roll/007/frame/3`. The file is `docs/how-to.md`.
- "Walk ; 5–10 min" has a space before the semicolon. It comes from `content/`, which you
  may not edit: **report it, do not fix it.** The same for "perusing an education" on the
  About page and the two broken lists in the roadmap.

#### B. Finding your way round the site

**B1. A section bar on every page.** This is the most valuable task. The 404 page already
has a bar of the site's sections. Put the same bar on every public page, under the header
drawn by `blog_header/1` in `core_components.ex`: Blog, Captain's logs, Photographs, Fitness,
Daybook, About. Rules for it:
- It is one component, used by the 404 page and the header, not two copies.
- The section you are in carries `aria-current="page"`.
- **Do not add a link to `/Christ`, `/food` or `/england2026`.** The owner decides where
  those are linked.
- It must not push a phone's page sideways: on a narrow screen it scrolls sideways inside
  itself (`overflow-x: auto`), it does not wrap to three lines.
- Each theme re-inks the same tokens (`.steel`, `.darkroom`, `.nx01`, `.faith`). Use tokens
  only and it will follow. Under `.darkroom`, `.nx01` and `.faith`, `--ink` is a light colour.
- `test/web_web/search_test.exs` and the homepage tests count links. If one fails, read the
  failure; do not delete the test.

**B2. The back button says where it goes.** `blog_header/1` draws a back link whose words
come from a script (`assets/js/trail.js`) that remembers the last page. It shows titles such
as "DISPATCH" or a cut-off date. Change only what is shown: when the remembered page is the
homepage show "Home"; when its title is longer than 18 characters show its section's name
instead (Blog, Photographs, Fitness, Daybook, Captain's logs). Do not change where the link
goes or what the script remembers.

**B3. One name per section.** A visitor clicks "[BLOG]" and lands on "Written Work". Make
what the visitor reads agree, changing **text only** (no address, no module, no CSS class):
- the homepage tile and the page heading for the blog say the same thing: use "Written work";
- the homepage footer link and the `/how-to` heading say the same thing: use "How this is made";
- the top bar's "Newsletter & Contact" stays; the newsletter page's heading becomes
  "Newsletter" with "Dispatch" kept as the smaller line under it.
Tests assert some of these strings. Change the test's expected words when, and only when,
the task changed those words.

**B4. Tell a first visitor what things are.** One short line each, in the page's own quiet
caption style, no new components:
- homepage: under the wordmark, one sentence saying what the site is. **Do not write it
  yourself.** Add the place for it, reading `site_description` from site settings
  (`Web.SiteSettings.get_setting/2`) and showing nothing when it is empty.
- the Captain's logs tile on the homepage: add the word "video" or "audio" as a small label
  only if the tile already has a place for a caption; otherwise report.
- a contact sheet: under the sheet, "Circled frames are printed. Frame numbers skip where a
  frame was blank." 
- the blog index: `title="How many different people have read it"` on the "witnessed" figure.

**B5. A frame can go back as well as forward.** The single-photograph view shows only a
"next" arrow though the left arrow key works. Add the matching "previous" link beside it,
built by the same module that builds "next" (`WebWeb.NegativesLive.Format`). Stop at the
first frame; do not wrap round.

**B6. A post leads somewhere.** At the foot of a blog post, above the letters, link the next
older and next newer post by title. `Web.Blog.list_posts/0` is already sorted; drafts are
never in it.

#### C. Do not do these. The review was wrong, or the choice is the owner's

- **The prayer page's address and privacy.** The real address is `/Christ` with a capital,
  `robots.txt` is correct, and `/faith` and `/christ` redirect to it. The owner put it on
  the homepage and in the search on purpose. Change nothing.
- **"1 of 52" on the roll pager.** Four rolls are not public. The count is of public rolls
  and is right. Change nothing.
- **Two dates for one roll** (scan date in the archive, another in the daybook). The owner
  chose to file rolls by scan date. Report if you find a page that disagrees with that;
  change nothing.
- **The homepage's layout and wordmark**, the "Admin Dashboard" link in its footer, the feed
  being all rolls after a scanning day, the `/pc` terminal, British spellings, the list of
  blocked crawlers. Leave them. List them in your report under "for the owner".
- **The newsletter page being empty behind its panel.** Needs a design decision. Report only.

### 7. When you stop

Finish `tmp/gemini-report.md` with: the tasks done (one line each with its commit), the tasks
skipped and why, everything under "for the owner", the last three lines of `mix test`, and
anything in this document that was wrong. Then stop. Do not merge, push or deploy.

---

## Exercise figures: handoff to another agent

Written 2026-10-10 for an agent that has never seen this project (Gemini Flash in
Google Antigravity, or anyone). Read all of it before running anything. It is a procedure
to follow, not background to skim.

### What you are working on

The exercise wiki (`/fitness/wiki/<slug>`) shows, for each of 113 exercises, a short looping
film of a 3D figure doing the exercise. Each film is rendered from a small pose file. Your
job is to make the figures correct, one at a time, by editing pose files and re-rendering.

You are **not** redesigning the body, the renderer, or the website.

Six things about the film are worked out for you. Do not try to set them in a pose file,
and do not edit the code that does them:

- **Which muscles are lit, and how strongly.** Three strengths. Full: the muscles the
  exercise's page names (**primary**). Half: the links that steady the load, such as the grip
  under a weight and the trunk between the hands and the floor (**chain**). Faint: the rest of
  the body holding still, such as the legs under a standing lift (**brace**). The page gives
  the first; rules read the other two off the figure (`lib/web/fitness/chain.ex`): where the
  load is, and what the body rests on.
- **Hands, wrists, shoulders and feet.** A hand has no fingers: it is a palm and a plate of
  fingers hinged at the knuckles, on a wrist that bends. What it does is read off what is
  beside it. Round a bar, a handle or a band's end it is a fist. On a floor, a box or a wall
  it lies flat with the wrist bent back under the forearm. On a ball, a dome or a bell the
  fingers fold over the curve. With nothing near it, it is a loose fist that hangs a little
  from the wrist when the arm is held level. The shoulder rises with an arm reaching overhead
  and comes forward with one reaching out. A foot up on its toes bends where the toes begin.
  **The only way you change a hand is by where you put it**: a hand "on the floor" at y = 95
  is four units above the floor, so it is drawn as a fist hovering in the air. Put it at
  y = 99 (or on the top of the box, or on the bar) and the hand changes by itself.
- **The weights** (redrawn 2026-10-11) are dark iron on bright steel. A dumbbell is a steel
  handle through two flat-faced iron heads. A barbell has a big plate, a smaller plate and a
  collar on each end. A kettlebell has a handle, a flat foot and a steel band round it. You
  place a weight only by placing the hand: put the hand where the handle should be and the
  weight follows. A dumbbell's handle always lies across the palm.
- **A lit muscle is a hard-edged orange area with a dark seam round it**, set into the body
  like an inlaid panel. Full orange is `primary`, paler is `chain`, faint is `brace`. It is
  exactly the muscle's own shape, so it is smaller than in older stills. An orange area with
  no seam, or a seam with no orange inside it, is a fault to report.
- **The whole body is built from bone outward** (the chest since 2026-10-10, everything else
  since 2026-10-11). Thin bones and joints come first: a rib cage narrower than the
  shoulders, collar bones, shoulder blades, a pelvis, and a bone in each limb. Each muscle is
  then laid from the bone it starts on to the bone it ends on, so it follows the joint
  between them, and it keeps its volume. You cannot pose any of this and need not: it
  follows from where the pelvis, hands, elbows, knees and feet are. When you look at a still,
  these are **correct, not faults**:
  - The pectoral and the lat are drawn out toward a raised arm and make the two folds of the
    armpit.
  - The biceps stands up when the elbow is bent and lies long when the arm is straight. The
    triceps does the opposite. The deltoid stands up over a raised arm.
  - The front of the thigh is thinner in a deep squat than standing; the back of the thigh
    is thicker with the knee bent. The buttock is drawn down under the hip in a squat or a
    lunge.
  - The calf stands out when the figure is up on its toes.
  - The belly is shorter and thicker when the trunk curls forward (a crunch, a hollow hold).
  - The waist is narrower than the ribs and the hips, the legs taper to the knee and the
    ankle, and there is a furrow down the middle of the back.

  What **is** a fault, and worth reporting (not fixing): a flap or slit where the belly should
  be smooth, skin showing through the shorts, a limb that looks broken at a joint, a ball
  stuck on a knee or an elbow. Say which slug and which pose.
- **The body's proportions are measured, not judged by eye** (since 2026-10-11). The command
  `mix fitness.film --measure` stands the figure upright and compares 31 of its measurements
  with those of lean men from a public survey of 4,082 soldiers (ANSUR II). You may run it;
  it takes 7 seconds, draws nothing and changes nothing. It must end with
  `5 of 31 measures are more than 8% from the men's`. If it says anything else, stop and
  report: someone has changed the body. Because of it these are also **correct, not
  faults**:
  - The hips are much narrower than the shoulders and only a little wider than the waist.
  - **The head is a plain ball with four black strokes on it and no hair, nose or ears.**
    That is the owner's own drawing of a head, traced: a line down the middle of the face,
    two arcs that make a lens across it, and a short stroke low on the middle line. The
    strokes are on the side of the head the figure is facing, so from the side you see
    only part of them and from behind almost none. Never report the face as missing or
    wrong unless the strokes are on the wrong side of the head for the exercise.
  - The shoulders slope down from the neck when the arms hang.
  - The crotch is high and the legs look long.

  And these are **known and wrong; do not report them, do not try to fix them**:
  - Where a hand lies flat (a push-up, a plank) the forearm is a fifth too long and the
    hand short.
  - The ankle is low: the foot looks flat.
  - The upper arm is a little short while the arm hangs.
  - The thighs never touch each other, even at the top.
  - Where a limb folds on itself (a deep squat, the top of a curl) the two parts run
    together; there is no crease.

### Rules you must not break

1. **Never deploy, restart or stop anything.** Do not run `./redeploy.sh`, `./rollback.sh`,
   `systemctl`, `mix phx.server` or `iex -S mix phx.server`. This machine is the live server.
2. **One render at a time.** Never start a second `mix fitness.film` while one is running, and
   never run it in parallel. It used to produce blank pictures silently. The cause was found
   and fixed on 2026-10-11 (the graphics driver was resetting long draws), but two at once
   are still slower than one after the other, and the fix has been tried only a few times.
3. **Do not add a key to a pose file that this document does not list.** The live site refuses
   a pose file with a key it does not know and the page then shows no figure at all.
4. **`stance` and `grip` may be used** (the site was deployed on 2026-10-11 and knows both).
   Use `stance` only where the exercise needs the feet apart (a kettlebell swing, a goblet
   squat, a sumo deadlift): a number from 6 to 11, the same in every pose of the file.
5. **Do not delete files.** Do not edit anything outside the paths in "Files you may edit".
6. **Do not commit or push** unless the owner asks. The pose files are not in git at all.
7. **Never say a figure is right because it validates.** A file that passes every check can
   still be a picture of the wrong exercise. You must open the still images and look.
8. If a command fails twice, stop and write down what happened. Do not improvise around it.

### Files

| Path | What it is | May you edit it? |
|---|---|---|
| `content/fitness/figures/<slug>.json` | The pose file for one exercise | **Yes** |
| `content/fitness/exercise-wiki/<group>/<slug>.md` | The exercise's page. Read "Goal" and "Execution" | No |
| `tmp/figure-refs/photos/<slug>-0.jpg`, `-1.jpg` | Reference photographs, start and end, for 47 exercises (`tmp/figure-refs/map.json` lists which) | No |
| `tmp/figure-audit.md` | An earlier audit's notes per figure. Leads, not facts | No |
| `lib/web/fitness/figure.ex` | The pose engine. Its `@moduledoc` documents every pose key | No (read it) |
| `priv/figure/figure3d.js` | The 3D body and renderer | No |
| `priv/figure/check.mjs` | The rule checker | No |
| `lib/web/fitness/chain.ex` | The rules for which muscles are lit at half and faint strength | No |

All commands are run from the repository root, `~/streetscissors`.

### The pose file, in one screen

The stage is 160 wide. The floor is y = 100 and **y grows downward**. A standing figure is
about 80 tall. A foot or hand resting on the floor is at y = 99. A body lying down has its
pelvis at y = 95. The figure faces right (+x).

```json
{
  "view": "side",
  "planted": ["foot_a", "foot_b"],
  "props": [{"kind": "mat", "from": 30, "to": 130},
            {"kind": "kettlebell", "hold": "hands", "mode": "hang"}],
  "poses": [
    {"name": "stand", "hold": 0.3, "move": 1.2, "pelvis": [80, 60], "lean": 0,
     "feet": [80, 99], "hands": [86, 42], "elbows": "down", "knees": "front"},
    {"name": "bottom", "hold": 0.4, "move": 1.2, "pelvis": [70, 82], "lean": 25,
     "feet": [80, 99], "hands": [84, 62], "elbows": "down", "knees": "front"}
  ]
}
```

- `pelvis` `[x, y]`: the hip joint. `lean`: the back's angle from upright in degrees,
  positive toward the facing side (90 = face down, -90 = on the back). `curl`: rounding of
  the upper back. `head`: the neck. `turn`: shoulders turned about the spine.
- Where a hand or foot **is**: `hand_a`, `hand_b`, `foot_a`, `foot_b` as `[x, y]`, or `hands`
  / `feet` for both. `a` is the near limb. Elbows and knees are worked out for you.
- Or where a limb **points**: `arm_a`, `arm_b`, `leg_a`, `leg_b` (or `arms`, `legs`) as
  `[angle, reach]`: angle from straight up turning toward the facing side (90 = forward,
  180 = down), reach from 0 to 1.
- `elbows` / `knees` (or `elbow_a` …): which way the joint bends: `up`, `down`, `front`,
  `back`, `headward`, `feetward`. **If the same joint bends different ways in two poses the
  file is refused**; give the same word in every pose.
- `side` (-1 to 1), `spread` (stage units, hands apart), `flare` (0 to 1, elbows out): depth
  cues. `spread` must be in every pose of a file or in none.
- Props: `mat`, `box` / `block` (`x`, `y`, `w`, `h`), `disc` (`at`, `r`: a bar seen end-on),
  `dome`, `line` (`from`, `to`, `style`: `band` or `pole`, optional `depth`), and held weights
  `kettlebell`, `dumbbell`, `bar`, `ball` with `hold` (`hands`, `hand_a`, `hand_b`) and `mode`
  (`hang` = below the hand, `arm` = in line with the forearm, `up` = above the hand).
- `name`, `hold` (seconds in the pose), `move` (seconds to reach the next pose).

The full list is the `@moduledoc` of `lib/web/fitness/figure.ex`. If a key is not there and
not here, it does not exist.

### The four commands

```bash
# 1. The rules. Fast (2 seconds for everything), draws nothing. Also reports a file the
#    pose engine refuses, and why.
mix fitness.film --check <slug>

# 2. A picture of every pose, to look at. About 12 seconds. Writes <slug>-0.png, -1.png …
timeout -k 5 150 mix fitness.film --stills /tmp/figure-stills <slug> < /dev/null

# 3. The film, onto the live site. About 90 seconds. Must print "1 filmed".
UPLOADS_PATH=$HOME/streetscissors-data/uploads timeout -k 5 300 mix fitness.film --all <slug> < /dev/null
```

```bash
# 4. Which muscles the film will light, in three strengths. Instant.
mix fitness.film --tiers <slug>
```

Always keep the `timeout` and the `< /dev/null`. A render can hang, and inside a loop the
command will otherwise swallow the rest of your list. If command 2 prints nothing and writes
no file, the pose file is invalid: run command 1 to see why.

### The algorithm, for one figure

Do these steps in order. Do not skip a step. Do not batch several figures into one step.

1. **Read** the page's "Goal" and "Execution". Write one sentence: the body position at the
   start, at the end, and what is held.
2. **Look** at `tmp/figure-refs/photos/<slug>-0.jpg` and `-1.jpg` if they exist. They show the
   real start and end. (A few are a near relative of the exercise, not the same one: the
   page's text wins over the photograph.)
3. **Check**: `mix fitness.film --check <slug>`. Note every line it prints.
4. **Draw** the stills (command 2) and open every image. For each pose answer, in writing:
   - Is the posture what the page says (standing, seated, lying, which way up)?
   - Are the hands on what they should hold, and the feet on the floor or the box? A hand
     meant to rest on something must be drawn flat on it (or wrapped over it, if it is
     round), and a hand meant to hold a bar must be a fist round it. A loose fist near a
     surface or a bar means the pose has the hand a few units off: move the hand, not
     anything else.
   - Is the equipment there, in the right place, and not through the body?
   - Does the pose match the reference photograph?
   - Are the lit muscles sensible? Run command 4. Strongest orange should be on the muscles
     the page names, paler on the grip and trunk carrying the load, faintest on what only
     holds the body up. If a tier looks wrong (for example legs lit on a seated exercise),
     **write it in your log and change nothing**: the fix is in the rules, not the pose file,
     and the rules are not yours to edit. One exception: if the tiers are wrong because the
     *pose* is wrong (a figure meant to be seated whose hips float above its bench, a hand
     meant to be on the floor that hovers above it), fix the pose.
5. If steps 3 and 4 found **nothing wrong**: go to step 9.
6. **Change one thing** in the pose file: the smallest edit that fixes the worst problem.
   Typical edits: move `hands`, move `pelvis`, change `lean`, move a prop. Keep `planted`
   limbs in the same place in every pose.
7. **Check again** (command 1). If the engine refuses the file, read its message; it names
   the pose and the limb. "out of reach" means move the hand or foot closer to the body, or
   the pelvis toward it. "bends one way in … and the other in …" means give that joint the
   same direction word in every pose.
8. **Draw again** and look (step 4). Repeat steps 6 to 8 **at most three times**. If the
   figure is still wrong after three, undo your edits to that file, record it as "could not
   fix" with the reason, and move to the next figure.
9. **Film** it (command 3) and confirm it printed `1 filmed`.
10. **Record** one line in your log: slug, what was wrong, what you changed, result.

Keep a copy of every pose file before your first edit to it, in a folder of your own, so
step 8's "undo" is a copy back.

### What "right" means

- The rule check prints nothing for the figure, **or** only prints something listed under
  "Known limits" below.
- Every pose image shows the exercise the page describes.
- Start and end poses differ visibly in the way the movement goes.
- Nothing is cut off by the edge of the picture.

### Known limits: do not try to fix these with pose edits

- **Hex-bar figures** (`hexbar-carries`, `hexbar-jumps`, `hexbar-rdl`, `hex-flat-side-deadlift`):
  there is no hex-bar prop, so the bar is drawn through the hips. Leave.

Record these as "known limit" and move on.

### The work, in order

**Task 1. Make sure every film is of the current look.** The owner's assistant began
re-filming all 113 on 2026-10-11 with this script, which films one figure at a time, writes a
line per figure to `tmp/film-all.log`, and skips what is already done when run again:

```bash
./tmp/film-all.sh >> tmp/film-all.log 2>&1
tail -3 tmp/film-all.log
```

Run it. It must end `pass finished: 113 of 113 filmed`. If it says fewer, run it again; if a
slug fails twice, write it down and go on. A whole pass is about three hours (95 seconds a
film), but only the missing ones are filmed.

**Whenever you change a pose file, film that figure again** (command 3), or its page falls
back to a flat drawing.

Then look for black frames. Until 2026-10-11 the renderer could give black pictures (the
graphics driver reset a draw that ran too long). That is fixed, and a render that loses the
graphics card now stops with an error instead of going on in black, but check all the same,
because a film with a black frame in it flashes. For every film:

```bash
cd ~/streetscissors-data/uploads/figures
for f in *.mp4; do
  n=$(ffmpeg -nostdin -i "$f" -vf blackframe=amount=98:threshold=20 -an -f null - 2>&1 | grep -c Parsed_blackframe)
  [ "$n" -gt 0 ] && echo "$f: $n black frame(s)"
done
```

It should print nothing. Film again any slug it names (the slug is the file's name without
the last `-xxxxxxxxxxxx`). A still that comes out all black or all white is the same fault:
draw it again before judging the pose.

**Task 2. The figures the rule check still flags.** Run `mix fitness.film --check` with no
slug. Apply the algorithm to each figure it lists that is not a known limit. Expected:
`medicine-ball-rotational-throws`, `couch-stretch`, `decline-leg-raises`, `lat-smashes`,
`thoracic-roller-extension`. With the known limits that is eleven figures in all; a twelfth
means something new has broken.

**Task 2b. A pass over the lit muscles.** Run command 4 for every slug and read the three
lists against the exercise. You are looking for the rules guessing the body's situation
wrong: a seated exercise treated as standing (legs in `brace`), an exercise with a band that
shows no `chain`, a hanging exercise with no `forearms`. Do not fix anything. Make a table:
slug, what the tiers say, what looks wrong and why. That table is the most useful thing you
can hand back, because it is how the rules get better.

**Task 3. The audit's leftovers.** `push-up-plus` (elbows should stay straight; only the
upper back rounds), `banded-ankle-dorsiflexion` (the front knee should travel forward over the
toes), `sub-maximal-holds` (hands should grip the edge, not pass through the slab),
`tricep-pushdowns`, `incline-dumbbell-press` (the bench back should lie under the torso).

**Task 4. The gym and kettlebell exercises against their photographs.** For each slug in
`tmp/figure-refs/map.json`, apply the algorithm. Start with the kettlebell circuit:
`goblet-squats`, `kb-swings`, `kb-single-arm-row`, `kb-russian-twist`, `kb-pullover`,
`kb-half-kneeling-press`, `kb-lunges`, `kb-halos`, `kb-side-plank-reach`, `plank`, `push-ups`,
`single-leg-calf-raises`, `hollow-hold`, `y-t-w-raises`.

Stop after any task if you are unsure, and report.

### When you finish, or stop

Write a report with: the figures you changed and what you changed in each; the figures you
could not fix and why; the last output of `mix fitness.film --check`; the table from Task 2b;
any fault in the body itself (slug and pose; see "correct, not faults" above for what is not
one); and anything in this document that turned out to be wrong.

---

## Get Sharp — Self-Auditing Autonomous Claude Code Playbook (v4)

### 0. Claude Self-Audit Protocol & Live-Host Errata Ledger

Because `content/` (the Obsidian vault), `scripts/`, and the live SQLite database (`*.db`) are gitignored in the public repository, this document was authored against the tracked application code and test fixtures. You (Claude) have permission and responsibility to audit and edit this document (`docs/get-sharp-handoff.md`) in place whenever live-host files, line numbers, or database rows differ from what is written here.

#### 0A. How to Audit This Document (Run Session 0 Before Session 1)

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

#### 0B. Live-Host Errata & Session Progress Ledger (Claude Updates This Block)

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
| v2 brief: generic check-ins, prescriptions, weekly report; KB redo | [x] Done 2026-10-19, deployed the same night | `16652d2` (code); content/fitness/{checkins.md, blocks/get-sharp.md, modules/kb-primer-upper.md, modules/kb-primer-lower.md, modules/kb-full-body.md, changelog.md} (gitignored) | **Dates:** the author's answer, "today to the 20th, consider this week 0": week 0 (Setup) is Oct 19–25, weeks 1–8 Oct 26 – Dec 20, phases 1–2 Baseline, 3–6 Push, 7 Peak, 8 Deload. **Check-ins:** questions are `content/fitness/checkins.md` (`Web.Fitness.Checks`); the table keeps one `answers` map a day (migration `20261019235956`, which drops the old columns; the live table had 0 rows). `save_checkin/2` takes the checks and refuses a non-number for a number check. **Plan:** `Web.Fitness.Prescription` reads a day's lines (the *first* line naming a slug is its plan, so a primer must never link a block lift); `Web.Fitness.Coach` gives each line's note, guardrail, target and form defaults; the log form is dropdowns by kind, with a one-tap Done. **Report:** `Web.Fitness.Report` renders `scripts/fitness_report.qmd` Sundays and on demand to `fitness-reports/` beside the uploads root, at `/admin/fitness/report[/:date]` (admin only); the block file passed is the running block's, by its slug. **Kettlebells (the author's ask, 2026-10-19, applying Proposal O):** the 14-move circuit is retired to `content/notes/fitness-retired/`; Tue/Thu open with a 4-move primer; the full circuit is `kb-full-body` on Saturday (10 moves, no block lift, so Saturday stays out of compliance). **Tests:** `mix precommit` 1622 tests, the one failure the private `week.md` test, failing before this. |

##### Session 0 findings (2026-10-19)

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

### 1. Token & Session Discipline (Read First — Saves ~75% of Context Spend)

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

### 2. Pre-Extracted Codebase Map & Test Invariants (Zero-Grep Reference)

#### 2A. Exact File & Line Map

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

#### 2B. ExUnit Test Invariants You Must Not Break

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

### 3. Canonical Domain Specification (Deliverables A–Q)

#### 3.1 The 8-Week Block & Progression Rules (Deliverables A.1–2, B.3–8)

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

#### 3.2 Guardrails, Changelog, Experiment Reports & Visual Check-Ins (Deliverables C.9, E.11, F.12, G.13, H.14)

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

#### 3.3 Homepage "Happening" Module (Deliverable I.15)

- `Web.Happening` (`lib/web/happening.ex`):
  - Now: Current block + week/phase (`Get Sharp · Week 1 of 8 — Baseline`), newest clear Komoot activity from `Web.Rides` (date, sport, distance — never clock time or coordinates), and current reading from `content/now.md` (omitted when absent).
  - Fresh: Newest published blog post, ready Captain's Log, negatives roll, and fitness update.
  - Witnessed (7d): Top 3 most-viewed public pieces in the last 7 days from `analytics_hits` (distinct `ip_hash`). Never surface `/food`, `/england2026`, `/Christ`, `/admin`, or drafts.

#### 3.4 Dual-Purpose Arms & KB Primer/Conditioning Proposals (Deliverables M, N, O)

*Written by Claude, 2026-10-19. These are proposals only. Nothing goes into `weekly/` or `modules/` until the author approves it.*

Each proposal is a file in `content/notes/fitness-proposals/` (private, rendered by no page), and each uses only slugs that already exist:
- **M — Tuesday arms that also serve the press** (`tuesday-arms.md`): swap the end of `upper-taper` for `zottman-curls` + `tricep-pushdowns` as a superset, keeping `bfr-arm-finisher` as the last-week option. Grip and elbow work then carries into the Friday press.
- **N — Friday dual-purpose arms** (`friday-arms.md`): `hammer-curls` and `tricep-pushdowns` after `shoulder-press`, with `face-pulls` kept for shoulder health. The weekly arm total is no larger than today's.
- **O — Saturday KB primer vs conditioning** (`saturday-kb.md`). Two variants, of which the author picks one or neither:
  - (a) **primer**, 15 minutes before the hike: `kb-swings`, `kb-half-kneeling-press`, `goblet-squats`.
  - (b) **conditioning**, 20 minutes on a non-ride Saturday: `kb-swings`, `farmers-walk`, `medicine-ball-slams` as EMOM.
- **Exercises without wiki pages.** The v4 names `kettlebell-clean-and-press`, `overhead-triceps-extension` and `dumbbell-rdl` have no wiki page, and the nearest pages are used instead: `kb-half-kneeling-press`, `tricep-pushdowns` and `hexbar-rdl`/`single-leg-rdl`. A page is written only if the author asks for the exact exercise.
- **On approval:** edit the module, add a changelog entry (§3.2), and run `ContentHealth`, which must show no broken links.

#### 3.5 R / Quarto Pipeline & Gated N-of-1 ML (Deliverables P & Q)

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

### 4. Copy-Paste Autonomous Session Prompts (Run One Per Session, `/clear` Between Sessions)

#### Session 0 — Claude Pre-Flight Self-Audit (Audits & Patches This Playbook)

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

#### Session 1 — The Block File & Thursday Content (Deliverables A.1–2)

1. Create `content/fitness/blocks/get-sharp.md` exactly as in §3.1: the frontmatter, plus a body with `## Hypothesis`, `## Question` and `## Stopping rules` (pointing to §3.2's guardrails). Every `[[link]]` in it must be a real wiki slug, because `ContentHealth.vault_links/0` scans all of `content/fitness/`.
2. In `content/fitness/modules/lower-durability.md`:
   - Add a `#### Power primer: 3 x 3` block holding `[[box-jumps|Box Jumps]]` before `#### Hinge`.
   - Make the hinge range read `3 x 5–8`, as the block says.
3. In `content/fitness/weekly/thursday.md`, add the frontmatter line `block: get-sharp`. That is the only change to the day file.
4. This is content only, and it goes live as soon as it is saved. Check it with `mix run --no-start` (Vault reads the module and the links resolve). No commit except this doc.

#### Session 2 — Security Fix, Structured Log Metrics, `Web.Fitness.Block` & `Web.Fitness.Progression` (Step 0 + Deliverable B.3)

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

#### Session 3 — e1RM Trends, Volume Load, Compliance, Stress/ACWR, History & Wiki Biographies (Deliverables B.4–8 & D.10)

1. **`WebWeb.FitnessCharts`** (`lib/web_web/components/fitness_charts.ex`):
   - Zero-JS inline SVG copying `Web.Blog.Embeds`' `nice_ticks/1`, `line_series_svg/3` and `bar_row_svg/3` (copied, not called: they are private).
   - It draws an e1RM line per lift, weekly volume load per pattern, compliance per week, and ACWR per pattern with a 0.8–1.3 band and a 1.5 rule.
   - Colours come from steel tokens only.
2. Add a `?tab=progress` panel to `/admin/fitness` (`AdminLive.FitnessManager`) to show them.
3. **Wiki biographies (D.10).** `/fitness/wiki/:slug` reads `session["admin_user"]` in `mount/3`. For the admin only, it shows "Your history" on the page: first and last entry, best e1RM, and the last five entries. Visitor HTML must not change, so add a test.
4. Tests cover the chart maths (ticks, empty data) and admin vs visitor on the wiki page.

#### Session 4 — Guardrail Check-Ins & Program Changelog (Deliverables E.11 & F.12)

1. Generate the migration with `mix ecto.gen.migration create_fitness_checkins`. It ships with `Web.Fitness.Checkin` and its context functions in **one commit**.
2. **`Web.Fitness.Guardrails`** (`lib/web/fitness/guardrails.ex`):
   - `state/2` takes a lift rule and a date and returns `{:green | :hold | :stop, reasons}`, as in §3.2.
   - `Progression.next_target` takes the guardrail state into account.
3. The check-in form goes in `/admin/fitness?tab=checkin`. In the log modal the guardrail shows as plain text, never as a checkbox.
4. **`Web.Fitness.Changelog`** (`lib/web/fitness/changelog.ex`) parses `content/fitness/changelog.md` per §3.2. Seed the file with `2026-10-26 — Get Sharp begins`.
5. Tests: each guardrail rule, changelog parsing (missing file → `[]`), and the visitor privacy test extended to the new state.

#### Session 5 — Regimen Revisions: Dual-Purpose Arms & KB Primer/Conditioning Split (Deliverables M, N, O)

1. Write the three proposals of §3.4 into `content/notes/fitness-proposals/`. Each one has the change as a diff of the module, the reasoning, and what it costs in time.
2. Check every slug in them exists. Do not touch `weekly/` or `modules/`.
3. Stop and ask the author. Apply only the proposals he approves, each with a changelog entry and a clean `ContentHealth` run.

#### Session 6 — Experiment Framing, Block Reports & Universal Visual Check-Ins (Deliverables C.9, G.13, H.14)

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

#### Session 7 — Homepage "Happening" Module (Deliverable I.15)

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

#### Session 8 — R / Quarto Pipeline & Stage 0 N-of-1 Models (Deliverables P & Q Stage 0)

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

### Addendum — Jiminy (2026-10-19)

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

---

## Custom Flatbed Scanner GUI: Architectural Blueprint & Specification

> **Status (2026-10-02).** This is the original design, kept for its reasoning. What was built
> differs: scans run through `Web.Scanner.Bed` (a GenServer holding a `scanimage` port), one
> strip placement per scan cut to a configured holder rectangle; strips are reordered with
> buttons, not drag and drop; the preview is a plain inversion, with no WebGL shader or rebate
> pipette; there is no bed-wide strip detection. `CLAUDE.md` describes the code as it is.

This document defines the architectural blueprint and technical specification for a **custom flatbed scanner GUI** specifically engineered for scanning film negatives and directly producing archives that conform to the hosting constraints and verification gates of **streetscissors**.

The application is designed to be accessible natively inside the `streetscissors` admin console at:
```
https://streetscissors.com/admin/scanner  (or http://localhost:4000/admin/scanner)
```

---

### 1. Problem Statement & Motivation

The current negative scanning workflow relies on a fragmented combination of separate tools:
1. A bash terminal wizard (`negatives`) to calculate roll names and create directories.
2. Epson's legacy Linux scanner software (`iscan` or `simple-scan`) to control the flatbed.
3. External file managers to inspect files.
4. Python scripts (`film-develop`) and headless GIMP Script-Fu (`digital-contact-sheet-maker`) to invert, analyze, and composite sheets.

#### Inefficiencies of the Legacy Approach
* **Inverted Blindness:** When previewing negatives in standard scanner software (`iscan`), the user sees an orange-tinted negative. Evaluating exposure, focus, and framing requires completing the scan, running terminal commands, and inspecting the final image.
* **Manual Strip Numbering:** Strips must be manually named in filename order (`001.tiff`, `002.tiff`) during the scanner's save dialog. Loading a strip backwards or numbering out of order corrupts the physical sequence on the contact sheet.
* **Separation from the Web Studio:** The scanning process is decoupled from the web application, even though the scanner is physically plugged into the exact same workstation that serves the site.

#### The Vision
An integrated **Darkroom Studio Console** mounted directly inside `streetscissors`'s authenticated admin area. It combines hardware scanner control, real-time positive previewing, computer-vision strip auto-detection, a virtual 8×10 contact sheet layout canvas, and zero-click web publishing.

---

### 2. System Architecture & Colocated Placement

Because the production Phoenix server runs on the physical host workstation where the flatbed scanner is connected via USB, the architecture takes advantage of direct local hardware access:

```
+-----------------------------------------------------------------------------------+
|                           ADMIN CLIENT (Desktop / iPad / Phone)                   |
|                                                                                   |
|  [ LiveView Studio Console: /admin/scanner ]                                      |
|  ├── Bed Preview & Rebate Pipette (HTML5 Canvas / WebGL Inversion Shader)        |
|  ├── Virtual 8x10 Contact Sheet Layout Canvas (Drag & Re-order Strips)            |
|  └── Roll Intake & Publishing Bar ([Scan Strips] [Assemble & Publish])           |
+------------------------------------------┬----------------------------------------+
                                           │ WebSocket (/live)
+------------------------------------------▼----------------------------------------+
|                          PHOENIX 1.8 / OTP SERVER (Host: Fedora)                  |
|                                                                                   |
|  WebWeb.AdminLive.Scanner (LiveView Module)                                       |
|    │                                                                              |
|    ▼                                                                              |
|  Web.Scanner.Driver (GenServer & Port Supervisor)                                 |
|    │                                                                              |
|    ├─► Elixir Port: stdin/stdout stream ──► [SANE scanimage / libsane C-Shim]     |
|    │                                                     │                        |
|    ├─► Port Worker: Python OpenCV / CV Engine            │                        |
|    │   (Auto-detects strip bounding boxes)               ▼                        |
|    │                                       [Epson Perfection V550/V600 (USB)]     |
|    ▼                                                                              |
|  Web.Scanner.Publisher (Workflow Orchestration)                                   |
|    ├── Writes raw strips: ~/Pictures/Negatives/<Format>/rollNNN_DATE.../          |
|    ├── Executes film-develop analyze -> frames.json                               |
|    ├── Executes digital-contact-sheet-maker -> Contact Sheets/rollNNN.png         |
|    ├── Verifies Gate 1 (frames.json sync) & Gate 2 (PNG IHDR dimensions)          |
|    ├── Generates 2000px WebP Preview via ImageMagick                              |
|    └── Appends roll record to catalog.csv                                         |
+------------------------------------------┬----------------------------------------+
                                           │ Request-time Filesystem Mount
+------------------------------------------▼----------------------------------------+
|                          PUBLIC APPLICATION (streetscissors.com)                  |
|                                                                                   |
|  WebWeb.NegativesLive -> Roll instantly live at /negatives/roll/NNN                |
+-----------------------------------------------------------------------------------+
```

---

### 3. Hardware & Driver Interface (SANE Layer)

The flatbed scanner communicates through the **Scanner Access Now Easy (SANE)** API via `libsane` and the `scanimage` utility.

#### Scanner Parameters for Film Negatives
To scan negatives on modern flatbeds (e.g. Epson Perfection V550, V600, V850):
* **Transparency Unit (TPU):** The standard reflective white lid is detached or covered, and the top backlight lamp is activated.
  ```bash
  scanimage -d "epson2:libusb:001:004" --source "TPU8x10" ...
  ```
  *(or `--source "Film"` depending on backend revision)*.
* **Scan Modes & Bit Depth:**
  * **Preview Mode:** 8-bit RGB at $75\text{ DPI}$ or $100\text{ DPI}$ for rapid bed scanning ($< 10\text{ seconds}$).
  * **Contact Strip Mode:** 16-bit linear raw RGB (or 8-bit RGB) at **strictly 300 DPI**.
  * **Single Frame Keeper Mode:** 16-bit TIFF at $2400\text{ DPI}$ or $3200\text{ DPI}$ optical resolution.
* **Scan Geometry Constraints:**
  SANE coordinates define the active bed window in millimeters:
  `-l` (left-x), `-t` (top-y), `-x` (width), `-y` (height).

#### The Elixir Port Driver (`Web.Scanner.Driver`)
LiveView processes must never block the Erlang VM's schedulers during a physical hardware scan that takes 30–60 seconds. The hardware is wrapped in an Elixir GenServer managing a child Port process:

```elixir
defmodule Web.Scanner.Driver do
  use GenServer
  require Logger

  @doc "Triggers a non-blocking preview scan of the flatbed."
  def preview_bed(caller_pid) do
    GenServer.cast(__MODULE__, {:start_preview, caller_pid})
  end

  @doc "Triggers a high-resolution strip scan for specified bounding boxes."
  def scan_strips(boxes, roll_meta, caller_pid) do
    GenServer.cast(__MODULE__, {:scan_strips, boxes, roll_meta, caller_pid})
  end

  # Callbacks execute inside supervised OTP GenServer, streaming chunks via send/2
end
```

---

### 4. Real-Time Inversion & Debayering Shader

In standard tools, the photographer stares at orange or dark inverted negatives on screen. The Custom Scanner GUI introduces a **Real-Time Positive Canvas Engine**:

```
[Raw Scanner Bed Frame] (Orange C-41 / Milky B&W)
            │
            ▼
[Pipette Tool / Auto-Rebate] ──► Samples unexposed film border: (D_R, D_G, D_B)
            │
            ▼
[WebGL Fragment Shader / Canvas 2D Pipeline]
  1. Subtract Orange Mask:
     I_norm(c) = (I_raw(c) - D_base(c)) / (I_white(c) - D_base(c))
  2. Invert:
     I_pos(c) = 1.0 - I_norm(c)
  3. Gamma Balance:
     I_final(c) = pow(I_pos(c), gamma_c)
            │
            ▼
[Real-Time 60 FPS Positive Preview on Canvas]
(User sees the true finished photograph before committing to final scan)
```

#### The Inversion Shader (GLSL Fragment Shader)
```glsl
precision mediump float;
varying vec2 v_texCoord;
uniform sampler2D u_image;
uniform vec3 u_rebateDensity; // Sampled from orange border
uniform vec3 u_channelGammas; // Dynamic gamma adjustments
uniform float u_exposure;
uniform float u_contrast;

void main() {
    vec4 raw = texture2D(u_image, v_texCoord);
    
    // 1. Subtract film base rebate mask
    vec3 normalized = clamp((raw.rgb - u_rebateDensity) / (vec3(1.0) - u_rebateDensity), 0.0, 1.0);
    
    // 2. Invert negative to positive
    vec3 positive = vec3(1.0) - normalized;
    
    // 3. Apply channel-specific gamma correction to eliminate color cast
    vec3 balanced = pow(positive, u_channelGammas);
    
    // 4. Exposure & contrast curve adjustments
    vec3 exposed = balanced * u_exposure;
    vec3 contrasted = (exposed - 0.5) * u_contrast + 0.5;
    
    gl_FragColor = vec4(clamp(contrasted, 0.0, 1.0), 1.0);
}
```

---

### 5. Virtual 8×10 Contact Sheet Canvas & Strip Reordering

The core interface of the GUI reflects the physical paper constraints of `streetscissors`:

#### Virtual Canvas Specifications
* **Aspect Ratio:** Strictly locked to an 8×10 inch portrait sheet ($2400 \times 3000\text{ px}$ at 300 DPI, aspect ratio $0.80$).
* **Canvas Background:** Pure Black (`#000000`), emulating unexposed photographic contact paper.
* **Layout Grid Rules:**
  * **120 / 620 Film:** 4 vertical columns with `@margin 75px` ($0.25\text{ in}$) and `@gap 24px` ($2\text{ mm}$).
  * **35mm Film:** 6 horizontal rows with `@margin 75px` and `@gap 24px`.

#### Strip Reordering Interaction
When film strips are placed on the glass bed:
* A photographer may accidentally place Strip 2 on the left of Strip 1, or lay a strip backwards.
* The Virtual Canvas allows the user to **click and drag strips** into the correct chronological order, and click a **Flip $180^\circ$** toggle.
* When the user clicks "Assemble Roll", the GUI writes the files with corrected numbering:
  * Slot 1 on canvas $\rightarrow$ `001.tiff`
  * Slot 2 on canvas $\rightarrow$ `002.tiff`
  * Slot 3 on canvas $\rightarrow$ `003.tiff`
  * Slot 4 on canvas $\rightarrow$ `004.tiff`
This guarantees that alphabetical order strictly matches visual layout, fulfilling the fundamental assumption of `Web.Negatives.SheetLayout`.

---

### 6. Site-Conformance Engine & Automated Verification

Before a newly scanned roll is finalized, the GUI runs the **Site-Conformance Pipeline**:

```
+-----------------------------------------------------------------------+
|                    SITE CONFORMANCE VALIDATION                        |
|                                                                       |
|  [Step 1] File Structure Check:                                       |
|           • Format directory exists (e.g. 120 Film/)                  |
|           • Roll folder named: rollNNN_YYYY-MM-DD_FORMAT_COLOR        |
|           • Strip scans named 001.tiff..N.tiff (all > 0 bytes)        |
|                                                                       |
|  [Step 2] Metadata & Analysis Generation:                             |
|           • film-develop analyze executed                             |
|           • frames.json written with frame regions & quality scores   |
|                                                                       |
|  [Step 3] Contact Sheet Composition:                                  |
|           • GIMP Script-Fu renders Contact Sheets/rollNNN.png         |
|           • Black background (#000000) verified                       |
|                                                                       |
|  [Step 4] LiveView Gate Pre-Flight Tests:                             |
|           • Gate 1: Web.Negatives.Sheet.verify_gate_1(roll_dir) == :ok|
|           • Gate 2: Web.Negatives.Sheet.verify_gate_2(png_path) == :ok|
|                                                                       |
|  [Step 5] Downscaled Preview Generation:                              |
|           • ImageMagick converts PNG -> Contact Sheets/previews/*.webp|
|           • Max 2000px, 82 quality                                    |
|                                                                       |
|  [Step 6] Master Catalogue Update:                                    |
|           • Row appended to catalog.csv:                              |
|             rollNNN,2026-10-02,120,bw,12,120 Film/rollNNN_...         |
+-----------------------------------------------------------------------+
```

If either Gate 1 or Gate 2 fails during pre-flight, the GUI halts, displays an explanatory diagnostic in the admin interface, and prevents publishing until corrected.

---

### 7. Single-Frame Keeper Rescan Mode

After the contact sheet is assembled and displayed in the GUI:
1. **Interactive Stickering:**
   - The user clicks on any frame on the virtual contact sheet.
   - The GUI applies a procedural red wax china-marker circle (identical to `Web.Negatives.GreasePencil`).
   - This records the frame into the roll's selects list.
2. **High-Resolution Optical Rescan:**
   - The user selects a stickered frame and clicks `[Rescan Keeper Frame]`.
   - The GUI prompts the user to place the negative into the scanner's single-frame high-resolution holder.
   - The scanner runs at **2400 DPI** or **3200 DPI** with 16-bit depth.
   - The image is developed using the strip's quality-weighted parameters (blending 70% strip profile / 30% individual frame reading).
   - Saved directly as `<frame_number>.tiff` (e.g. `3.tiff`) inside the roll's folder.
3. **Instant Web Availability:**
   - `streetscissors` detects `<frame_number>.tiff` at request time.
   - The individual frame page [`/negatives/roll/NNN/frame/<N>`](https://streetscissors.com/negatives) becomes immediately functional with high-resolution zooming and metadata.

---

### 8. Implementation Roadmap

The custom scanner GUI can be rolled out in four progressive milestones:

#### Phase 1: The SANE & Driver Bridge
* Implement `Web.Scanner.Driver` GenServer supervising an asynchronous port to `scanimage`.
* Support USB device detection and Transparency Unit (TPU) mode switching.
* Implement flatbed low-DPI preview capture streaming into LiveView.

#### Phase 2: LiveView Studio Console (`/admin/scanner`)
* Build the `/admin/scanner` LiveView template under `WebWeb.AdminLive.Scanner`.
* Add the **"Darkroom"** section and navigation link in `WebWeb.AdminNav`.
* Embed the HTML5 Canvas / WebGL real-time inversion shader with the interactive rebate pipette.

#### Phase 3: The Virtual Contact Canvas & Strip Segmentation
* Implement the interactive 8×10 virtual contact sheet canvas.
* Implement drag-and-drop strip sequencing and orientation toggles.
* Connect strip cropping coordinates directly to 300 DPI scan passes.

#### Phase 4: Automated Assembly & Conformance Gatekeeper
* Integrate automated execution of `film-develop analyze` and GIMP Script-Fu compositing.
* Integrate pre-flight execution of `Web.Negatives.Sheet` Gate 1 and Gate 2.
* Wire the keeper rescan helper to save `<frame_number>.tiff` directly into the roll folder.
