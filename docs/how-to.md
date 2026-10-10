# How this is made

A manual for the streetscissors website and the darkroom pipeline behind it.

It is written in two registers, for two kinds of reader.

Parts 1 to 4 assume nothing. They say what the site is for, how a photograph gets from a strip of developed film onto the internet, and how a text file becomes a page. If you have never programmed, they are the whole manual.

Parts 5 to 9 are for someone who programs: not a Phoenix expert, but someone who can read a shell script and a config file and wants to know exactly how the thing is built and kept running. Which process listens on which port. What the deploy script does, in order, and why. Where every kind of data lives, how it is backed up, and how to get it back. What to check first when something breaks.

Every unfamiliar word is explained the first time it appears, and again in the glossary at the end. Read it in order or jump to the part you need.

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

- **Every day is a page.** `/daybook` opens like an engagement calendar, at this week: a photograph on one side and seven ruled days on the other. A day with work in it holds everything made that day side by side. A year is laid out like a contact sheet, and it prints as a clean edition.
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

The rest of this manual is how that idea is actually implemented; first for photographs, then for words, then the machinery underneath both. Part 10 shows how to run a copy of the whole thing yourself.

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
| `/daybook` | Everything made, day by day, as an engagement calendar | Built live from all of the above |
| `/guestbook` | Messages from visitors | Database |
| `/newsletter` | Sign-up for the mailing list | Database |
| `/about` | Who made this | A text file |
| `/how-to` | This page | `docs/how-to.md` |
| `/roadmap` | What gets built next | `docs/roadmap.md` |
| `/search` | One search across all of the above | Everything, read as you ask |
| `/feed` | Everything new, as an RSS feed | Built live from all of the above |
| `/admin` | The private side, behind a password | All of the above, edited in one place |

Three of those deserve a note.

**`/blog` and `/logs` are siblings, not parent and child.** The blog is written
work; the logs are spoken work. They are separate systems that happen to share
one vocabulary; see *Keywords* in Part 4. Both can be sorted by **most recent**
or by their count: **most witnessed** for the blog, which means most read, and
**most viewed** for the logs.

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
logs, the fitness wiki, the keywords, and a report on what is broken),
**Darkroom** (the scanner), **Mail** (the inbox, the guestbook, citations from
other sites, the newsletter) and **Sync** (the Komoot activities, and the heart
rate that goes with them), plus a page of settings. The admin writes the same
files you would write by hand, so nothing it does is locked inside it.

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

These tools are the darkroom's, not the website's. They are not part of the
site's repository, and they work with no website at all. The site's scanner
page, described at the end of this part, runs the last two itself.

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

**Slide film is already the picture.** Colour reversal film (the E-6 process:
Ektachrome and its kind) comes out of the tank as a positive, so nothing is
inverted and there is no orange mask to remove. Its difficulty is the opposite
one. The frames are separated by black, not by clear film, and at night a
picture's shadows are exactly as black as the gap beside them. So for slides
the software does not go looking for black lines. It slides a template of the
frame (36 mm of picture, 2 mm of gap) along the strip and keeps the position
where nothing of a picture falls in a gap.

Nobody has to say which of the three kinds of film is on the glass. A colour
negative's clear film is orange; a slide's is neutral and its borders are true
black; black-and-white has no colour at all.

All of this is measured **per strip, not per roll**. One dark strip should not
be allowed to drag down the exposure of every other strip on the sheet. A
single frame scanned for a page of its own is treated the other way round: the
roll as a whole decides the colour, and the frame only its own exposure.
Judging each thin negative by itself is what used to tint them.

**Where one frame ends.** A 35mm frame is 36 mm wide. How far the film was
wound between frames is the camera's business, and some cameras are uneven
about it. So the software finds the gaps on the film itself, cuts whole 36 mm
frames, and where a camera's spacing wanders it walks outward from the
plainest frame rather than trusting a fixed grid. On 120 and 620 film the
number of frames on a strip is read off the film too, since the same film makes
twelve square pictures in one camera and eight wide ones in another.

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

The page follows one loop for each load of the holder, and its one big button always says what is next.

1. **Load the holder and press Preview.** Both slots of the 35mm holder can be filled. A quick look over the glass (about 30 seconds) reads the format and whether the film is colour, names the roll and makes its folder (slide film needs no telling: it is recognised when the strips are measured), adds every strip it finds, and shows the frames of this load as positives, lying landscape. If the holder was loaded wrong, fix it and press Preview again: the second look replaces the first. 620 is 120 film and reads as 120, so set that one by hand first, under Roll.
2. **Select.** The well exposed frames are ticked for you. Tick the ones you want as singles and turn any that are the wrong way up.
3. **Press Scan.** The scanner goes back for the ticked frames at 1600 dpi; frames next to each other, or side by side in the two slots, are taken in one crossing (about a minute for three). Leave the film where it is. With nothing ticked the button reads "No singles, next load" and just moves on.
4. **Load the next strips.** When the scan ends the page is back at Preview. The singles you scanned are listed under **Singles in roll**, where each can still be turned or removed; those are the pictures that get a page of their own.
5. **Publish roll**, when the roll is all in. One press assembles the contact sheet, checks it and puts the roll on `/negatives`. If it stops, it says at which step. Pressed while a load is still at Select with frames ticked, it scans those singles first and publishes when they are in.

**Adding singles to a roll that is already published.** Lay strips of that roll back in the holder (either slot, either way up; one roll at a time) and press **Add singles to an old roll**. The page looks at the glass, matches the film against every roll in the archive, opens the roll it belongs to and shows those strips' frames. Tick what you want and press Scan: the new singles go straight onto the roll's page, with their rings on the contact sheet. Nothing is published again. Frames chosen earlier and never made come back ticked. **Back to new film** returns to the roll you were building. If it cannot place the film, open the roll from the Archive tab and use *Find this roll's strips on the glass* there.

**Where one roll ends.** Under Roll, *Strips per roll* (7 to begin with) is how many strips one archive sleeve holds; leave it blank to switch the counting off. The holder takes two strips at a time, so the strip that fills a roll often shares the glass with the first strip of the next one. Nothing is decided at the look: both strips join the roll on the bench, and their singles are chosen and scanned together. When the load is done and the roll is one strip over, the page asks which of its last two strips begins the next roll, and cuts there; the strip takes its singles with it. A roll with exactly its count is simply full, and the next Preview opens the next roll. A full roll waits on the bench with a **Publish** button of its own, and nothing is published until you press it. Singles are developed in the background: as soon as the scanner stops, change the film.

**About the roll.** Under Roll, say what you know that the film cannot: when it was shot (a year, a month or a day, as exact as you know it), the camera, the film stock, the place, and a note. It is saved as you type, kept with the roll, and shown on the roll's page. The roll is still filed by the day it was scanned.

Strips can be put in order, turned 180° or deleted under Strips. Do that before scanning singles from them, since singles are filed by frame number.

Strips scanned elsewhere can still be dropped onto the page, under Strips; they are kept exactly as they were, and a single from one means putting the strip back in the calibrated slot.

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

`/fitness` works like the blog: Markdown files, this time in `content/fitness/`.
The public page deliberately shows only the headings and the checklist items;
the notes about where and when and why stay in the file and never reach the
page.

A day is assembled from two kinds of file, so that a block of work written once
can be used on any day that wants it.

- **A day** lives in `weekly/` (or `additional/`, for the sessions that belong
  to no particular day). It is short: a title, the name on its tab, and a list
  of the blocks it is made of.
- **A module** lives in `modules/`. It is one block: a warm-up, a swim set, a
  long run, with its exercises as a checklist. A module is never a page by
  itself. It appears only where a day names it.

The list is a line in the day's frontmatter:

```
---
title: "Tuesday: Upper Body"
tab: Tuesday
modules: shoulder-warmup, upper-pull, universal-cooldown
---
```

When the page is asked for, the site reads that line, fetches those three files
from `modules/`, and sets them one under another beneath whatever the day's own
file says. A day that alternates (a swim one week, a run the next) lists its
alternatives as `option_1:`, `option_2:` and so on, and the site shows the one
whose turn it is.

Names are matched exactly, and a name that matches nothing fails silently: the
block is simply missing from the page. `/admin/health` lists any module a day
asks for that is not there, and any module that no day asks for.

`content/templates/` holds a starting file for each kind, for Obsidian to copy
from. Nothing on the site reads that folder.

### The exercise wiki and its figures

Each exercise has a page under `/fitness/wiki`: a Markdown file in
`content/fitness/exercise-wiki/`, one folder per muscle group. Every page has
the same frontmatter and the same sections, and `/admin/health` lists a page
that has drifted from that shape.

Most pages lead with a figure doing the exercise. The figure is described by a
small file in the vault's `figures/` folder: a few poses that say where the
body is (the pelvis, the lean of the back, where each hand and foot rests),
never joint angles. The site works out the elbows and knees so that each limb
reaches, and refuses a figure that cannot: one that goes through the floor, or
whose arm is longer in one pose than the next.

What the page plays is a short silent film of that figure, drawn once in three
dimensions with the working muscles lit, and about a hundred kilobytes. Films
are content, not code. They are made on the bench with one command and kept
with the other uploaded media, so nothing is deployed for a page to play one.
Edit a figure and its page falls back to a flat drawing of the same poses until
it is filmed again; `/admin/health` lists the ones waiting. Part 8 has the
commands.

### Rides, runs and the heart rate

Bike rides arrive on their own. Once an hour the site asks Komoot for anything
new and copies it across, and a tour deleted there leaves the site on the next
pass. If Komoot is not set up, nothing happens and nothing breaks.

**Komoot draws each activity.** The page shows Komoot's own embed: its map, its
figures, its elevation profile and any photographs taken along the way. A
private tour is shown through a share link, which the site asks Komoot to make
the first time it sees the tour.

**Home is hidden by Komoot, and the site checks.** In the Komoot app there is a
*privacy zone* around the house, and Komoot removes everything inside it from
what anybody else is shown. That is the protection. But it lives on somebody
else's computer, so the site keeps its own note of where home is
(`RIDE_PRIVACY_ZONES`, in `.env`, never in the code) and, each time it reads a
tour, reads it the way a stranger would and asks one question: does any of this
come within a hundred metres of home? What it finds is one of four things.

| What a stranger is given | What the site shows |
|---|---|
| A route that stays away from home | Komoot's embed, map and link |
| A route that begins or ends at home | The figures only, and a warning to you |
| A route that passes home in the middle | The figures only |
| Nothing: the whole tour is inside the zone | The figures only |

