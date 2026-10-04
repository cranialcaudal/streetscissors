# How this is made

A manual for the streetscissors website and the darkroom pipeline behind it.

This page is written for two people. One of them has never programmed and wants to know what this site is and how a photograph gets from a strip of developed film onto the internet. The other has just started programming and wants to know how the website itself is built. Neither is assumed to know anything in advance. Every unfamiliar word is explained the first time it appears, and again in the glossary at the end.

Read it in order or jump to the part you need. Nothing here depends on having read what came before it.

---

## Part 1: What this is for

If you use social media, you already know how to use this site.

A feed gives you four things: a place to put photographs, a place to put words, a way for people to find them, and a way to know they were seen. This site does all four. The photographs live under `/negatives`. The written words live under `/blog`, and the spoken ones under `/logs`. One set of keywords finds things everywhere, and every piece carries its count of witnesses. If all you want is to look at the work, that is the whole manual; the rest of this page is for people who want to know how the thing is built, and for people who want to build one like it.

The difference between this and a feed is not what it does. It is what it refuses to do, and the refusal is the entire point. The first post on this site argued it directly: social media stays in business by fragmenting you. It asks for the profile, the story, the reel, the thread; one person cut into formats, each owned by somebody else, each training you to watch yourself the way the platform watches you. To see an image in parts, the post said, is to never see it at all.

This site is that argument, built:

**One person, whole, in one place.** The essays, the photographs, the training log, the recordings: they live together and they link to each other. A frame links back to the contact sheet it was cut from. A keyword finds the essay and the recording alike. Nothing here is sliced into a format.

**Owned, not rented.** It runs on a computer in a house, not in a data centre. There is no account to be suspended and no terms that can change under you. The automated scrapers that feed the large models are refused at the door. The software is free for anyone to take; the work on it belongs to its maker.

**Shown, not fed.** The indexes sort by most recent or most witnessed, and you choose which. No feed decides what you see next, and no metric tells the writer what to make more of. The guestbook takes signed messages, not likes.

**Answered, not commented.** A feed is also how people keep up with each other and reply, so the site does that too, on its own terms:

- **Every day is a page.** Under `/almanac`, a day with work in it holds everything made that day side by side. A year is laid out like a contact sheet, and it prints as a clean edition.
- **You can follow a keyword.** The feed at `/feed` carries everything, and `/feed?keyword=film` follows one thread across the blog and the logs. You follow a thought rather than an account.
- **You can write a letter.** Under any post, log or photograph, you can write to the author about that piece. It is private unless you allow it to be published and the author chooses to publish it.
- **Other sites can cite a piece.** A site that links to a piece can say so by webmention. Once the link is checked and approved, it appears beneath the piece as "Cited by": a conversation between two homes, with no platform in the middle. It runs the other way too: when a post here links to another site, that site is told, so it can show the citation on its side.

"Owned, not rented" deserves a concrete picture, because that is where the philosophy becomes plumbing. Here is what happens when you open this site, in plain terms.

Your browser asks the internet where `streetscissors.com` lives. That name is rented from a registrar, the way a phone number is rented from a carrier; it points at an address and does nothing else. At that address sits a computer in a house. A small program called Caddy answers the door: it proves the site is who it claims to be (that is what the padlock in your browser means) and scrambles the conversation so nobody between you and the house can read it. Caddy passes the request to the site itself, which reads the folders on that computer's disk and builds the page you see.

Sovereignty, in this context, is not a metaphor. It is the list of things no one else controls: the files are on a disk in the house; the program that serves them is free software running on that same machine; the machine answers to its owner and to nobody's terms of service. A social feed inverts every one of those: your words sit on their disks, served by their programs, under their rules, and the account is yours only until it isn't.

The arrangement rests on one stubborn technical idea:

> **The thing on disk is the thing on the site.**

Most websites keep a copy of your work inside a database, behind a login, in a format only that website can read. If the website disappears, so does the work. This one is arranged the other way round. The essays are ordinary text files in a folder. The photographs are ordinary image files in a folder. The website reads those folders directly, every time somebody visits, and shows whatever it finds there.

That has three consequences that shape everything else in this manual.

**There is no "publish" button for most of it.** Save the file, and it is live. Rename the file, and the address changes. Delete the file, and the page is gone. No upload form stands between the work and the reader.

**The archive outlives the website.** The folder of negatives is a folder of negatives. It can be copied to a drive, opened on any computer, and read in thirty years by software nobody has written yet. The website is a way of looking at that folder, not the place the folder lives.

**Backups are of files, not of a service.** Everything that matters can be carried away on a disk.

