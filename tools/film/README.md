# Film Scanning & Contact Sheet Pipeline

Turns scanned film strips into printable contact sheets using GIMP —
without ever opening the GIMP window. Scans are always made at **300 dpi**,
and every sheet is a **300 dpi, ~8×10 in** image, so exposures print at
their true physical size.

## What's in this repo

```
bin/negatives                    the scan-session wizard (one roll at a time)
bin/digital-contact-sheet-maker  headless GIMP contact-sheet builder
gimp/film-contact-sheet.scm      the layout engine (also a GIMP dialog:
                                 File > Create > Film Contact Sheet…)
gimp/negative-package.scm        File > Create > Negative Package… dialog
install.sh                       symlinks everything into place (--copy to copy)
```

Requirements: bash, GIMP 3.x (native or flatpak), and optionally Epson's
`iscan` (falls back to simple-scan, or set `NEGATIVES_SCANNER`). Run
`./install.sh` after cloning. The finished sheets are served by
[streetscissors](https://streetscissors.com/negatives) straight from the
collection folder described below.

## Folder layout

```
~/Pictures/Negatives/
├── 120 Film/          one folder per roll
├── 620 Film/
├── 110 Film/
├── 35mm Film/
├── Other/
├── Contact Sheets/    finished sheets: <roll folder name>.png
├── catalog.csv        roll,scan_date,film_type,color,frames,folder
└── README.md          this file
```

## Naming convention

Each roll gets one folder, named:

```
rollNNN_DATE_FORMAT_COLOR        e.g.  roll001_2026-07-04_120_bw
```

- `NNN` — roll number (keep it unique; zero-pad so sorting works)
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
