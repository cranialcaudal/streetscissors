# Film Scanning & Contact Sheet Pipeline

Turns scanned film strips into printable contact sheets using GIMP —
without ever opening the GIMP window. Scans are always made at **300 dpi**,
and every sheet is a **300 dpi, ~8×10 in** image, so exposures print at
their true physical size.

## What's in this folder

This is the film darkroom's toolkit. It lives inside the website's repository (it used to be a
separate one; its history came with it), but **it does not need the website**: on its own it
scans a roll, develops it and lays out a contact sheet. The website then shows the folder these
tools write. See [`../README.md`](../README.md) for how it fits with the site's other tools.

```
bin/negatives                    the scan-session wizard (one roll at a time)
bin/film-develop                 turns a scan of a negative into a positive print: finds the
                                 frames on a strip, removes the orange mask of colour film,
                                 sets the colour once per roll and the exposure per frame
bin/film-finish                  what a developed single needs after that, in place: the
                                 scanner's lines undone, dust and hairs filled, and a colour
                                 print's grey balanced against its roll (film-develop runs it)
bin/digital-contact-sheet-maker  headless GIMP contact-sheet builder
gimp/film-contact-sheet.scm      the layout engine (also a GIMP dialog:
                                 File > Create > Film Contact Sheet…)
gimp/negative-package.scm        File > Create > Negative Package… dialog
install.sh                       links everything into place (--copy to copy)
test-model/                      a pretend roll of film with known numbers, for testing
                                 film-develop's colour maths (see its README)
```