The second row is the alarm. A zone that is working trims exactly the two ends
of a tour, so a route that still begins or ends at home means the zone has been
deleted, moved or switched off. The overview says so and the site writes to
you.

The third row is not an alarm, and it happens more than you would think.
**A zone trims where a tour starts and where it ends, and nothing else.** A ride
that comes home, stops for lunch and goes out again is handed to a stranger
with both ends cut and the middle whole, front door included. The site holds
those back quietly. To show one, split or trim the tour in the Komoot app, then
press **Sync now** on the admin's Activities page, which reads every tour
again.

**Heart rate and energy come from the watch, by way of the phone.** Komoot
keeps neither. The watch writes them to Apple Health, and getting them to the
site is a job done by hand every so often:

1. On the phone, open **Health**, tap your picture, and choose **Export All
   Health Data**. It makes one file, `export.zip`.
2. Send that file to this computer (AirDrop, a cable, anything).
3. On the admin's **Activities** page, drop it on *Heart & energy*.

The site reads the file in the background and says what it found. It keeps
only the workouts that match an activity, with the heart rate during them. The
rest of the file is never read (not sleep, not weight, not where you were) and
the file itself is deleted as soon as it has been read. Do it again whenever
you want the newer rides filled in; a workout already on file is simply
updated.

There is also an automatic way: an app on the phone can post each workout as it
is recorded. It is switched off until you make a token for it on the same page,
and the app that does it charges money, which is why the file is the default.

What the page then shows, above the map: average, peak and lowest heart rate,
active energy, the time spent in each of five effort zones, and the heart rate
drawn across the whole outing. The zones are shares of the highest heart rate
the watch has ever recorded for you, since the site is never told your age.

### The newsletter

People sign up through the overlay on any page, past a hand-made puzzle rather
than a Google one, limited to three attempts an hour from any one address. They
get a welcome letter immediately. Every letter carries a real unsubscribe link
and the header that lets a mail program offer a one-click unsubscribe.

Unsubscribing never deletes anybody. It marks them inactive, so re-adding the
same address cannot start mailing them again by accident.

---

## Part 5: The machine

From here on the manual is for someone who programs. Not a Phoenix expert:
someone who can read a shell script and a config file, and wants to know
exactly how this site is put together, which process listens where, and what
happens in what order. Part 5 is the anatomy. Part 6 is how it is run, Part 7
how it is kept safe, and Part 8 how to change it without breaking it.

### The words, in plain language

**Elixir** is the programming language the site is written in. It runs on the
Erlang virtual machine, called the **BEAM**, which was built for telephone
exchanges: many small processes that share nothing, watched by supervisors that
restart the ones that die. **Phoenix** is the toolkit that turns Elixir into a
website. **LiveView** is the part of Phoenix that lets a page update itself
without hand-written browser code: the page keeps a connection open to the
server, and when something changes the server sends just the changed piece.
**SQLite** is the database: not a server you install and manage, but a single
file on disk.

Nothing here runs in the cloud. There is no Amazon, no Vercel, no managed
anything, and no container.

### The stack, by name and version

| Layer | What does it | Version on the live machine |
|---|---|---|
| Operating system | Fedora Linux | 43 |
| Language and VM | Elixir on Erlang/OTP | 1.19 on OTP 26 (`mix.exs` asks for `~> 1.15`) |
| Web framework | Phoenix, with LiveView | 1.8 and 1.1 |
| HTTP server inside the app | Bandit | 1.12 |
| Database | SQLite, through `ecto_sqlite3` | one file, in WAL mode |
| Queued jobs | Oban, on its SQLite engine (`Oban.Engines.Lite`) | 2.20 |
| Scheduled jobs | Quantum, a cron inside the VM | 3.5 |
| Mail | Swoosh, sending through Resend's HTTP API | 1.20 |
| HTTP client | Req | 0.5 |
| Markdown | Earmark | 1.4 |
| CSS and JavaScript build | Tailwind 4.1 and esbuild 0.25, as standalone programs `mix` fetches | no Node.js in the build |
| Front proxy and TLS | Caddy | 2.10 |
| Process supervisor | systemd, as user units | |

The exact versions of every dependency are pinned in `mix.lock`.

### One computer, two processes

The whole site is two long-running programs on one machine, each kept alive by
systemd.

```
                        ┌────────────────────── one computer ──────────────────────┐
 browser ── 443 ──▶  Caddy  ──┬─ /uploads/*  ──▶  files on disk (the uploads folder)
 (80 redirects to 443)        │
                              └─ everything else ─▶ 127.0.0.1:4000
                                                     Bandit ▶ Phoenix (the release)
                                                       ├─ SQLite file
                                                       ├─ content/  (the vault)
                                                       ├─ the negatives archive
                                                       └─ child programs: ffmpeg,
                                                          ImageMagick, scanimage,
                                                          film-develop, rsync
```

**Caddy** (`caddy-streetscissors.service`) is the only thing that faces the
internet. It owns ports 80 and 443, holds the certificate, and serves uploaded
media straight off the disk.

**The release** (`streetscissors.service`) is the application: a compiled,
self-contained copy of the Elixir code and the Erlang runtime, listening on
port 4000 of the loopback address only, so nothing but this machine can reach
it.

A **release** is worth a sentence, because it shapes everything about
deploying. `mix release` compiles the project and packs it, with the runtime
and a start script, into one directory (`_build/prod/rel/web/`). That directory
runs with no source code, no `mix` and no compiler. It also carries its own
copy of `priv/`, which it replaces wholesale on every build. That last fact is
why nothing the site writes while it runs may live inside the release.

### Where everything lives on the disk

| Path | What it is | Written by |
|---|---|---|
| `~/streetscissors/` | The checkout: code, the `content/` vault, `.env`, the `Caddyfile`, the deploy scripts, and Caddy's access log | You, git, the admin's editors |
| `…/_build/prod/rel/web/` | Inside the checkout: the release being served. `web.previous` beside it is the one that was serving before the last deploy | `./redeploy.sh` |
| `~/streetscissors-data/` | The live data. `streetscissors.db` with its `-wal` and `-shm` companions; `uploads/` for recordings, the blog's images and the exercise films; `ride_thumbs/` for cached route pictures | The release, and `mix fitness.film` |
| `~/streetscissors-backups/` | `db/` for database snapshots, `content/` for versions of the writing | The release |
| The negatives archive | Scans, contact sheets, the catalogue. Wherever `NEGATIVES_PATH` points | The darkroom tools and the scanner page |
| An external drive | A second copy of the backups, the negatives and the recordings, when it is plugged in | The release |
| `~/.config/systemd/user/` | The two unit files. Copies are kept in `ops/systemd/` | You |
| `~/.local/share/caddy/` | Caddy's certificates and keys | Caddy |
| `~/.local/bin/` | The darkroom tools | You |

Three kinds of thing are kept apart on purpose:

- **Code** is in the checkout and in git. It can be rebuilt from nothing.
- **Content** (`content/`) is in the checkout but not in git: the public
  repository is the site's skeleton only. It is read from disk by whichever
  release is running, which is why a new post needs no deploy.
- **Data** the site writes while running (the database, uploads, thumbnails,
  backups) is outside the checkout entirely, so that neither a deploy nor a
  `git clean` can touch it.

### What happens to a request, exactly

Take a visitor asking for the post at `/blog/some-post`.

**1. The name.** DNS answers with the public address of the house. That record
is set by hand in the registrar's panel, which has no API, so there is no
dynamic DNS: if the provider changes the house's address, the site's own
monitor notices and writes to its owner with the new value to type in.

**2. The router** in the house forwards ports 80 and 443 to this machine.

**3. Caddy** takes the connection. In order:

- Port 80 is answered with a redirect to HTTPS. `www.` is redirected to the
  bare name.
- TLS is terminated with a Let's Encrypt certificate that Caddy obtained and
  renews by itself. HTTP/3 is switched off: restarts used to leave browsers
  holding dead QUIC connections, and every page hung until the browser was
  restarted.
- A request from a named scraper (`GPTBot`, `ClaudeBot`, `Bytespider` and a
  few more) is answered 403 and goes no further.
- A request under `/uploads/` is served straight off the disk, with byte
  ranges for seeking and a one-year `immutable` cache header. No part of the
  application is in that path, so a visitor scrubbing through a video costs
  the Elixir side nothing.
- Everything else is passed to `localhost:4000`, with the visitor's address
  in an `X-Forwarded-For` header that Caddy writes itself.
- On the way back out, Caddy compresses the response (zstd or gzip) and adds
  a few headers: `Strict-Transport-Security` for a year, `X-Frame-Options`,
  `X-Content-Type-Options`, a referrer policy.

Caddy runs as an ordinary user, not as root. An ordinary user may not normally
bind a port below 1024, so the machine has one line of system configuration, in
a file under `/etc/sysctl.d/`, that lowers the floor:

```
net.ipv4.ip_unprivileged_port_start=80
```

A new machine needs that line or Caddy will fail to start.

**4. Bandit**, the HTTP server inside the release, accepts the proxied request
and hands it to `WebWeb.Endpoint` (`lib/web_web/endpoint.ex`), which runs a
fixed chain of **plugs**. A plug is a function that takes the request and
returns it, possibly changed, possibly answered. In order:

| Plug | What it does here |
|---|---|
| `WebWeb.Plugs.MediaServe` | Serves `/uploads/` with byte ranges. In production Caddy has already taken those requests; this is for development, where there is no Caddy |
| `Plug.Static` | Serves files from `priv/static`, but only the top-level names listed in `WebWeb.static_paths/0` (`assets`, `fonts`, `images`, `robots.txt`, `sw.js` and a few more). A new file there is invisible until it is added to that list |
| `Plug.RequestId`, `Plug.Telemetry` | Give the request an id for the log, and time it |
| `Plug.Parsers` | Decode form posts, uploads and JSON |
| `Plug.MethodOverride`, `Plug.Head` | Let a form say `DELETE`; answer `HEAD` as `GET` without a body |
| `Plug.Session` | Read the signed session cookie |
| `WebWeb.Router` | Decide what code answers |

**5. The router** (`lib/web_web/router.ex`) matches the address and sends the
request through a **pipeline**, which is just a named list of more plugs.
Nearly every page goes through `:browser`:

| Step in `:browser` | What it does |
|---|---|
| `accepts ["html"]` | Refuses anything that is not asking for a page |
| `fetch_session`, `fetch_live_flash` | Load the session and any one-time notice |
| `put_root_layout`, `put_layout` | Choose the HTML shell |
| `protect_from_forgery` | Refuse a form post that does not carry this session's CSRF token |
| `put_secure_browser_headers` | Phoenix's default security headers |
| `WebWeb.Plugs.Analytics` | Record one hit (not for a prefetch, a bot, or a sub-resource) |
| `WebWeb.Plugs.SetCurrentUser` | Tell templates whether this is the admin. It protects nothing |
| `WebWeb.Plugs.FetchStats` | Count today's distinct visitors, for the header |
| `WebWeb.Plugs.LoadSiteSettings` | Load the handful of settings kept in the database |

Then the matched code runs: `BlogController.show/2` asks `Web.Blog` for the
post, which reads the Markdown file from `content/blog/` at that moment,
renders it, and returns HTML.

**6. The answer** goes back through Caddy to the browser.

That is the whole path, and it runs for every visitor, every time. There is no
page cache in front of it and no build step behind it. What *is* remembered is
small and specific: this manual's rendered HTML until the file's modification
time changes, a few reference files parsed once at boot (`Web.Warm`), the
web-sized copies of photographs on disk, and whatever the browser itself caches
(the fingerprinted stylesheet and script, and everything under `/uploads/`, are
marked immutable).

### The addresses that skip the browser pipeline

A few addresses are called by machines, not by people, and a machine has no
session and no CSRF token. Each has its own short pipeline, and its own reason
to be safe without one.

| Address | Who calls it | What authorises it |
|---|---|---|
| `POST /unsubscribe/…/one-click` | A mail program's one-click unsubscribe | The signed token in the address. It can only ever remove consent |
| `POST /webmention` | Another website, saying it linked here | Nothing is trusted until the source is fetched and the author approves it |
| `POST /seen` | The browser, reporting that a prefetched page was actually shown | Nothing to protect: it counts a view |
| `POST /api/health/ingest` | An app on the phone, posting a workout | A bearer token. With none made, everything is refused |
| `GET /health` | The uptime check and the site's own monitor | Nothing to protect: it answers yes or no |
| `GET /share/...` | Link unfurlers, asking for a preview picture | Nothing to protect |

### How a live page differs

Some pages are ordinary controller pages: one request, one HTML response,
done. Others are **LiveViews** (the negatives archive, the logs, the fitness
pages, the guestbook, the whole admin). A LiveView is rendered twice:

1. First as plain HTML, through exactly the path above. A reader with
   JavaScript off, or a search engine, gets a complete page.
2. Then the page's JavaScript opens a WebSocket to `/live`, the server starts
   one process for that tab, renders the page again inside it, and from then
   on sends only differences.

Two consequences are worth knowing before they surprise you.

**The socket checks where the page came from.** `check_origin` in
`config/runtime.exs` lists the site's own hostnames, and a socket opened by a
page served under any other name is refused. So if you open the site by IP
address, or as `localhost:4000`, the first render appears and then nothing
live works: no hooks mount, no buttons respond. To see a live page on the
server itself, use the real name. On this machine `/etc/hosts` points the
domain at loopback, so the site's public address goes through the local Caddy
and behaves exactly as it does for a visitor.

**Browser-side behaviour is attached by hooks.** Where a page needs its own
JavaScript (the video player, the recording booth, the exercise figure), the
script is written next to the markup as a *colocated hook*. The Elixir compiler
extracts those scripts, and the JavaScript bundler picks them up. That ordering
matters at build time, and Part 8 returns to it.

### Whose address is it

Because Caddy is always the one connecting, every request the application
sees comes from `127.0.0.1`. The visitor's real address is the first entry of
`X-Forwarded-For` (`WebWeb.ClientIP`). Caddy writes that header itself and
does not pass on one a stranger supplied.

This is the reason the application listens on loopback only. Reached directly,
around the proxy, a caller could write `X-Forwarded-For` themselves and be
whoever they liked, and the address is what every rate limit below counts by.

### Sessions and the admin

There are no user accounts. There is one administrator and one password.

**The session is one cookie**, `_web_key`. It is *signed*, not encrypted: the
browser can read what is in it but cannot change it without the signature
failing. It is marked `SameSite=Lax`, is only ever sent over HTTPS in
production (`Secure`), and expires after fourteen days. The signing key is
derived from `SECRET_KEY_BASE`, which is why that value is the one real secret
of the site. The "salts" beside it in the code are not secrets; they only keep
keys derived for different purposes apart.

**Logging in** (`AdminSessionController`) compares the submitted
password with `ADMIN_PASSWORD` in constant time, and on a match puts
`admin_user: true` in the session and reissues the cookie. Ten attempts are
allowed per address per fifteen minutes.

**Every admin page checks the flag.** All `/admin/*` LiveViews sit in one
`live_session :admin` block in the router, whose `on_mount` hook
(`WebWeb.AdminAuth`) redirects anyone without the flag before the page mounts.
A new admin page belongs inside that block, and then it is protected without
doing anything further.

Two things follow from there being no session store on the server:

- Changing `ADMIN_PASSWORD` does not log out a browser that is already in.
- The only way to end every session at once is to change `SECRET_KEY_BASE`
  and restart, which invalidates every cookie ever issued.

### What runs inside the release

The BEAM runs many small processes, arranged as a **supervision tree**: a
supervisor starts its children in order and restarts any that crash. This
site's tree is one flat list in `lib/web/application.ex`, started top to
bottom. If one child dies, only that child is restarted.

| Order | Child | What it is for |
|---|---|---|
| 1 | `WebWeb.Telemetry` | Timing and counters |
| 2 | `Web.Repo` | The pool of five database connections |
| 3 | `Ecto.Migrator` | Runs any pending database migration, then steps aside. Only in a release |
| 4 | `DNSCluster` | For clustering several servers. There is one, so it does nothing |
| 5 | `Phoenix.PubSub` | Message bus between processes: scan progress, encode progress, new signatures |
| 6 | `Finch` | The HTTP connection pool mail is sent through |
| 7 | `Task.Supervisor` | A place to run one-off background tasks |
| 8 | `Web.RateLimit` | Owns the table that counts login attempts and form posts. Must exist before any request arrives |
| 9 | `Web.Komoot.Auth` | Remembers the Komoot login between hourly syncs |
| 10 | `Oban` | The job queue |
| 11 | `Web.Media.Transcoder` | The ffmpeg queue for recordings, one encode at a time |
| 12 | `Web.Scanner.Bed` | The flatbed scanner, one scan at a time |
| 13 | `Web.Scheduler` | The clock (Quantum) |
| 14 | a one-off task | Takes any backup the machine slept through |
| 15 | a one-off task | Clears an Apple Health import that a restart interrupted |
| 16 | `Web.Backup.MirrorWatcher` | Notices the external drive being plugged in |
| 17 | `WebWeb.Endpoint` | Starts answering requests. Last on purpose |
| 18 | a one-off task | `Web.Warm`: reads what the first visitor would otherwise wait for |

The order is the boot sequence. The database is migrated before anything
reads it, the rate limiter exists before the first request can arrive, and the
site only starts answering once everything it depends on is standing.

### Work that happens on a clock

`Web.Scheduler` is a cron that lives inside the VM. Its table is in
`config/config.exs`, and its times are in **UTC**.

| When (UTC) | What runs | Module |
|---|---|---|
| Every hour at :07 | Ask Komoot for new or deleted tours | `Web.Rides.KomootSync` |
| Every hour at :23 | Tell other sites about links to them (webmentions) | `Web.Webmentions.Outgoing` |
| Every 15 minutes | The machine checks itself | `Web.Monitor` |
| 03:17 daily | Snapshot the database | `Web.Backup` |
| 03:19 daily | Keep a version of the writing, if it changed | `Web.Backup.Content` |
| 03:41 on Sundays | Rehearse a restore | `Web.Backup.Drill` |

03:17 UTC is 8:17 in the evening, Pacific daylight time, and an hour earlier
in winter.

A cron inside a program has one weakness: it does not make up a run it slept
through. If the machine was off at 03:17, that night produces nothing. So at
every boot `Web.Backup.catch_up/0` looks at how old the newest snapshot and the
newest content version are, and takes one if it is more than twenty hours old.

### Work that is queued

**Oban** is a job queue whose jobs are rows in the database (`oban_jobs`), so a
job survives a restart and is retried if it fails. It is used for anything
that talks to someone else's server and might not get an answer:

| Queue | Jobs | Attempts |
|---|---|---|
| `mailers` | One letter of the newsletter per subscriber; mail from the site to its owner | 3 and 5 |
| `webmentions` | Sending a webmention; fetching and verifying one received | 3 |

Two queues are deliberately *not* Oban:

- **The transcoder** (`Web.Media.Transcoder`) runs ffmpeg for one recording at
  a time. A retry would re-encode an unreadable file over and over, so it
  keeps its own state in the recording's row (`pending`, `processing`,
  `ready`, `failed`) and on boot simply picks up whatever a restart left
  unfinished.
- **The scanner** (`Web.Scanner.Bed`) owns a physical device that can do one
  thing at a time. A second request while it is working is answered "busy".

### The database

One SQLite file, opened in **WAL mode**. WAL (write-ahead log) means recent
writes sit in a companion file, `streetscissors.db-wal`, until they are folded
back into the main file. Two things follow:

- The database is really **three files** (`.db`, `.db-wal`, `.db-shm`), and
  they belong together.
- **Never back the database up by copying the `.db` file.** The copy would
  miss whatever is still in the log. The site asks SQLite itself for a clean
  copy instead (Part 7).

The schema is built by the migrations in `priv/repo/migrations/`, in order.
In a release they run automatically at boot, before the site starts answering.

What the tables hold:

| Tables | What |
|---|---|
| `audio_logs`, `audio_plays` | The captain's logs and their view counts |
| `rides`, `health_workouts` | Activities from Komoot, and the heart rate that goes with them |
| `exercises`, `exercise_logs` | The weights logged against exercises |
| `guestbook_entries`, `contact_messages` | Signatures and messages |
| `subscribers`, `newsletter_drafts` | The mailing list and its letters |
| `webmentions`, `webmentions_sent` | Citations received and sent |
| `analytics_hits` | One row per page view |
| `site_settings` | Key and value pairs: the few settings edited in the admin, and the state the machine keeps about itself (the last monitor pass, the last restore drill) |
| `oban_jobs`, `schema_migrations` | The job queue, and which migrations have run |