The rest of this manual is how that idea is actually implemented; first for photographs, then for words, then the machinery underneath both. Part 7 shows how to run a copy of the whole thing yourself.

---

## Part 2: The map

The site is divided into sections. Here is what each one is and where its
contents come from.

| Address | What it holds | Where the content lives |
|---|---|---|
| `/` | The front door | Hand-built page |
| `/blog` | Written work | Text files in `content/blog/` |
| `/logs` | Captain's logs; spoken pieces | Database, plus audio files on disk |
| `/negatives` | Contact sheets and single frames from film | The photo archive folder |
| `/fitness` | The training regimen and bike rides | Text files, plus rides pulled from Komoot |
| `/pc` | A pretend 1980s terminal that navigates the site | Built live from all of the above |
| `/guestbook` | Messages from visitors | Database |
| `/newsletter` | Sign-up for the mailing list | Database |
| `/about` | Who made this | A text file |
| `/how-to` | This page | `docs/how-to.md` |
| `/admin` | The private side, behind a password | All of the above, edited in one place |

Three of those deserve a note.

**`/blog` and `/logs` are siblings, not parent and child.** The blog is written
work; the logs are spoken work. They are separate systems that happen to share
one vocabulary; see *Keywords* in Part 4. Both can be sorted by **most recent**
or by **most witnessed**, which means most read or most listened to.

**`/pc` is a joke that tells the truth.** It looks like an old DOS prompt. Type
`roll007` and press Enter and it takes you to that roll of film. It works
because it asks the same questions the ordinary pages ask; *what rolls exist,
what posts exist, what recordings exist*; and answers with the real filenames
things have on disk. It is the clearest demonstration of the idea in Part 1: if
you know what the file is called, you can find it.

**`/admin` is the back office.** It opens on an overview that lists only what is
waiting for you (a guestbook signature to approve, a message in the inbox, a
recording that failed to convert) with each item a link to the page where it
gets done, and beside it the state of the machine: when the database and the
writing were last copied, whether the backup drive is plugged in, when Komoot
was last checked, how long the certificate has left, whether the domain still
points at the house. The machine makes those checks itself every fifteen
minutes, and writes to its owner when one of them fails.
The pages are grouped by the kind of work: **Write** (the blog, the captain's
logs, the fitness wiki), **Mail** (the inbox, the guestbook, the newsletter) and
**Sync** (the Komoot activities), plus a page of settings. The admin writes the
same files you would write by hand, so nothing it does is locked inside it.

---

## Part 3: Film, from negative to page

How a roll of exposed film becomes a page on the internet. This is the longest
part, because it has the most steps that happen away from a keyboard. If you are
a photographer and read only one section, read this one.

### What a contact sheet is

Before digital cameras, you could not see a negative properly by holding it up
to a lamp. So you laid the whole roll; cut into strips; onto a sheet of
photographic paper, pressed a piece of glass on top, and exposed it all at once.
The result was one print showing every frame on the roll at its true size. That
is a **contact sheet**. You looked at it with a loupe, marked the good ones with
a grease pencil, and only then made a real print.

This site reproduces that object digitally. Every roll gets one contact sheet:
a single image, 300 dots per inch, about 8 by 10 inches, black background,
showing every frame on the roll. That sheet is the unit the site publishes.
Individual frames come later, and only for the ones worth it.

### The tools

Three programs do the work. They live in `~/.local/bin` on the machine, which
means you can type their names from anywhere.

| Command | What it is |
|---|---|
| `negatives` | The wizard. Walks you through scanning one roll, start to finish. Also spelled `film-intake`; same program. |
| `digital-contact-sheet-maker` | Builds one contact sheet from a folder of scans. The wizard calls this for you; you can also call it yourself. |
| `film-develop` | The image mathematics; inverting negatives, correcting colour, finding where one frame ends and the next begins. You rarely run this directly. |

`digital-contact-sheet-maker` drives **GIMP**, the free image editor, without
ever opening its window. GIMP does the actual laying-out; the script tells it
what to do and closes it again.

### The steps

**1. Shoot the roll.** 120, 620, 110 or 35mm. The format matters later, because
it decides how the strips are arranged on the sheet.

**2. Develop it.** In a tank at home or at a lab. This manual starts where the
dry negatives do.

**3. Cut the roll into strips** and start the wizard:

```
negatives
```

It asks four questions: the roll number (it suggests the next free one and
refuses one already used), the film format, black-and-white or colour, and the
date. From those it builds a folder with a name that carries all of it:

```
~/Pictures/Negatives/120 Film/roll007_2026-07-22_120_bw/
```