Requirements: bash, GIMP 3.x (native or flatpak), Python 3 (standard library only, for `film-develop`),
ImageMagick, and optionally Epson's `iscan` (falls back to simple-scan, or set
`NEGATIVES_SCANNER`). `film-finish` needs numpy and OpenCV, so `film-develop` runs it under the
print repair's Python (`~/.local/share/film-repair/venv`, or `FILM_FINISH_PYTHON`); without it
a single only has its white specks taken off, as before. Install with `tools/install.sh` from the top of the repository (it runs
this folder's `install.sh`). The finished sheets are served by
[streetscissors](https://streetscissors.com/negatives) straight from the collection folder
described below.

**`film-develop` is a long program (about 3,000 lines of Python).** How it reads strips scanned
on bare glass, and why each rule is there, is told roll by roll in
[`docs/negatives-pipeline.md`](../../docs/negatives-pipeline.md) §9. The git history of
`bin/film-develop` has one commit per version, oldest first.

## Folder layout

```
~/Pictures/Negatives/
├── 120 Film/          one folder per roll
├── 620 Film/
├── 110 Film/
├── 35mm Film/
├── Other/
├── Contact Sheets/    finished sheets: <roll folder name>.png
│   └── previews/      downscaled .webp the website serves
├── .trash/            rolls retired with --delete (safe to empty)
├── catalog.csv        roll,scan_date,film_type,color,frames,folder
└── README.md          this file
```

## Naming convention

Each roll gets one folder, named:

```
rollNNN_DATE_FORMAT_COLOR        e.g.  roll001_2026-07-04_120_bw
```

- `NNN` — roll number, unique across the whole collection and zero-padded
  so sorting works. The wizard refuses a number that's already taken; to
  reuse one, retire the old roll first (see **Deleting a roll** below)
- `FORMAT` — `120`, `620`, `110`, `35mm`, or anything else → filed under Other
- `COLOR` — `bw` or `color`

Inside the folder, every scan file must start with `roll` (any of
jpg/png/tif/tiff/bmp/webp). Strips are placed on the sheet in **filename
order**, so number them: `..._01.tiff`, `..._02.tiff`, …

## The pipeline: `negatives`

Typing `negatives` runs one roll at a time, start to finish:

1. **Builds the roll name** — prompts for roll number (suggests the next
   free one), film format, bw/color, and scan date (defaults to today;
   format and color default to your previous roll).
2. **Creates the roll folder** directly inside its format folder (e.g.
   `120 Film/roll004_…`), opens it in the file manager, and **launches
   the scanner app from inside that folder** (iscan; falls back to
   simple-scan, or set `NEGATIVES_SCANNER=<command>` to override).
   iscan's save dialog opens in the process's working directory, so
   when you press Scan it already points at the roll folder — just name
   the files, one per strip:
   `rollNNN_DATE_FORMAT_COLOR_01.tiff`, `_02.tiff`, …
3. **Waits for the scanner to close** — when you close `iscan`, the
   pipeline continues automatically (or press Enter if no scanner app
   is configured).
4. **Catalogs and assembles** — appends the roll to `catalog.csv` and
   builds the contact sheet on a **black background** in headless GIMP
   (`Contact Sheets/<roll folder name>.png`). streetscissors serves that
   folder directly, so the sheet is live on the site the moment it's
   written.
5. **Open in GIMP?** — `y` opens the sheet in GIMP and ends the session;
   `n` asks whether to scan another roll (y/n).

`film-intake` is an alias. There is no batch/menu mode anymore — the
wizard is strictly one roll at a time. Rolls scanned outside the wizard:
drop a `rollNNN_DATE_FORMAT_COLOR` folder into the right format folder,
run `digital-contact-sheet-maker <folder>`, and add a `catalog.csv`
line by hand (`roll,scan_date,film_type,color,frames,folder`).

## Deleting a roll, and reusing its number

A roll number lives in **four** places: the scan folder, its `catalog.csv`
row, `Contact Sheets/<name>.png`, and the web preview under
`Contact Sheets/previews/`. Deleting the folder in your file manager only
clears the first, so the number stays reserved and the stale sheet keeps
serving on streetscissors. Use the command instead:

```
negatives --list            what each number currently holds, and the next free one
negatives --delete 009      retire roll 009 and free the number
negatives --redo 009        delete 009, then scan a fresh roll straight into 009
```

`--delete` prints exactly what it will remove and asks first (`-y` skips
the prompt). Scans are **recoverable** — the folder moves to
`~/Pictures/Negatives/.trash/<name>_deleted-<timestamp>/` — while the
catalog row, sheet and preview are removed outright, since all three are
rebuilt from the scans anyway. Nothing in `.trash/` reserves a number, so
empty the folder whenever you like.

`--redo NNN` is the rescan case: it deletes, then drops into the normal
wizard with `NNN` pre-filled, so you confirm format/color/date and scan.

## One roll at a time

```
digital-contact-sheet-maker "120 Film/roll001_2026-07-04_120_bw"
```

Useful options:

| Option | Meaning |
|---|---|
| `-o FILE` | Output path/format (default `Contact Sheets/<name>.png`) |
| `-p 8x10\|a4\|letter` | Paper size, always 300 dpi (default 8x10) |
| `-l rows\|columns\|auto` | Force a strip layout (default: inferred, see below) |
| `--no-invert` | For scans that are already positives |
| `--white` | White paper (default is black — traditional darkroom look) |
| `--pattern GLOB` | Match scans not named `roll*` |

## Layout rules per format

Inferred from the folder path; override with `--layout`.

- **120 & 620** — strips side by side ("columns"). Exposure count per
  strip doesn't matter: 620 rolls of 8 (3:2 frames) or 12 (square) work
  the same way.
- **35mm** — 6-exposure strips stacked top to bottom ("rows").
- **110 & Other** — no assumption ("auto"); these usually need custom
  assembly, so force a layout or arrange by hand in GIMP.

`rows`/`columns` auto-rotate scans into the needed orientation. Strips are
placed at native size when they fit; if the stack physically can't fit the
paper, all strips shrink by one uniform factor and the tool prints the
percentage.

## Working frame by frame: analysis & keepers

A contact sheet is built to be marked up. You can analyze exposures and sticker keepers:

```bash
negatives --analyze NNN          # split strips into frames, calculate IQR quality, write frames.json
negatives --selects NNN          # view current stickered frames
negatives --select NNN 2,5,9     # sticker keeper frames (shows red wax mark on streetscissors)
negatives --unselect NNN 5       # remove sticker
negatives --scan-frames NNN      # scan picked frames at high resolution (2400-3200 DPI)
negatives --redevelop NNN        # redevelop rescanned frames with 70% strip / 30% frame weighting
```

- When a frame is stickered with `--select`, `streetscissors` procedurally generates an organic red china-marker wax circle around it on the live contact sheet.
- Rescanned keeper frames are saved as `<frame_number>.tiff` (e.g. `3.tiff`), instantly publishing the photograph at `https://streetscissors.com/negatives/roll/NNN/frame/<N>`.

## Integration with streetscissors

This toolchain feeds directly into the [streetscissors](https://streetscissors.com) web engine:
- **Filesystem Contract:** `streetscissors` points at `~/Pictures/Negatives/` via `NEGATIVES_PATH`. The site reads `catalog.csv`, contact sheets, and `frames.json` directly at request time without database records.
- **Coordinate Replay:** `Web.Negatives.SheetLayout` transcribes the exact layout arithmetic of `film-contact-sheet.scm`, mapping strip coordinates to responsive web percentages.
- **Organic Marks:** `Web.Negatives.GreasePencil` deterministically generates Catmull-Rom splined wax rings for stickered frames.
- **Future Custom Scanner GUI:** For the architectural specification of the upcoming native studio scanner console at `/admin/scanner`, see `docs/scanner-gui-blueprint.md` in the `streetscissors` repository.

## Notes

- Negative scans are inverted to positives by default. On **color** (C-41)
  rolls the orange mask inverts to a blue-ish cast — fine for proofing.
- Sheets keep 300 dpi metadata, so they print at true size from any app.
- Manual/GUI alternative: in GIMP, **File > Create > Film Contact Sheet…**
  offers the same engine with folder picker, paper, invert, black-paper,
  and layout options (uses all image files in the folder, not just `roll*`).
- The layout engine lives in `~/.config/GIMP/3.2/scripts/film-contact-sheet.scm`;
  the commands are `~/.local/bin/negatives` (alias: `film-intake`) and
  `~/.local/bin/digital-contact-sheet-maker`. If a run fails, the full GIMP
  log is printed — most "unbound variable" errors mean the .scm file moved
  or GIMP changed versions (the tools pick the newest
  `~/.config/GIMP/*/scripts/` automatically).