A handful of tables are left from earlier designs (`blog_posts`, `tags`,
`post_tags`, `media_items`, `recipes`, `workout_sessions` and a few more). They
are empty and nothing reads them. They are left alone because dropping a table
is the one kind of change the rollback script cannot take back.

Two privacy notes about what is stored. A page view keeps a keyed hash of the
visitor's address, not the address: enough to count a returning reader once,
not enough to say who it was. A guestbook signature does keep the signer's
address, for moderation.

### The files

Everything that is not in the database is a file, in one of three places.

**The vault**, `content/` in the checkout. An Obsidian vault of Markdown:

```
content/
├── blog/              one .md per post; the filename is the address
├── fitness/
│   ├── weekly/        one file per day of the week
│   ├── additional/    sessions that belong to no day
│   ├── modules/       reusable blocks a day is assembled from
│   ├── exercise-wiki/ one folder per muscle group, one .md per exercise
│   └── figures/       one .json per exercise: the poses its figure holds
├── emails/            the welcome letter and other mail templates
├── templates/         starting files for Obsidian (the only part in git)
├── about.md           the About page
└── about.json         the few facts about the author the code needs
```

**The negatives archive**, wherever `NEGATIVES_PATH` points. Part 3 drew its
top level. Inside one roll's folder:

```
roll048_2026-10-09_35mm_color/
├── 001.tiff …         the strip scans, at 300 dpi
├── frames.json        where each frame lies on each strip, and how it measured
├── frames/NN.png      finished prints, one per chosen frame
├── raw-frames/        the 1600 dpi scans those prints were developed from
├── holder.json        where each strip lay on the scanner glass
├── selects.json       which frames were proposed and which were chosen
└── roll.json          what the photographer knows: camera, film, place, date
```

**The uploads folder**, beside the database:

```
uploads/
├── staging/           a recording's source, until it is converted
├── logs/<slug>-<token>/   one folder per captain's log: video.mp4 or
│                          audio.m4a, and poster.jpg
├── images/            the blog's image library
└── figures/           the exercise films, and clips.json which says
                       which film belongs to which figure
```

A file under `uploads/` never changes once written. A recording that is
converted again gets a *new* folder with a new token, and the database row is
pointed at it. That is what makes the one-year cache header honest.

### Configuration: three layers and one rule

Settings come from three places, and which place decides when a change takes
effect.

**1. Compile-time config**: `config/config.exs`, then one of `dev.exs`,
`test.exs` or `prod.exs`. These are read when the code is compiled and baked
into the build. The scheduler's table, the job queues, the build tools'
versions and "send the session cookie over HTTPS only" live here. Changing one
means building again.

**2. Runtime config**: `config/runtime.exs`. It is evaluated every time the
application boots, and it is where environment variables are read. So a changed
*value* in the environment needs only a restart. The file itself is copied
into the release when the release is built, so an edit to `runtime.exs` is a
code change like any other and needs a deploy.

**3. The environment**, which comes from two places that are merged when the
service starts:

- **`.env`** in the checkout holds what must not be published: secrets, and
  settings that belong to this particular host. It is not in git, and its
  permissions are owner-only. `.env.example` lists every variable.
- **The unit file** holds *where things are*: the database, the uploads, the
  backups. It exports those paths *after* reading `.env`, so the unit always
  wins. This is deliberate. The service once came up serving the development
  database because a stale line in `.env` quietly overrode the unit.

**The one rule: a missing secret refuses to start.** `runtime.exs` raises at
boot when `DATABASE_PATH`, `SECRET_KEY_BASE`, `ADMIN_PASSWORD` or
`RESEND_API_KEY` is absent. A site that will not start is found in seconds. A
site quietly running without its mail key is found weeks later.

The variables, and where each is set:

| Variable | Set in | Needed | What it is |
|---|---|---|---|
| `SECRET_KEY_BASE` | `.env` | Yes | Signs the session cookie and everything else that is signed. Make one with `mix phx.gen.secret` |
| `ADMIN_PASSWORD` | `.env` | Yes | The one password |
| `RESEND_API_KEY` | `.env` | Yes | Sends the welcome letter, the newsletter and the site's mail to its owner |
| `DATABASE_PATH` | unit | Yes | The live SQLite file |
| `PHX_SERVER` | unit | Yes | Without it a release starts and listens to nothing |
| `PHX_HOST` | unit, `.env` | | The public hostname |
| `PORT` | unit, `.env` | | The local port, 4000 |
| `UPLOADS_PATH` | unit | | Where recordings, images and films are written. Must be outside the release |
| `RIDE_THUMBS_PATH` | unit | | Where cached route pictures are kept. Outside the release too |
| `BLOG_PATH` | unit | | The posts' folder. Without it a release looks inside itself and the blog is empty |
| `FITNESS_PATH` | unit | | The fitness vault. The same |
| `BACKUP_PATH` | unit | | Where database snapshots land |
| `CONTENT_BACKUP_PATH` | unit | | Where versions of the writing land |
| `BACKUP_MIRROR_PATH` | unit | | The snapshots' folder on the external drive |
| `CONTENT_MIRROR_PATH` | unit | | The content versions' folder on the drive |
| `PHOTOS_MIRROR_PATH` | unit | | The negatives' folder on the drive |
| `UPLOADS_MIRROR_PATH` | unit | | The recordings' folder on the drive |
| `MONITOR_UNITS` | unit | | Which systemd units the monitor expects to find running |
| `NEGATIVES_PATH` | `.env` | | The photo archive |
| `KOMOOT_EMAIL` | `.env` | | With `KOMOOT_PASSWORD`, the Komoot login. The hourly sync stays off without them |
| `RIDE_PRIVACY_ZONES` | `.env` | | The places no ride may be shown near |
| `HEALTH_WEBHOOK_TOKEN` | `.env` | | For the phone app that posts workouts. One can be made in the admin instead |
| `SCANNER_AREA_35MM` | `.env` | | Where the 35mm film holder sits on the glass. `SCANNER_AREA_120` is the same for medium format |
| `SCANNER_DEVICE` | `.env` | | Which scanner to use, when more than one is attached |
| `NOTIFY_EMAIL` | `.env` | | Where the site writes to its owner, if no address is set in the admin |
| `AUTHOR_NAME` | `.env` | | The author's name, for search engines. Unset, nobody is named |
| `MACHINE_NAME` | `.env` | | What the `/pc` terminal calls itself |
| `REL_ME_URLS` | `.env` | | Profiles elsewhere that should verify this domain as theirs |
| `EXCLUDED_IPS` | `.env` | | Addresses whose visits are not counted |
| `POOL_SIZE` | either | | Database connections. Five by default |

A few settings are neither code nor environment: they are rows in the
`site_settings` table, edited at `/admin/settings`, and take effect on the
next request with nothing restarted.

### Programs the site runs

The application does not do everything itself. For work that an existing tool
does well, it starts that tool as a child process and reads what it prints.

| Program | Used for | Called from |
|---|---|---|
| `ffmpeg`, `ffprobe` | Converting recordings to one MP4 or M4A, cutting the trim, drawing the poster or waveform. Run under `nice` so an encode never starves the site | `Web.Media.FFmpeg` |
| `magick` (ImageMagick) | Web-sized copies of contact sheets and frames, share cards, and the cutting and measuring the scanner page does | `Web.Negatives`, `Web.ShareCard`, `Web.Scanner.*` |
| `scanimage` (SANE) | Driving the flatbed scanner | `Web.Scanner.Driver`, `Web.Scanner.Bed` |
| `film-develop` | Finding frames on a strip, developing a scan into a print | `Web.Scanner.Pipeline` |
| `digital-contact-sheet-maker` | Assembling a contact sheet, through GIMP | `Web.Scanner.Pipeline` |
| `rsync` | Copying the negatives and the recordings to the external drive | `Web.Backup.Tree` |
| `unzip` | Reading an Apple Health export | `Web.Rides.AppleHealth.Export` |
| `df`, `systemctl` | The monitor's disk and service checks | `Web.Monitor.Probe` |

Each is found on the `PATH` the unit file sets, which is why that `PATH`
includes `~/.local/bin`. Each can also be pointed elsewhere by a config key
(`:ffmpeg_bin`, `:magick_bin`, `:scanimage_bin`, `:film_develop_bin` and so
on), and that is how the test suite swaps every one of them for a small stub
script: no test encodes a video, drives a scanner or starts GIMP.

One rule holds across all of them: **nothing stands in for a missing tool.**
If `film-develop` fails, the page says so and stops. An earlier version
invented frame positions when the tool was missing, and put the marks on the
public contact sheets in the wrong place. A plain error is better than a
plausible lie.

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
nothing. The same goes for icons: an icon exists only if its name is on the
list at the top of `assets/css/app.css`. One that is not on the list renders as
an empty square, with no error anywhere.

### The mobile app and offline caching

The site is an installable **Progressive Web App (PWA)**:
- Adding it to a phone's home screen installs it as a standalone app with its own icon, running full-screen without the browser's address bar.
- A service worker (`priv/static/sw.js`) keeps the icons on the device from the start. A page is always fetched from the network first and a copy kept, so a page you have already opened can still be shown when the connection drops. Stylesheets, scripts, fonts and images are answered from the device first and refreshed in the background.
- WebSocket connections (`/live`) and the admin (`/admin`) bypass it entirely, so a live page is never answered from a cache.

### Discoverability and search engines

Every public page carries structured Schema.org metadata (JSON-LD) identifying:
- The site and its author (`Person` and `WebSite`). The author's name comes from `AUTHOR_NAME`; unset, no author is named.
- Writing as full `BlogPosting` entries with dates, headlines and breadcrumb trails.
- Captain's logs as `AudioObject` or `VideoObject` entries with runtimes, poster artwork and file addresses.
- The About page as a `ProfilePage`, with a job title and employer only when the vault's `about.json` gives them.
- A sitemap (`/sitemap.xml`) built at request time with real dates.

`robots.txt` asks the large-model crawlers to stay away, and Caddy refuses the
ones that announce themselves, whatever they were asked.

---

## Part 6: How it is run

Part 5 was the anatomy. This part is the daily life: what keeps the site up,
what a deploy does in what order, how to look inside the running thing, and
what to check first when something is wrong.

### The two units

**systemd** is the part of Linux that starts programs and keeps them running.
Each program it manages is described by a small text file called a **unit**.
The site has two, and they are *user* units: they belong to an ordinary
account, not to root, which is why every command below has `--user` in it.