**4. Scan the strips.** The wizard opens your file manager at that folder and
launches the scanner program *from inside it*, so when you press Scan the save
dialog is already pointing at the right place. Scan at **300 dpi**, one file per
strip, numbered in order:

```
001.tiff   002.tiff   003.tiff   004.tiff
```

The numbering is what decides the order on the sheet, so number them the way you
want them read.

**5. Close the scanner.** That is the signal. The wizard notices, writes a row
into the archive's catalogue, and builds the contact sheet.

**6. There is no step six.** The sheet is on the website. Not "after a deploy",
not "after an upload"; the website reads that folder directly, so the next
person to load `/negatives` sees it. This is the payoff of Part 1.

### What happens inside step 5

Worth knowing, because it is the part that took the longest to get right.

A scan of a negative is not simply an upside-down photograph. Three problems
have to be solved before it looks like anything.

**The scanner bed is in the picture.** Around and between the strips is bright
white scanner glass, and in the gaps of the film holder, pure black. Those pin
the brightest and darkest values in the image to their extremes, which means any
automatic "fix the levels" tool; including GIMP's own; measures those instead
of the film and does nothing at all. So the first thing the software does is
*mask out everything that is not film*, and only then measure. This is the step
everything else depends on.

**Colour negatives are orange.** C-41 colour film has an orange base built into
it. Invert an orange-based negative naively and the whole thing comes out blue.
Stretching each colour channel to its proper endpoints helps but does not fix
it, because the orange mask is not just a brightness offset; each channel
responds differently. What actually removes the cast is pulling the three
mid-tones back to a common average afterwards.

**Black-and-white negatives are flat.** They use only part of the available
range, so a plain inversion looks milky. The correction uses one range shared
across all three channels; measuring each channel separately would tint a
picture that is supposed to be grey; and averages to true neutral at the end.

All of this is measured **per strip, not per roll**. One dark strip should not
be allowed to drag down the exposure of every other strip on the sheet.

Then GIMP lays the strips out. 120 and 620 strips stand side by side as columns;
35mm strips stack as rows; anything else is left alone for hand assembly. The
result is written to:

```
~/Pictures/Negatives/Contact Sheets/roll007_2026-07-22_120_bw.png
```

### Choosing the keepers

A contact sheet exists to be marked up. The digital version keeps that ritual.

```
negatives --analyze 7          look at every frame and score its exposure
negatives --selects 7          show which frames are currently picked
negatives --select 7 2,5,9     pick frames 2, 5 and 9
negatives --unselect 7 5       change your mind about 5
negatives --scan-frames 7      rescan the picked frames properly, one at a time
negatives --redevelop 7        redo the corrections on frames already scanned
```

`--analyze` measures each frame's exposure and flags the ones that are thin or
blown. It is a second opinion, not a verdict; a correctly exposed night
photograph is supposed to be dark, and the scoring is deliberately built not to
punish that.

`--scan-frames` walks you through the picked frames one at a time, showing you
each so you load the right negative, and scans it at whatever resolution you
choose. Those higher-resolution scans land in a `frames/` subfolder inside the
roll.

### Publishing a single frame

To give one photograph its own page, put a scan of it in the roll's folder,
named with its frame number:

```
3.tiff
```

That is the entire procedure. The site looks in the roll's folder for files
whose names end in a number, and any it finds appear in the strip beneath the
contact sheet and get their own address:

```
/negatives/roll/7/frame/3
```

The frame page always links back to the sheet it was cut from; a photograph
should be able to show where it came from.

### Putting a photograph in a piece of writing

Inside any blog post you can write:

```
![[roll012]]              the whole contact sheet
![[roll012/3]]            frame 3 of roll 12
![[roll012/3|Low tide]]   the same, with a caption
```

If the roll or the frame does not exist, the text is simply left as it is. A
post never renders a broken image.

### Fixing and undoing

| Command | What it does |
|---|---|
| `negatives --list` | Which roll numbers are taken, what each holds, next free number |
| `negatives --add 7` | Reopen the scanner into roll 7's folder to scan strips you missed |
| `negatives --recompile 7` | Rebuild roll 7's sheet from the scans already there, no scanner needed |
| `negatives --redo 7` | Retire roll 7 and scan it again into the same number |
| `negatives --delete 7` | Retire roll 7 and free the number |
| `digital-contact-sheet-maker <folder>` | Build a sheet from any folder of scans |

A roll number lives in four places; the scan folder, the catalogue row, the
contact sheet, and the sheet's web-sized copy. `--delete` clears all four, which
is why deleting the folder by hand is not enough: the number stays reserved and
the sheet stays on the website.

Retired rolls go to a hidden `.trash` folder inside the archive rather than
being destroyed.

### The archive on disk

