# Working on this site: instructions for another agent

Written 2026-10-11 for an agent that has never seen this repository (Gemini Flash in Google
Antigravity). Read all of it before you run anything. It is short on purpose. When this
document and your own judgement disagree, follow this document and say so in your report.

The exercise figures have their own guide: [`figures-handoff.md`](figures-handoff.md). Do
not start it unless the owner asks for figure work. It is the one job done in the owner's
folder and not in your copy, because the pose files are not in git.

## 1. What this is

A personal website: writing, spoken logs, film photographs, a training plan, a prayer page.
Phoenix 1.8 and LiveView 1.1 (Elixir), SQLite, hand-written CSS. One author, one machine.

**The machine you are on is the live web server.** The folder `~/streetscissors` is what gets
deployed, by the owner, whenever he likes. Anything half-finished in that folder can go live.
That is why rule 1 exists.

## 2. Rules. Breaking one of these is worse than not finishing

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

## 3. Setting up your copy (once)

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

## 4. Finding your way

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

How to find the code behind something you see on a page: search for its words.

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

## 5. The loop for every task

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

## 6. The tasks, in order

These come from a first-time visitor's review of the site on 2026-10-11. Each was checked
against the code. Where the review was wrong, the task says so. **Do not do anything from
the review that is not in this list.**

### A. Plain bugs (do these first)

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

### B. Finding your way round the site

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

### C. Do not do these. The review was wrong, or the choice is the owner's

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

## 7. When you stop

Finish `tmp/gemini-report.md` with: the tasks done (one line each with its commit), the tasks
skipped and why, everything under "for the owner", the last three lines of `mix test`, and
anything in this document that was wrong. Then stop. Do not merge, push or deploy.