| Unit | Runs | Listens on |
|---|---|---|
| `caddy-streetscissors.service` | `caddy run --config Caddyfile`, from the checkout | 80 and 443, all interfaces |
| `streetscissors.service` | the release's `bin/web start` | 4000, loopback only |

Both say `Restart=always` with a five-second pause, so a crash is followed by
a fresh start without anyone doing anything. Both are `WantedBy=default.target`
and the account has **lingering** switched on (`loginctl enable-linger`), which
together mean they start when the machine boots, whether or not anybody logs
in. Without lingering, user units stop when the last session closes.

The application's unit is worth reading once, because it is where the
environment is assembled. Its start line does three things in order:

```
set -a; . ~/streetscissors/.env; set +a      # 1. every line of .env becomes an environment variable
export DATABASE_PATH=…/streetscissors.db     # 2. then the paths, so nothing in .env can override them
export UPLOADS_PATH=…/uploads
…
exec ~/streetscissors/_build/prod/rel/web/bin/web start     # 3. become the release
```

`set -a` is the shell's "export everything I define from here on". `exec`
replaces the shell with the release, so systemd is watching the real process
and not a wrapper around it.

The installed unit files live in `~/.config/systemd/user/`. Copies are kept in
the repository under `ops/systemd/`, written with systemd's `%h` (the home
directory) and `%u` (the user's name) in place of the real ones, so that no
home directory is written into a public repository. To change a unit:

```
cp ops/systemd/*.service ~/.config/systemd/user/
systemctl --user daemon-reload
```

`daemon-reload` only makes systemd read the files again. Nothing restarts, and
the change applies from the next restart.

The commands you will actually type:

| Command | What it does |
|---|---|
| `systemctl --user status streetscissors` | Is it running, since when, and its last few log lines |
| `systemctl --user restart streetscissors` | Stop it and start it. A few seconds of 502 from Caddy |
| `systemctl --user stop streetscissors` | Stop it and leave it stopped |
| `systemctl --user reload caddy-streetscissors` | Make Caddy read the `Caddyfile` again, without dropping connections |
| `journalctl --user -u streetscissors -f` | Follow the application's log. Ctrl-C to stop following |
| `journalctl --user -u streetscissors -n 100` | The last hundred lines |
| `journalctl --user -u caddy-streetscissors` | Caddy's own log: certificates, startup, proxy errors |

`journalctl` also takes a window of time: add `--since "1 hour ago"`, or
`--since today`.

One caution about restarting by hand: a restart kills a scan that is running
on the flatbed and the run of singles behind it. The deploy script waits for
the scanner. `systemctl restart` does not.

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

### What needs a deploy, and what does not

This is the question that comes up most, so here is the whole answer.

| You changed | What it takes to go live |
|---|---|
| A post, a regimen file, a wiki page, this manual | Nothing. Save the file |
| A roll of film, a new single frame | Nothing. The archive is read on each request |
| An exercise's film | `mix fitness.film` (Part 8). No deploy |
| A setting at `/admin/settings` | Nothing. It is a row in the database |
| A value in `.env` | `systemctl --user restart streetscissors` |
| A path in the unit file | `daemon-reload`, then a restart |
| The `Caddyfile` | `systemctl --user reload caddy-streetscissors` |
| Code: `lib/`, `assets/`, `config/`, `priv/` | `./redeploy.sh` |
| A database migration | `./redeploy.sh`. It runs at the next boot |

### A deploy, step by step

```
./redeploy.sh
```

That is the whole command, and it should not be replaced with anything
shorter. Here is what it does, in order, and why each step is where it is.

**1. Build the assets.** `mix assets.deploy` compiles the Elixir code, runs
Tailwind and esbuild with minification, removes JavaScript chunks no longer in
use, and then **digests**: every file in `priv/static` gets a copy with a
fingerprint of its contents in its name (`app-3f9c….css`), and a manifest that
maps plain names to fingerprinted ones. Pages link to the fingerprinted names,
so a browser can cache them for ever and a new build is a new name.

This comes first because a release packs `priv/` into itself. Assets built
after the release change the checkout and not the thing being served.

**2. Keep the release that is serving.** If the site answers on
`localhost:4000`, the current release directory is copied aside, to
`web.previous` beside it. That copy is what `./rollback.sh` returns to.
It is taken only while the site is answering: if the last deploy is what broke
it, the copy already kept is the good one, and a second attempt must not
replace it with the broken one.

**3. Build the release.** `mix release --overwrite` rebuilds
`_build/prod/rel/web/` in place. The old program is still running at this
point, from memory, on files that have just been replaced under it.

**4. Wait for the scanner.** The script asks the running site whether the
flatbed is busy, every five seconds, and holds the restart until it is not. It
gives up after fifteen minutes and says so: the new release is built but not
started, and the thing to do is run the script again when the scanner is free.
The question
is asked through the *kept* copy of the old release, because the build in step
3 replaced the secret (the release's **cookie**) that lets one release talk to
another.

**5. Restart.** `systemctl --user restart streetscissors`. The old program
stops, the new one boots: it migrates the database if there is anything to
migrate, starts its tree, and begins answering. Caddy answers 502 for the few
seconds in between.

**6. Prove it.** The script will not call the deploy a success until it has
checked five things, each of which once went wrong without any error:

| Check | What is asked | The failure it exists for |
|---|---|---|
| It is up | The homepage answers 200 within a minute | The release did not boot: a missing secret, a bad migration |
| `/dev` is shut | The dashboard and the mail preview answer 404 | The developer tools were once reachable by anyone on the internet |
| Fresh styles | The stylesheet being served is byte for byte the one on disk | A months-old compressed copy once shadowed the real file, and the site wore last season's design for weeks |
| Hooks are in | Every colocated hook is named in the JavaScript being served | Bundled before compiling, the script ships without them: the page renders and its buttons are dead |
| Real data | A page that needs the database shows rows | A wrong `DATABASE_PATH` makes SQLite create an empty file, and the site comes up looking wiped instead of failing |

If any check fails, the script says which, prints the service's status, and
names the way back.

### Taking a deploy back

```
./rollback.sh
```

It stops the service, swaps `web` and `web.previous`, and starts the service
again. Nothing is compiled, so it takes as long as a restart. Run it a second
time and the newer release is back: it is a swap, not a one-way door.

What it does **not** do matters as much:

- **It does not touch the checkout.** The source is still the newer code.
  Fix it forward or `git revert`, then deploy as usual.
- **It does not undo a migration.** The older release boots against the
  database as it now is. A table or column that was *added* is harmless to
  code that does not know about it. One that was dropped or renamed is not,
  and for that the answer is a snapshot (Part 7), not this script.
- **It does not change content.** Posts and photographs are files, read by
  whichever release is running.

### Migrations

A **migration** is a small Elixir file in `priv/repo/migrations/` that changes
the shape of the database: add a table, add a column. They are numbered by
timestamp and each runs once, in order; the `schema_migrations` table records
which have run.

- Make one with `mix ecto.gen.migration name_in_snake_case`, never by hand, so
  the timestamp is right.
- In development and in tests you run them (`mix ecto.migrate`, or `mix test`
  does it for the test database). In production nobody runs them: the release
  does, at boot, before it starts answering.
- **Prefer migrations that only add.** An additive migration keeps
  `./rollback.sh` safe, because the previous release ignores what it does not
  know about.
- The deploy script builds whatever is in the working tree, committed or not.
  So a half-written migration must never be left lying in the checkout.

To take one migration back by hand, with the service stopped:

```
_build/prod/rel/web/bin/web eval 'Web.Release.rollback(Web.Repo, 20260101120000)'
```

where the number is the version to return *to*.

### Looking inside the running site

The release's start script is `bin/web`, inside the release directory. It has a
few commands besides `start` and `stop`, and two of them reach into the
program that is already running.

**`rpc`** runs one expression inside the live application and prints what it
prints:

```
_build/prod/rel/web/bin/web rpc 'IO.inspect(Web.Scanner.Bed.status())'
_build/prod/rel/web/bin/web rpc 'IO.inspect(Web.Monitor.last())'
_build/prod/rel/web/bin/web rpc 'IO.inspect(Web.Backup.run())'
```

**`remote`** opens an interactive Elixir prompt inside it. Everything typed
there happens to the live site, to the live database. Leave with Ctrl-C twice,
which closes the prompt and leaves the site running.

```
_build/prod/rel/web/bin/web remote
```

Both work because Erlang programs can talk to each other, and both are
guarded by a shared secret, the **cookie**, kept in a file inside the release
directory. A program that does not know the cookie is not answered.

For anything that does not need the live application at all (calling a pure
function, trying a parser), run it from the checkout without starting the app:

```
mix run --no-start -e 'IO.inspect(Web.Keywords.slugify("New York"))'
```

**On the server itself, never start a development copy to poke at something.**
The machine that serves the site is also the machine the code is edited on.
`mix phx.server` there would be a second copy of the application, reaching for
the same port, with its own scheduler and its own idea of where things are.
`rpc`, `remote` and `mix run --no-start` cover every case without it.

### Logs

| Where | What is in it |
|---|---|
| `journalctl --user -u streetscissors` | Everything the application logs, at `info` level and above: one line per request with its id and timing, warnings, crashes with stack traces, the scheduler's jobs |
| `journalctl --user -u caddy-streetscissors` | Caddy starting and stopping, certificate issue and renewal, errors reaching the application |
| `caddy_access.log` in the checkout | One JSON line per request Caddy served, including the media files the application never sees. Caddy rotates and compresses it |
| `erl_crash.dump` in the checkout | Written if the Erlang VM itself dies, usually at boot. Its first lines say why |

Passwords and contact details are filtered out of the request log
(`filter_parameters` in `config/config.exs`).

### Certificates, the domain and the house's address

**Certificates are Caddy's job and need no attention.** It asks Let's Encrypt
for one the first time it sees the domain in its config, keeps it in
`~/.local/share/caddy/`, and renews it when a third of its life is left. For a
renewal to work, port 80 or 443 has to reach the machine from the internet. If
a renewal ever stops working, the monitor says so when 21 days are left and
calls it a fault at 14.

**The domain is set by hand.** The registrar's control panel has no API, so
nothing here can update it. The monitor asks public DNS servers two questions,
where the domain points and what address the house appears as from outside,
and if the answers differ it writes with the value to type into the panel.

**By address, on the home network.** The `Caddyfile` has a second site block
for the machine's private addresses, signed by Caddy's own certificate
authority, since no public authority will issue a certificate for a private
address. A browser will warn that it does not know the issuer, which is true.
Live pages will not connect there (Part 5, the socket's origin check), so it
is only good for a quick look.

### After a reboot

Nothing needs doing. In order, by themselves:

1. systemd starts both units, because the account lingers.
2. The release migrates the database if needed and starts its tree.
3. `Web.Backup.catch_up/0` takes any backup the machine slept through.
4. The transcoder picks up any recording whose conversion was interrupted.
5. `Web.Warm` reads what the first visitor would otherwise wait for.

The one thing a reboot does not bring back by itself is the external drive, if
it needs a login to be mounted. Until it is there, the copies to it are
skipped, which is logged and is not an error.

### When something is wrong

Each entry is what you see, where to look, and what it usually is.

**The browser says 502.** The application is down or still booting. Look at
`systemctl --user status streetscissors`, then at its log. If it will not
boot, the log's last lines name the reason: a missing variable, a migration
that failed.

**Nothing answers at all.** Caddy is down, or the house is offline, or the
router stopped forwarding. `systemctl --user status caddy-streetscissors`. If
Caddy says it cannot open its log, see the `site up` note above.

**A certificate warning.** A renewal is failing, almost always because port 80
or 443 no longer reaches the machine. Caddy's log says what it tried, and the
admin overview shows how many days are left.

**The site is up but looks emptied: no rides, no logs.** `DATABASE_PATH` in the
unit points somewhere new, and SQLite made an empty database there.

**The blog or the regimen is empty and everything else is fine.** `BLOG_PATH`
or `FITNESS_PATH` is not set, and the release is looking inside itself.

**A page looks unstyled in places after a deploy.** A tab left open across the
deploy. It reloads itself the next time it connects; reloading by hand does the
same.

**Buttons on a page do nothing, and the browser console says "unknown hook".**
The JavaScript was bundled before the Elixir was compiled. Run `./redeploy.sh`
again.

**A new icon is an empty square.** Its name is not on the allowlist at the top
of `assets/css/app.css`.

**The scanner page says the scanner is busy and nothing moves.** Ask the bed
directly:

```
_build/prod/rel/web/bin/web rpc 'IO.inspect(Web.Scanner.Bed.status())'
```

A scan that outlives fifteen minutes is killed.

**`./redeploy.sh` stops at "the scanner has been busy".** It will not restart
under a scan. Wait, and run it again.

**Mail is not arriving.** The admin overview's mail queue says whether letters
are failing. The usual causes are the Resend key and the provider being
unreachable; queued mail is retried.

**Rides have stopped arriving.** The admin overview, under Komoot. The login
failed, or Komoot changed something on its side.

**The disk is filling.** `df -h ~`, then `du -sh` on the folders listed in
Part 5. The negatives archive and the recordings are the only things that grow
without limit.

---

## Part 7: Keeping it safe

Three things protect the site: copies of everything that cannot be made again,
a machine that checks itself and says when something is wrong, and a short list
of things it refuses to do.

### What is backed up, and how

Four kinds of thing, each kept the way that suits it.

| What | How | How many | Where |
|---|---|---|---|
| The database | Every night SQLite is asked to write a clean copy of itself (`VACUUM INTO`). The copy is reopened and integrity-checked before it counts | The newest 14 | `db/` in the backups folder |
| The writing | The vault and the few private files beside the code are packed into one archive. The archive is unpacked again and every file's hash compared with the original | The newest 30 *versions* | `content/` in the backups folder |
| The negatives | Copied to the external drive with `rsync` | Everything, for ever | The drive |
| The recordings | Copied to the external drive with `rsync` | Everything, for ever | The drive |

The backups folder is `~/streetscissors-backups/`. A snapshot is named for the
moment it was taken, `web-YYYYMMDD-HHMMSS.db`, and a content version for the
moment and for a fingerprint of what is in it.

A few choices in there are deliberate, and worth knowing before changing any
of it.

**The database is never copied as a file.** Part 5 explained why: in WAL mode
the newest writes are in a second file, and a plain copy of the first one is
silently stale or torn. `VACUUM INTO` asks SQLite for a complete, consistent
copy through the connection the site already has open.

**A backup is not trusted until it has been read back.** A file of the right
size is evidence of nothing. Each database snapshot is opened and checked; each
content archive is unpacked and compared hash for hash. A bad copy is reported
the night it is written, not discovered the day it is needed.

**A content version is written only when something changed.** Each night every
file is fingerprinted, and if the fingerprint matches the newest archive
nothing is written. So thirty kept means thirty *versions*, not thirty nights:
a paragraph deleted in August is still recoverable in October, however quiet
September was. `.env` is deliberately not in the archive: the drive is not
encrypted, and a password can be reissued where a paragraph cannot.

**The copies on the drive never delete.** `rsync` runs without `--delete`. A
backup that faithfully copies your deletions reproduces exactly the accident it
exists to protect you from.

**The drive's absence is not an error.** The application never creates the
top-level backup folders on the drive: their presence *is* the signal that the
drive is plugged in, and creating them would quietly write the "off-disk" copy
onto the same disk. Make the folders once, on the drive. After that, plugging
the drive in is all it takes: `Web.Backup.MirrorWatcher` checks every thirty
seconds whether the folder has appeared, and copies everything across the
moment it does.

**A restore is rehearsed every week.** On Sunday the newest snapshot is copied
to a scratch file and opened, integrity-checked, and has every table read end
to end; the newest content archive is unpacked and its fingerprint recomputed.
The copies on the drive get the same reading when the drive is in. The result
is shown on the admin overview, and a failed rehearsal is mailed like any other
fault. A backup that has never been restored is a hope.

**What is not backed up, on purpose or otherwise:**

- `.env`. Keep a copy of it somewhere that is not this machine.
- The code. It is in git and on GitHub.
- The release and everything under `_build/`. It is rebuilt by a deploy.
- Ride thumbnails. They are fetched again.
- Caddy's certificates. They are issued again.
- **The darkroom tools** in `~/.local/bin` and the GIMP script they drive.
  They are not part of this repository and not in these backups, and they
  need a copy of their own.

### Getting something back

**The database.** Choose a snapshot, then, with the site stopped:

```
systemctl --user stop streetscissors
cd ~/streetscissors-data
mkdir set-aside && mv streetscissors.db* set-aside/
cp ~/streetscissors-backups/db/web-YYYYMMDD-HHMMSS.db streetscissors.db
systemctl --user start streetscissors
```

The `*` on the second line matters: it moves the `-wal` and `-shm` files away
with the database they belong to. Left behind, they would be applied to a
database they were never written for. A snapshot older than the current code
is fine; the release migrates it forward as it boots. Before you restore, a
snapshot can be inspected without touching anything:

```
sqlite3 -readonly ~/streetscissors-backups/db/web-YYYYMMDD-HHMMSS.db 'select count(*) from rides'
```

**A piece of writing.** Unpack a version somewhere out of the way and copy
back the file you want. Do not unpack over the vault: that would also undo
every edit made since.

```
mkdir ~/restore
tar -xzf ~/streetscissors-backups/content/content-….tar.gz -C ~/restore
```

A file deleted or overwritten through the admin's editor is often nearer than
that: it is in the vault's `.trash` folder.

**The negatives or the recordings.** They are plain folders on the drive, laid
out exactly like the originals, so the way back is the same command pointed the
other way:

```
rsync -a /path/to/drive/streetscissors-backups/negatives/ ~/Pictures/Negatives/
```

**The whole site, on a new machine.** In the order that works:

1. Install Erlang, Elixir, Caddy, ffmpeg, ImageMagick and SQLite. For the
   darkroom: SANE (`scanimage`), GIMP and the tools in `~/.local/bin`.
2. Clone the repository to `~/streetscissors`. Put `.env` back.
3. Restore `content/` from a content archive, the database and `uploads/`
   into `~/streetscissors-data/`, and the negatives archive.
4. Add the sysctl line that lets an ordinary user bind port 80 (Part 5).
5. Copy the units from `ops/systemd/`, `daemon-reload`, enable both, and
   switch lingering on.
6. `mix deps.get` and `mix assets.setup` (which fetches the two build
   tools), then `./redeploy.sh`.
7. Point the router's ports 80 and 443 at the new machine, and the domain at
   the house if the address changed. Caddy fetches a certificate by itself.

### The machine watching itself

A site in a house has faults no visitor reports. A certificate stops renewing
and nothing changes for weeks. The provider hands the house a new address and
the domain goes on pointing at the old one. So every fifteen minutes
`Web.Monitor` checks, and compares what is failing now with what was failing
last time.

| Check | What it asks | A warning when | A fault when |
|---|---|---|---|
| Certificate | Connects to the site as a browser would and reads the certificate's expiry | Under 21 days left | Under 14 |
| Front door | `GET /health` on the site's own name, through Caddy | | It does not answer |
| DNS | Where public resolvers say the domain points, against the house's address as seen from outside | The lookup could not be made | They differ |
| Disk | Free space | Under 10% | Under 5% |
| Units | Whether the systemd units named in `MONITOR_UNITS` are active | | One is not |

Those five reach outside the application, and cost a network handshake or a
child process each. The same pass also reads the checks the admin overview
already makes, which cost nothing: how old the newest snapshot and the newest content
version are, whether the drive's copies are current, how the last restore
rehearsal went, when Komoot last answered, whether any ride showed too much,
and whether mail is piling up unsent. What the pass found is stored in one row
of `site_settings`, and the overview reads that row, so opening the admin never
makes a network call.

**It tries hard not to cry wolf.** Only a fault is ever mailed; a warning is
for the overview. A check has to fail on two passes in a row before a word is
sent, so one dropped packet is not an alarm. After that it is mentioned once,
once more each day it stays broken, and once when it clears. A check that could
not be made at all (no route to a DNS server, say) is a warning, never a fault:
a wifi blip must not be reported as the site being down.

**Where it writes to** is the address under Settings, Alerts, in the admin, or
`NOTIFY_EMAIL` as a fallback. With neither set nothing is sent, and the
overview says there is nowhere to write to. The mail is a queued job, so one
written while the network is down is retried: a fault is exactly when the
network is least to be trusted.

**What it cannot see.** It runs on the machine it watches, so it is silent
about exactly the faults that silence it: the power is out, the machine is off,
the house has no internet. Those can only be seen from somewhere else.

**The check from outside** is that somewhere else. `uptime.yml`, in the
repository's `.github/workflows/` folder, is a GitHub Actions workflow that
asks the site's `/health` address twice an hour, three tries a minute apart so
a deploy's restart is not reported as an outage, and GitHub mails the
repository's owner when a run fails.
`/health` answers 200 only when the proxy, the application and the database are
all standing, and says nothing else. Two things about GitHub's side are easy to
miss: a scheduled workflow runs only from the repository's **default branch**,
and GitHub switches a schedule off after sixty days without a commit (it mails
a warning first, and the workflow's page has a button to turn it back on).

### What is refused, and where

**Plain HTTP.** Caddy redirects it, and tells browsers to refuse it for a year.
The session cookie is never sent over it.

**Requests from around the proxy.** The application listens on loopback only.

**A forged form.** Every form a browser posts carries a token tied to the
session; a post without it is refused. A live page's socket is accepted only
from a page served under the site's own name.

**Guessing.** Counted per address, in fixed windows, in memory (so a restart
clears the counts):

| What | How many |
|---|---|
| Admin login attempts | 10 in 15 minutes |
| Newsletter sign-ups | 3 an hour |
| Guestbook signatures | 3 an hour |
| Letters under a piece | 3 an hour |
| Contact messages | 5 an hour |
| Grammar checks | 20 an hour |
| Searches | 30 a minute |
| Webmentions received | 20 an hour |
| Workouts posted by the phone | 60 an hour |

The public write forms also sit behind a small hand-made puzzle rather than a
third-party captcha.

**The developer tools.** Phoenix's dashboard and mail preview are compiled
only into a development build, are behind the admin check even there, and the
deploy script fails if either answers on the live site. Three locks, because
one of them has failed before.

**Scrapers.** `robots.txt` asks the large-model crawlers to stay away, and
Caddy answers 403 to the ones that name themselves.

**Home.** A ride that would show where the house is has its map withheld
(Part 4). The place is known to the site only through `RIDE_PRIVACY_ZONES`.

**Anything personal in the code.** The repository is public and holds the
site's skeleton only. The writing, the photographs, the author's name, the
places: all of it lives in `content/` or `.env`, which git ignores, and the
code reads it at run time with a neutral fallback, so that a fresh clone still
builds, boots and passes its tests. This is a rule for changing the site, not
only a fact about it: a detail about a person goes in the vault or in `.env`,
never in a source file.

---

## Part 8: Changing it

How to work on the code without breaking the site that is running from it.

### Where things are in the repository

```
streetscissors/
├── lib/web/            the thinking: content, photos, rides, mail, backups
├── lib/web_web/        the web layer: router, pages, live pages, components
├── lib/mix/tasks/      commands of the project's own (mix fitness.film)
├── assets/css/         the design, hand written, one sheet per section
├── assets/js/          the small amount of browser code
├── config/             settings for development, test and production
├── priv/repo/          database migrations
├── priv/static/        files served as they are: fonts, icons, robots.txt
├── priv/figure/        the camera that films the exercise figures
├── test/               the tests, their fixtures and their stand-in tools
├── docs/               this manual, and the darkroom's technical notes
├── ops/systemd/        the two unit files that run the site
├── content/            the Obsidian vault (not in git, apart from templates)
├── Caddyfile           the front proxy's configuration
├── redeploy.sh         the deploy
└── rollback.sh         the way back
```

The convention: `lib/web/` is the part that would still make sense if the
website were replaced by something else, and `lib/web_web/` is the website
itself. A function that reads a roll of film off the disk belongs in the first;
the page that shows it belongs in the second.

Two files at the top are for whoever writes code here, person or machine.
`CLAUDE.md` is the map of the non-obvious wiring: why each odd thing is the way
it is. `AGENTS.md` is Phoenix and LiveView house style.

### Three places the same code runs

| | Development | Test | Production |
|---|---|---|---|
| Started by | `mix phx.server` | `mix test` | systemd |
| Config file | `dev.exs` | `test.exs` | `prod.exs`, plus the environment |
| Database | `web_dev.db` | `web_test.db` | Outside the checkout |
| Content | The vault | Invented fixtures | The vault |
| Reloads on save | Yes | | No: a change is a deploy |
| Migrations | You run them | Run for you | Run at boot |
| Tools at `/dev` | Behind the admin check | | Compiled out |
| Other programs | The real ones | Stubs | The real ones |

On an ordinary computer, development is the usual Phoenix loop: start the
server, edit, refresh. Elixir and templates reload by themselves. Stylesheets
are the exception worth remembering: if a CSS change does not appear, run
`mix assets.build`.

On the server itself the loop is different, because the development server
cannot run beside the live site (Part 6). There the loop is: edit, `mix test`
for the part you touched, `mix precommit`, then `./redeploy.sh`.

### The gate

```
mix precommit
```

It runs four things, and all four must pass:

1. `compile --warnings-as-errors`. An unused variable, a call to a function
   that does not exist, a clause that can never match: each stops the build.
2. `deps.unlock --unused`. Drops dependencies that are locked but no longer
   asked for.
3. `format`. Rewrites the code into the one standard layout.
4. `test`. The whole suite.

If it passes, the change is done. If it does not, it is not.

### The tests

About 1,360 of them, and they run in a little over a minute. `test/web/` tests
the thinking (one file per module, more or less), `test/web_web/` tests pages
by asking for them the way a browser would, and `test/support/` holds what
both need.

The suite's first rule is that **it never touches anything real**:

- The vault, the trip notes, the mail templates and the negatives archive are
  replaced by small invented ones in `test/support/fixtures/`.
- `ffmpeg`, `ffprobe`, ImageMagick, `scanimage`, `film-develop`, the contact
  sheet maker and the figure camera are replaced by stub scripts in
  `test/support/`. The scanner is a simulation.
- Backups go to a temporary folder. The monitor's checks take their outside
  world as arguments, so no test opens a socket.
- Nothing is mailed, and nothing is posted to another site.

That is what lets the suite run on the machine that serves the site, and on a
fresh clone that has none of the author's content.

A few tests exist to hold a *rule* rather than a function, and are worth
knowing by name:

- `search_test.exs` walks the router and fails if a public page cannot be
  found by the site's own search. Add a page and forget the search, and this is
  what tells you.
- `speed_test.exs` pins the things that made the site fast: fonts served from
  here, pages prefetched but never prerendered, a prefetch not counted as a
  view.
- The page tests for `/how-to` check that this file still renders, that its
  contents list points at headings that exist, and that it has a table in it.

There is also `test/private/`, which git ignores. Those tests read the
author's real content and hold it to the same shape the code expects: every
exercise page has its sections, every contact sheet's marks land on its
frames. They run with the rest when the content is there.

```
mix test                                   everything
mix test test/web/blog_test.exs            one file
mix test test/web/blog_test.exs:42         one test, by line number
mix test --failed                          only what failed last time
```

### The front end build

No Node.js is involved. `mix` fetches two standalone programs, Tailwind and
esbuild, and runs them.

**CSS.** `assets/css/app.css` is the entry point. It defines every colour and
typeface as a token in one `:root` block, then imports about thirty hand-written
sheets, one per section (`negatives.css`, `admin.css`, `header.css` and so on).
Tailwind is imported with `source(none)`, which means it scans no files and so
generates no utility classes. It is there for two things only: the handful of
utilities named in the `@source inline(...)` lines at the top of that file, and
the icons. Both are allowlists. A class or an icon that is not named there does
not exist.

**JavaScript.** `assets/js/app.js` is the entry point, and esbuild bundles it
with everything it imports into `priv/static/assets/js/`. Only that bundle and
the one stylesheet are ever served, so a library has to be imported into them;
a `<script src>` pointing somewhere else is not how this site loads code.

**Colocated hooks, and why the order matters.** A LiveView component can carry
its own browser script, written in the same file as its markup. When Elixir
*compiles*, those scripts are extracted into `_build/`, and esbuild then picks
them up from there. So Elixir must be compiled before JavaScript is bundled.
The `assets.build` and `assets.deploy` aliases in `mix.exs` both begin with
`compile` for exactly this reason. Run esbuild alone on a fresh checkout and
the bundle ships without any hooks: every page renders, and nothing on it
responds.

**Digesting.** In production each asset is served under a name that contains a
fingerprint of its contents, and the template helper `~p"/assets/css/app.css"`
looks the fingerprinted name up in `cache_manifest.json`. That is
why assets must be built before the release (the manifest is packed into it),
and why a stale manifest is so quiet a failure: it points, correctly, at the
previous build.

**Fonts** are served from `priv/static/fonts/`, not from Google. The root
layout preloads the two files the header draws with.

**Compression** is Caddy's job. `Plug.Static` is told not to serve the `.gz`
copies that digesting leaves beside each file, because a second source of
compressed bytes is a second way to serve the wrong ones.

### Rules that hold the site together

Each of these is a convention the code already follows everywhere, and
breaking one tends to fail quietly rather than loudly.

- **Pages read tokens, never colour values.** `var(--ink)`, not a hex code.
  That is what lets one class re-ink a whole section.
- **The address is the whole state of a view.** Which roll is open, how the
  index is sorted, which day of the regimen is showing: all of it is in the
  URL, and every control is a link. That is what makes the browser's Back
  button, a reload and a shared link all work.
- **Every public page is in the search.** A page with no content of its own to
  list goes in the `@fixed` list in `lib/web/search.ex`: its title, its
  address, what it is, and other words someone might type for it.
- **Nothing personal in a source file.** It goes in `content/` or `.env`, and
  the code falls back to something neutral when it is absent.
- **A new admin page goes inside `live_session :admin`** in the router. That
  is the whole of its protection.
- **An external program is reached through a config key** (`:ffmpeg_bin` and
  its cousins), so the tests can put a stub in its place.
- **A file is written beside its target and renamed over it.** A reader never
  sees half a file, and a crash never leaves one.
- **No fallback invents data.** When a tool fails, say so. A wrong answer
  that looks right is worse than no answer.

### Small recipes

**Add a page.** Add a route in `lib/web_web/router.ex`, inside the `:browser`
scope. For a plain page, add an action to a controller and a template beside
the others. Give it a `page_title` and a `meta_description`. Add it to
`Web.Search`'s `@fixed` list, and to the list in `sitemap_controller.ex` if
search engines should find it. Its styles go in a sheet of its own under `assets/css/`, imported from
`app.css`.

**Add a setting the admin can change.** Read it with `get_setting/2` in
`Web.SiteSettings`, which takes a default, and add a field for it at
`/admin/settings`. No migration: settings are rows.

**Add a setting that comes from the environment.** Read the variable in
`config/runtime.exs` and store it with `config :web, :some_key, value`. Read it
in the code with `Application.get_env(:web, :some_key)`. Document it in
`.env.example`. If it is a path to data, export it from the unit file (and
from `start_prod.sh`), not from `.env`.

**Add something that runs on a clock.** Add a line to the `Web.Scheduler` job
list in `config/config.exs`, naming a function that takes no arguments. Make
that function catch its own errors and log them: a job that raises is simply
gone until the next tick, and nobody is told. Times are UTC.

**Change the database.** `mix ecto.gen.migration add_something`, write the
change, `mix ecto.migrate` to try it, and add the field to the schema module.
Additive changes only, if you want `./rollback.sh` to stay safe.

**Film an exercise's figure.** Write or edit the figure's `.json` in the
vault, then look at each pose before filming anything:

```
mix fitness.film --stills ~/somewhere plank
```

A file that passes validation is not thereby a picture of the exercise, so
look. Then film it into the live site's uploads:

```
UPLOADS_PATH=~/streetscissors-data/uploads mix fitness.film plank
```

It needs `node`, Chrome and `ffmpeg`, and takes a little under a minute a
figure. With no name it films every figure that has no current film, so if a
long run stops part way, run it again. Nothing is deployed: the page plays the
new film on its next load.

### Git, and what GitHub does and does not get

The repository on GitHub is the site's code and nothing else. `content/`, the
photographs, `.env` and the private tests are ignored, so `git push` cannot
publish them.

Two things about how git and the live site relate are easy to get wrong:

- **The deploy builds the working tree, not a commit.** Whatever is on disk
  when `./redeploy.sh` runs is what goes live, committed or not, on whatever
  branch. Committing is how the change is remembered; it is not what ships
  it. Keep the tree in a state you would be willing to deploy.
- **A push changes nothing on the live site.** There is no pipeline that
  deploys from GitHub. The only thing GitHub runs for this site is the uptime
  check (Part 7).

---

## Part 9: The shortcuts

Everything below is typed into a terminal, from inside the project folder unless
it says otherwise.

### Working on the site on your own computer

| Command | What it does |
|---|---|
| `mix setup` | First time only. Fetches everything, creates the database, builds the styles. |
| `mix phx.server` | Starts the site at http://localhost:4000. Stop it with Ctrl-C twice. |
| `iex -S mix phx.server` | The same, but with a prompt where you can talk to the running site. |
| `mix assets.build` | Rebuilds the CSS and JavaScript. Run this after editing a stylesheet. |
| `mix ecto.gen.migration name` | Starts a new database migration. |
| `mix ecto.migrate` | Runs the migrations that have not run yet. |

### Before you commit anything

| Command | What it does |
|---|---|
| `mix precommit` | The gate. Compiles with warnings treated as errors, checks for unused dependencies, formats the code, runs every test. |
| `mix test` | Just the tests. |
| `mix test test/web/blog_test.exs` | One file. |
| `mix test --failed` | Only what failed last time. |
| `mix format` | Tidies the code layout. |

### The live site

| Command | What it does |
|---|---|
| `./redeploy.sh` | Build and ship the code that is on disk. Waits for the scanner, then proves the result. |
| `./rollback.sh` | Swap the previous release back in. Run it again to swap forward. |
| `systemctl --user status streetscissors` | Is it running? |
| `systemctl --user restart streetscissors` | Restart it. Needed after changing `.env`. |
| `systemctl --user reload caddy-streetscissors` | Make Caddy read the `Caddyfile` again. |
| `journalctl --user -u streetscissors -f` | Watch the log as it happens. |
| `journalctl --user -u streetscissors -n 50` | The last fifty lines. |
| `curl -s localhost:4000/health` | Ask the application directly whether it and its database are up. |
| `_build/prod/rel/web/bin/web rpc '…'` | Run one expression inside the live site. |
| `_build/prod/rel/web/bin/web remote` | Open a prompt inside the live site. |
| `mix run --no-start -e '…'` | Run an expression from the checkout, without starting anything. |

### The darkroom

| Command | What it does |
|---|---|
| `negatives` | Scan a roll, start to finish |
| `negatives --list` | Which roll numbers are taken |
| `negatives --recompile 7` | Rebuild roll 7's sheet from the scans already there |
| `negatives --analyze 7` | Score every frame's exposure |
| `digital-contact-sheet-maker <folder>` | Build a sheet from any folder of scans |
| `mix fitness.film` | Film every exercise figure that has no current film |

Full details in Part 3, and for the films in Part 8.

### Things that look like shortcuts but are not

`./deploy.sh`, with the `Dockerfile` and `docker-compose.yml` beside it, builds
and runs the site in containers. It was tried and set aside long ago, and the
site has since grown a scanner, a film pipeline and a set of data folders it
knows nothing about. The live site does not use it and it should not be run on
the server.

`./start_prod.sh` starts the release by hand in a terminal, with the same
environment the unit gives it. It refuses to run while the unit is up. It is
for the rare case of wanting the release's output in front of you; it is not
how the site stays up.

`mix phx.server` on the server is not a shortcut either (Part 6).

---

## Part 10: Running your own copy

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
  in it is needed to start the site in development.

To run it for real, on a machine of your own, follow "The whole site, on a new
machine" in Part 7, leaving out the steps that restore data you do not have.

### A note on the licence

**The software is MIT licensed**; everything under `lib/`, `assets/`,
`config/`, `test/`, `priv/repo/`, `docs/`, and the scripts at the top level.
Take it, learn from it, build on it, sell it. This manual is included in that.

**The content is not in the repository at all.** The writing, the photographs,
the recordings and the training notes are all rights reserved, and they stay
on the machine that serves them. What you clone is the building with nothing
on the walls, which is the point: fill it with your own.

---

## Part 11: Glossary

**Backup**: Four things here, each kept its own way. The database is asked to
write a clean copy of itself every night, and the copy is reopened and checked
before it is trusted; fourteen are kept. The written content is packed into one
archive, unpacked again and compared file by file, and kept only if something
changed, so the thirty that are kept are thirty versions, not thirty nights.
The photograph archive and the recordings are copied to an external drive,
which also takes a copy of everything else within thirty seconds of being
plugged in. See Part 7.

**Bandit**: The HTTP server inside the application. It accepts the requests
Caddy passes on.

**BEAM**: The Erlang virtual machine, which runs Elixir. Built to keep many
small processes running and restart the ones that fail.

**Caddy**: The web server that faces the internet, holds the encryption
certificate, and passes requests to the site.

**Colocated hook**: A piece of browser JavaScript written in the same file as
the markup it belongs to. Extracted when Elixir compiles, which is why
compiling comes before bundling.

**Contact sheet**: One image showing every frame on a roll of film at its true
size. See Part 3.

**Cookie** (of a release): A shared secret that lets one Erlang program talk
to another. Not the browser kind. It is what `rpc` and `remote` present.

**C-41**: The standard process for developing colour negative film. The
negatives it produces have an orange cast built into them, which has to be
undone when scanning.

**Commit**: A saved point in the project's history, with a message explaining
what changed and why.

**Deploy**: Putting a change to the code onto the live site. Here: `./redeploy.sh`.

**Digest**: Giving a file a name that contains a fingerprint of its contents,
so a browser can keep it for ever and a new version is a new name.

**E-6**: The process for developing colour slide film. What comes out is
already a positive picture.

**Elixir**: The programming language the site is written in.

**Frame**: One photograph on a roll of film. Frames are numbered along the roll.

**Frontmatter**: The small block of information between two `---` lines at the
top of a Markdown file: title, date, keywords.

**GIMP**: A free image editor. Here it is used without its window ever opening,
purely as an engine for assembling contact sheets.

**ImageMagick**: A set of image tools that run from the command line. Used here
to make the web-sized copies of contact sheets.

**Lingering**: A systemd setting that lets one account's services run when
nobody is logged in to it.

**LiveView**: The part of Phoenix that lets a page update itself without
custom browser code.

**Loopback**: The address a computer uses to talk to itself (`127.0.0.1`, or
`localhost`). A program listening only there cannot be reached from any other
machine.

**Markdown**: Plain text with a few marks in it that mean "heading", "italic",
"link". Readable as-is; converts to a web page.

**Migration**: A recorded change to the shape of the database, so the same
change can be replayed anywhere.

**Oban**: The job queue. Jobs are rows in the database, so they survive a
restart and are retried when they fail.

**Obsidian**: A note-taking program that works on ordinary Markdown files in an
ordinary folder. The writing on this site is edited in it, but nothing depends
on it.

**Phoenix**: The toolkit that turns Elixir into a website.

**Plug**: One step in handling a request: a function that takes the request and
passes it on, changed or answered. A pipeline is a list of them.

**Preview**: The smaller, web-friendly copy of a contact sheet, made
automatically the first time someone asks for that sheet and remade whenever the
sheet changes.

**Quantum**: The scheduler: a cron that lives inside the application.

**Release**: A self-contained, compiled copy of the site, built by
`./redeploy.sh` and run by systemd. It contains everything needed to run and
nothing needed to build.

**Repository (repo)**: The project folder, with its full history. This one
lives on GitHub.

**Reverse proxy**: A server that takes requests from the internet and hands
them to another program behind it. Caddy, here.

**Roll**: One length of film, shot, developed and scanned as a unit. Numbered
uniquely across the whole archive: roll 7 is roll 7 forever.

**SQLite**: The database. A single file on disk rather than a server.

**Strip**: A roll of film cut into a short length, usually three, four or six
frames, so it fits in a scanner.

**Supervision tree**: The list of processes an Erlang program starts, each
watched by a supervisor that restarts it if it dies.

**systemd**: The part of Linux that starts programs and keeps them running.

**Tailwind**: A popular CSS toolkit. Installed here but deliberately producing
almost nothing; all styling on this site is written by hand.

**Unit**: A small text file that tells systemd how to run one program.

**Vault**: The `content/` folder: the writing and the training notes, as plain
Markdown files that Obsidian can open.

**WAL**: Write-ahead log. SQLite's way of letting readers and a writer work at
once, by keeping recent writes in a second file beside the database.

**Webmention**: A way for one website to tell another that it has linked to
it, with no platform in between.

**Witnessed**: This site's word for how many people have read a piece.
`/blog` can be sorted by it. A captain's log has **views** instead: one each
time it is watched or listened to for thirty seconds or more.