```
~/Pictures/Negatives/
├── 120 Film/          one folder per roll
├── 620 Film/
├── 110 Film/
├── 35mm Film/
├── Other/
├── Contact Sheets/    the finished sheets, one PNG per roll
│   └── previews/      web-sized copies, made automatically
├── catalog.csv        roll, date, format, colour, frame count, folder
└── .trash/            retired rolls
```

`catalog.csv` is a plain spreadsheet file. It is the only piece of metadata the
website trusts beyond the folder names themselves, and you can open it in
anything.

The `previews/` folder is not yours to manage. The first time somebody asks for
a sheet, the site makes a smaller web-friendly copy of it and keeps it. If you
rebuild the sheet, the copy is remade automatically, because the site compares
the two files' timestamps. Never delete a preview by hand to force a refresh;
just rebuild the sheet.

### How the coordinates reach the page

When you open `/negatives/roll/012` on the site, each printed photograph is encircled by a red wax mark, and hovering over it shows its frame number. Clicking it opens the photograph.

Nothing in the contact sheet PNG itself says where frame 7 is. The software that built the sheet knows, though, and Elixir replays its rules at request time:

1. **The strip-level rectangles:** Running `negatives --analyze` segments each raw strip scan into individual frame rectangles and writes their dimensions to `frames.json`.
2. **Replaying the Script-Fu math (`Web.Negatives.SheetLayout`):** The Scheme script (`film-contact-sheet.scm`) that laid out the sheet in GIMP obeyed exact geometric rules: a 75-pixel margin (0.25 inch at 300 DPI), a 24-pixel gap (2 mm) between strips, and a fixed 90° or 270° strip rotation depending on the film format. Elixir re-runs those exact formulas without ever launching GIMP, translating each strip's coordinates into responsive CSS percentages (`--x`, `--y`, `--w`, `--h`).
3. **The two safety gates:** Misplacing a mark—so that clicking one photo opens another—is worse than showing no mark at all. So before drawing anything, `Web.Negatives.Sheet` verifies two things:
   - **Gate 1:** The strip files currently on disk must match `frames.json`'s list in exact alphabetical order. If someone added or rescanned a strip without re-running the analysis, the gate closes and no marks are drawn.
   - **Gate 2:** The code reads the first 24 bytes of the contact sheet PNG to get its physical width and height from the image header. It tests every paper size at 300 DPI (8×10, A4, Letter). If the composed dimensions do not match the real image to the exact pixel, the gate closes.

If both gates pass, the click targets and grease-pencil rings appear in their true physical positions.

### How the wax circles are drawn

On a physical contact sheet, keepers are marked with a red grease pencil (a china marker)—a waxy stick that skips over the photographic gloss, wobbles with the photographer's hand, and loops wide around the frame.

A sterile computer-drawn ellipse would break the feeling of a real darkroom proof sheet. `Web.Negatives.GreasePencil` generates organic wax marks dynamically as pure SVG vectors:

1. **Deterministic seeding:** The circle is seeded by `:erlang.phash2({roll, frame})`. Frame 3 of roll 12 gets the same unique mark on every device and after every server restart, but no two frames on the site ever share the same circle.
2. **Sine harmonics:** The radius of the circle is perturbed by three low-frequency sine waves (frequencies 2, 3, and 5) with randomized phases, producing a steady-handed organic wobble instead of jagged noise.
3. **Catmull-Rom splines:** The perturbed coordinates are smoothed into continuous cubic Bézier curves.
4. **Double wax stroke & gloss skip:** The ring is drawn in two passes—a heavier outer line and a lighter inner stroke where the pencil looped back around. Both strokes use SVG dash patterns normalized to a 100-unit path length to recreate the waxy skip on paper gloss, drawn with `vector-effect: non-scaling-stroke` so the line weight remains an authentic 2 mm pencil stroke regardless of screen zoom.

### Scanning from the admin

Scanning a roll used to mean switching between the terminal wizard (`negatives`), the file manager and Epson's `iscan`. The admin's **Scanner** page (`/admin/scanner`) does the same job from the browser, because the server is the machine the scanner is plugged into:

1. **Name the roll** — number, scan date, format, film. The page shows the folder it will fill and offers the lowest free roll number.
2. **Scan the strips, one at a time.** Lay a strip in the film holder and press *Scan strip*. The scanner is driven through its transparency unit as negative film, at 300 dpi, cut to the holder slot for that format. The page stays usable while it scans and shows the progress. Strips scanned elsewhere can be dropped in instead; they are kept exactly as they were.
3. **Put them in order.** Move a strip earlier or later, or turn it 180°. The order of the files is the order of the sheet.
4. **Analyse and assemble.** These run `film-develop` and `digital-contact-sheet-maker` — the same tools `negatives` uses — so the roll is identical to one made in the terminal. If either fails, the page says what it said; it never makes up a result.
5. **Publish**, once both gates pass: the strip files match `frames.json`, and the sheet is exactly the size those strips compose to. That adds the roll to `catalog.csv`, and it is on `/negatives`.
6. **Rescan the keepers.** Put a frame's strip back in the holder and it is scanned at 2400 dpi and developed into `frames/`, which is what gives a frame its own page and its grease-pencil ring.

With no scanner connected the page says so and scans nothing. The slot rectangles for the film holder are set once, in `.env` (`SCANNER_AREA_35MM`, `SCANNER_AREA_120`); the page's **Setup** tab shows what is set and which scanner is in use.

For complete technical specifications, mathematical equations, and driver designs, see `docs/negatives-pipeline.md` and `docs/scanner-gui-blueprint.md` in the repository.

---

## Part 4: Words, from file to page

How a piece of writing, a recording or a training note gets published.

### Writing a post

Blog posts are text files in `content/blog/`, written in **Markdown**; plain
text with a few marks in it, where `# ` starts a heading and `*stars*` make
italics. The folder is an [Obsidian](https://obsidian.md) vault, so it can be
edited in Obsidian, or in any text editor at all, because Markdown files are
just text.

At the top of each file goes a small block of information called
**frontmatter**:

```
---
title: "The Ferry at Bowling Green"
description: "A short line that shows on the index page."
date: "2026-07-15"
keywords: film, new-york, ferry
---
```

Then the piece itself.

**The filename becomes the address.** A file called `ferry-at-bowling-green.md`
is published at `/blog/ferry-at-bowling-green`. Rename the file and you rename
the page, so it is worth getting the name right the first time.

Anything you leave out is worked out for you: no title, and it is made from the
filename; no date, and the file's own modification time is used; no description,
and the first real paragraph is borrowed.

**Save the file and it is live.** The site reads the folder fresh on every
visit, so there is nothing to rebuild.

**Unless it says it is a draft.** Add `draft: true` to the frontmatter and the
file stays in the folder and off the site: no index lists it, no feed carries
it, and its address answers as though nothing were there. Take the line out and
it is published. Logged in, you can still open a draft at its own address, to
see it as it will look.

**The admin can edit the same file.** `/admin/blog` lists every post, and each
one opens in an editor that shows the whole file on the left, frontmatter and
all, and the page it makes on the right. It is the same file Obsidian edits, so
the editor checks before it saves: if the file changed on disk after the page
loaded it (because you saved it in Obsidian in the meantime), the save is
refused and you choose which version to keep. The one you do not keep goes to
the vault's `.trash` folder rather than being thrown away.

### Keywords

`keywords:` in the frontmatter is what powers the filter buttons on `/blog`.
They are put through one shared tidying step, so `New York`, `new-york` and
`NEW YORK ` all become the same tag. The same tidying makes the addresses of
pages, which is why a post called "The Ferry at Bowling Green" lives at
`the-ferry-at-bowling-green`.

The logs use the same vocabulary from a different place; their keywords are
typed into the admin form rather than into a file; so a keyword filters writing
and recordings alike.

`/admin/keywords` shows the whole vocabulary at once, with everything filed
under each word. A keyword renamed there is rewritten in every file and every
recording that carries it, and renaming one to a word already in use merges the
two; which is how `nyc` and `new-york` become one place again.

### Checking the work

`/admin/health` reads everything the way the site does and lists what does not
hold together: a link to a page that was renamed, a photograph embed naming a
roll that is not there, a published post with no description, an uploaded image
that no page uses. Each link is checked by asking the site itself for that
address, so the report cannot disagree with what a visitor would get. It changes
nothing; it says what is wrong and where to fix it.

### Recording a log

Captain's logs are the spoken half, as video or audio. Unlike the blog, they do
live in the database, because a recording needs details a filename cannot carry.

1. Go to `/admin/logs`, the recording booth.
2. Choose video or audio, switch the camera or microphone on, and record. Or
   drop a file you already have onto the screen.
3. Trim the start and the end, and pick the frame that stands for the
   recording (its poster).
4. Add a caption, keywords and notes if you like, then **Publish** or **Save as
   draft**.

The trim and the poster are only numbers. The server applies them when it
converts the recording into a single file every browser can play, so nothing is
re-encoded in your browser. The original is deleted once that conversion
succeeds, which makes the trim a one-time decision; the caption, keywords, date
and poster stay editable.

A log is titled by the day it was recorded, and that date is its address:
`/logs/2026-09-18`. A second recording on the same day becomes `2026-09-18-2`.

### The training log

`/fitness` works like the blog: Markdown files, this time in `content/fitness/`,
one per day of the week plus reusable blocks. The public page deliberately shows
only the headings and the checklist items; the notes about where and when and
why stay in the file and never reach the page.

Bike rides arrive on their own. Once an hour the site logs in to Komoot, asks
for anything new, and imports it. A ride made private on Komoot disappears from
the site on the next pass. If Komoot is not set up, nothing happens and nothing
breaks; you can also drop a GPX file in by hand.

### The newsletter

People sign up through the overlay on any page, past a hand-made puzzle rather
than a Google one, limited to three attempts an hour from any one address. They
get a welcome letter immediately. Every letter carries a real unsubscribe link
and the header that lets a mail program offer a one-click unsubscribe.

Unsubscribing never deletes anybody. It marks them inactive, so re-adding the
same address cannot start mailing them again by accident.

---

## Part 5: The machine

This part is for the beginner programmer. If you only want to run the site,
skip to Part 6.

### The words, in plain language

**Elixir** is the programming language the site is written in. **Phoenix** is
the toolkit that turns Elixir into a website. **LiveView** is the part of
Phoenix that lets a page update itself without you writing any browser
JavaScript; the page stays connected to the server, and when something changes,
the server sends just the changed piece. **SQLite** is the database: not a
server you install and manage, but a single file on disk you can copy.

Nothing here runs in the cloud. There is no Amazon, no Vercel, no managed
anything.

### What happens when somebody visits

1. A request arrives at **Caddy**, a small web server that owns ports 80 and
   443. It handles the encryption certificate and passes the request inward.
2. Caddy hands it to the Phoenix application listening on port 4000.
3. Phoenix runs it through a short chain of steps: record the visit, work out
   whether this is an administrator, load the site's settings.
4. The **router** matches the address against its list and picks the code to run.
5. That code reads whatever it needs; files from disk, rows from the database;
   and renders the page.
6. The HTML goes back out the way it came.

Steps 1 to 6 happen for every visitor, every time. There is no cache in front of
it and no build step behind it.

### Which content is a file and which is a row

This is the single most useful thing to know about the codebase.

| Content | Where it lives | Added by |
|---|---|---|
| Blog posts | Files, `content/blog/` | Saving a file |
| Training regimen | Files, `content/fitness/` | Saving a file |
| Contact sheets and frames | Files, the photo archive | Scanning a roll |
| This manual | A file, `docs/how-to.md` | Saving a file |
| Captain's logs | Database + media files | The admin's recording booth |
| Bike rides | Database | The hourly Komoot sync |
| Guestbook, subscribers, visit counts | Database | Visitors |

Everything in the top group is read from disk at the moment of the request.
Everything in the bottom group is in one SQLite file.

### Where things are in the repository

```
streetscissors/
├── lib/web/            the thinking: content, photos, rides, mail, backups
├── lib/web_web/        the web layer: router, pages, live pages, layouts
├── assets/css/         the design, hand written
├── assets/js/          the small amount of browser code
├── content/            the Obsidian vault: writing and training notes
├── docs/               this manual
├── priv/repo/          database migrations
├── test/               the tests
├── config/             settings for development, test and production
└── redeploy.sh         the deploy script
```

The convention: `lib/web/` is the part that would still make sense if the
website were replaced by something else, and `lib/web_web/` is the website
itself.

### The design

The look is called **UC Press / Valley print**. Frederic Goudy cut a typeface
for the University of California Press in 1938: Sorts Mill Goudy is the free
revival of it, and it carries the headings and the body text. IBM Plex Mono is
the second voice; the one used for buttons, labels, dates and numbers, the way
a lab notebook sits beside a printed book.

Two rules matter if you ever touch the styling:

**Every colour is a token.** The stylesheet defines names; paper, ink, the
three pigments; in one place, and pages use the names rather than the colour
values. That is how the whole site can be re-inked at once, and how `/negatives`
turns itself into a darkroom and `/fitness` into blueprint steel by redefining
the same names.

**Tailwind is installed but generates nothing.** It runs in a mode where it
scans no files, so none of its shortcut classes exist. Every rule on this site
was written by hand. Do not reach for a utility class; it will silently do
nothing.

### The mobile app and offline caching

The site is an installable **Progressive Web App (PWA)**:
- Adding it to a mobile home screen installs it as a standalone app with its own icon, running in full-screen without browser address bars.
- A service worker (`priv/static/sw.js`) pre-caches the site's typography and stylesheets, serves static media cache-first, and falls back gracefully when mobile connectivity drops.
- WebSocket connections (`/live`) and administrative routes (`/admin`) bypass the cache entirely to ensure real-time LiveView communication is never buffered.

### Discoverability and search engines

Every public page carries structured Schema.org metadata (JSON-LD) identifying:
- The site and author (`Person` and `WebSite` schemas).
- Writing as full `BlogPosting` entries with publication dates, headlines, and breadcrumb trails.
- Captain's logs as `AudioObject` or `VideoObject` entries with runtimes, poster artwork, and streaming URLs.
- Author profile on `/about` as a dedicated `ProfilePage` tied to the author's name and institutional research affiliation.
- A comprehensive sitemap (`/sitemap.xml`) updated at request time with real dates for search engine crawlers.

---

## Part 6: The shortcuts

Everything below is typed into a terminal, from inside the project folder unless
it says otherwise.

### Working on the site on your own computer

| Command | What it does |
|---|---|
| `mix setup` | First time only. Fetches everything, creates the database, builds the styles. |
| `mix phx.server` | Starts the site at http://localhost:4000. Stop it with Ctrl-C twice. |
| `iex -S mix phx.server` | The same, but with a prompt where you can talk to the running site. |
| `mix assets.build` | Rebuilds the CSS and JavaScript. Run this after editing a stylesheet. |

> Phoenix reloads Elixir and template changes by itself while the server is
> running; you edit, you refresh, you see it. Stylesheets are the exception
> worth remembering: if a CSS change does not appear, run `mix assets.build`.

### Before you commit anything

| Command | What it does |
|---|---|
| `mix precommit` | The gate. Compiles with warnings treated as errors, checks for unused dependencies, formats the code, runs every test. |
| `mix test` | Just the tests. |
| `mix test test/web/blog_test.exs` | One file. |
| `mix test --failed` | Only what failed last time. |
| `mix format` | Tidies the code layout. |

`mix precommit` is the one that matters. If it passes, the change is done.

### Putting changes on the live site

```
./redeploy.sh
```

That is the whole answer, and it should not be replaced with anything shorter.
It builds the minified stylesheets, builds the release, restarts the service,
waits for the site to answer, and then checks four things before it will call
itself successful: that the homepage returns normally, that the developer-only
pages are closed to the public, that the stylesheet the site is serving matches
the one on disk byte for byte, and that a page which needs the database actually
shows real data.

Every one of those checks exists because that exact thing once went wrong
silently. The most instructive is the stylesheet one: a months-old compressed
copy of the styles once shadowed the real file, and the site served last
season's design for weeks without any error anywhere.

> Content is different. A new blog post or a new contact sheet needs **no
> deploy**; it is read from disk. Deploying is only for changes to the code
> itself.

### Looking after the running site

| Command | What it does |
|---|---|
| `systemctl --user status streetscissors` | Is it running? |
| `systemctl --user restart streetscissors` | Restart it. |
| `systemctl --user stop streetscissors` | Stop it. |
| `journalctl --user -u streetscissors -f` | Watch the log as it happens. Ctrl-C to stop watching. |
| `journalctl --user -u streetscissors -n 50` | The last fifty lines. |

The same commands work for `caddy-streetscissors`, the web server in front.

**systemd** is the part of Linux that keeps programs running and starts them
again if they stop. The site is registered with it as a *user service*, which is
why every command has `--user` in it.

> There is an older shortcut on this machine, `site up` and `site down`, from
> before the site was supervised properly. It starts a development server and
> its own copy of the web server, as root, outside systemd's control.
>
> It has already caused one real outage, and the shape of it is worth knowing.
> The web server it starts runs as root, so the log file it creates belongs to
> root. The supervised one runs as you, cannot open that file, and so refuses to
> start; quietly, forever, while the unsupervised copy keeps serving and hides
> the fact. The site looked healthy for five days while the thing meant to keep
> it alive had failed seventy-three thousand times. Use the `systemctl` commands
> above.

### The darkroom

| Command | What it does |
|---|---|
| `negatives` | Scan a roll, start to finish |
| `negatives --list` | Which roll numbers are taken |
| `negatives --recompile 7` | Rebuild roll 7's sheet from the scans already there |
| `negatives --analyze 7` | Score every frame's exposure |
| `digital-contact-sheet-maker <folder>` | Build a sheet from any folder of scans |

Full details in Part 3.

### Things that look like shortcuts but are not

`./deploy.sh` builds and runs the site in containers. It was tried and set
aside; the live site does not use it. `./start_prod.sh` runs the built site by
hand in a terminal, which is useful for looking at a build before trusting it,
but it is not how the site stays up.

---

## Part 7: Running your own copy

The code is on GitHub at
[cranialcaudal/streetscissors](https://github.com/cranialcaudal/streetscissors).

You will need **Elixir** and **Erlang** installed. You do not need Node.js; the
tools that build the stylesheets and JavaScript are fetched automatically. If
you want the photography half to work you also need **ImageMagick**, which makes
the web-sized copies, and **GIMP**, which builds contact sheets.

```
git clone https://github.com/cranialcaudal/streetscissors.git
cd streetscissors
mix setup
mix phx.server
```

Then open http://localhost:4000.

Most of it works immediately. Some of it will be empty, and that is expected:

- **`/blog` will have nothing in it.** The writing is not in the repository;
  see the licence note below. Put your own Markdown files in `content/blog/`
  and they will appear.
- **`/negatives` will be empty** unless you point it at a folder of contact
  sheets. It looks for a `negatives/` folder beside the checkout by default,
  or wherever `NEGATIVES_PATH` in `.env` points.
- **Komoot, mail and the newsletter stay switched off** until you fill in a
  `.env` file. Copy `.env.example` to `.env` and fill in what you want. Nothing
  in it is needed to start the site.

### A note on the licence

The repository is deliberately split in two.

**The software is MIT licensed**; everything under `lib/`, `assets/`,
`config/`, `test/`, `priv/repo/`, `docs/`, and the scripts at the top level.
Take it, learn from it, build on it, sell it. This manual is included in that.

**The content is not.** The writing, the photographs, the recordings and the
training notes under `content/` and `priv/static/images/` are all rights
reserved. They are in the repository so the site can actually be built and run,
not so they can be reused.

---

## Part 8: Glossary

**Backup**: On this machine, a verified copy of the database taken every night
at 20:17 Pacific, kept for two weeks. Not a file copy: the database is asked to
write a clean copy of itself, which is then reopened and checked before it is
trusted. Two minutes later the written content gets the same treatment: the
vault is packed into one archive, the archive is unpacked again and compared
file by file with what is on disk, and it is kept only if something changed
since the last one, so the thirty that are kept are thirty versions, not thirty
nights. Plugging in the external drive triggers a copy of everything, including
the photograph archive and the recordings, within thirty seconds.

**Caddy**: The web server that faces the internet, holds the encryption
certificate, and passes requests to the site.

**Contact sheet**: One image showing every frame on a roll of film at its true
size. See Part 3.

**C-41**: The standard process for developing colour negative film. The
negatives it produces have an orange cast built into them, which has to be
undone when scanning.

**Commit**: A saved point in the project's history, with a message explaining
what changed and why.

**Deploy**: Putting a change to the code onto the live site. Here: `./redeploy.sh`.

**Elixir**: The programming language the site is written in.

**Frame**: One photograph on a roll of film. Frames are numbered along the roll.

**Frontmatter**: The small block of information between two `---` lines at the
top of a Markdown file: title, date, keywords.

**GIMP**: A free image editor. Here it is used without its window ever opening,
purely as an engine for assembling contact sheets.

**ImageMagick**: A set of image tools that run from the command line. Used here
to make the web-sized copies of contact sheets.

**LiveView**: The part of Phoenix that lets a page update itself without
custom browser code.

**Markdown**: Plain text with a few marks in it that mean "heading", "italic",
"link". Readable as-is; converts to a web page.

**Migration**: A recorded change to the shape of the database, so the same
change can be replayed anywhere.

**Obsidian**: A note-taking program that works on ordinary Markdown files in an
ordinary folder. The writing on this site is edited in it, but nothing depends
on it.

**Phoenix**: The toolkit that turns Elixir into a website.

**Preview**: The smaller, web-friendly copy of a contact sheet, made
automatically the first time someone asks for that sheet and remade whenever the
sheet changes.

**Release**: A self-contained, compiled copy of the site, built by
`./redeploy.sh` and run by systemd. It contains everything needed to run and
nothing needed to build.

**Repository (repo)**: The project folder, with its full history. This one
lives on GitHub.

**Roll**: One length of film, shot, developed and scanned as a unit. Numbered
uniquely across the whole archive: roll 7 is roll 7 forever.

**SQLite**: The database. A single file on disk rather than a server.

**Strip**: A roll of film cut into a short length, usually three, four or six
frames, so it fits in a scanner.

**systemd**: The part of Linux that starts programs and keeps them running.

**Tailwind**: A popular CSS toolkit. Installed here but deliberately producing
nothing; all styling on this site is written by hand.

**Witnessed**; This site's word for how many times a piece has been read or
listened to. `/blog` and `/logs` can both be sorted by it.
