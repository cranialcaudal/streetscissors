# tools/

This folder holds **programs that are not the website, but that the website needs.**

The website (everything under `lib/`) is written in Elixir. For some jobs it starts a separate
program, waits for it to finish, and reads what it wrote: developing a scanned negative into a
print, laying out a contact sheet, editing a photograph, repairing a damaged one. Most of those
programs are ordinary software you install from your system's package manager (ffmpeg,
ImageMagick, GIMP; [`docs/setup.md`](../docs/setup.md) lists them all). The ones that were
written or assembled for this site live here, so that a fresh copy of the repository has
everything it needs.

Nothing in this folder is compiled into the website. The site finds these programs by name, on
your `PATH` (usually `~/.local/bin`), exactly as you would find them by typing their names in a
terminal.

## What is here

| Folder | What it is | Which part of the site uses it | Install it with |
|---|---|---|---|
| [`film/`](film/) | The film darkroom: `negatives` (a wizard that walks you through scanning one roll of film), `film-develop` (turns a scan of a negative into a positive print), `digital-contact-sheet-maker` (lays a roll's strips out on one page, using GIMP), and the GIMP scripts that do the layout | `/negatives` (the public archive) and `/admin/scanner` (the scanner page) | `tools/install.sh` |
| [`film/test-model/`](film/test-model/) | A fake roll of film made from numbers chosen in advance, so the colour maths can be tested: if you know exactly what went in, you can check exactly what comes out | Nothing at run time; only tests | Nothing to install. Needs Python with numpy and pytest |
| [`vendor/codemirror/`](vendor/codemirror/) | Rebuilds `assets/vendor/codemirror.js`, the admin editor's engine, from the versions pinned in its `package.json` and lockfile. The site's own build needs no Node; only this does, and only when a version changes. Run it, then commit both files it writes | `/admin` (the document editor) | `tools/vendor/codemirror/build.sh` |
| [`lightcraft/`](lightcraft/) | Builds `lightcraft-cli`, the photo-editing engine behind the print editor's sliders, crop and dust removal | `/admin/darkroom` (the print editor) | `tools/install.sh --lightcraft` |
| [`repair/`](repair/) | Sets up the two Python environments and the two AI models the print editor's Repair tab uses | `/admin/darkroom`, Repair tab | `tools/install.sh --repair` |
| [`install.sh`](install.sh) | Runs the installers above. Read its opening comment: it explains every step | — | — |

## The one-line version

```bash
tools/install.sh          # the film tools (seconds)
tools/install.sh --all    # also LightCraft (minutes, needs Rust) and the repair models (about 4 GB)
tools/install.sh --doctor # installs nothing: lists every program the site runs, found or missing
```

Then check:

```bash
film-develop --help                  # prints the film-develop commands
negatives --list                     # lists the rolls in your negatives folder (if you have one)
lightcraft-cli --version             # only after --lightcraft
```

## Things worth knowing

**The installed programs are links back into this folder, not copies.** After
`tools/install.sh`, `~/.local/bin/film-develop` points at `tools/film/bin/film-develop`.
So editing the file here changes the program the live site runs, immediately, with no
install step and no deploy. That is convenient, and it also means: **test a change to
`film-develop` before you save it over the working file on the server.** The test model in
`film/test-model/` and the regression checks described in
[`docs/colour/contracts.md`](../docs/colour/contracts.md) are how.

**Each tool works without the website.** You can scan and develop a roll of film with
`negatives` and `film-develop` on a computer that has never seen the site. The site is a way of
looking at the folder of negatives those tools make; see [`film/README.md`](film/README.md).

**Without a tool, the matching page says so.** The site never pretends: if `film-develop` is
missing, the scanner page shows the error rather than inventing a result. Every other page keeps
working.

## Where else to look

- [`docs/setup.md`](../docs/setup.md): setting up a whole machine, step by step, including the
  system packages these tools depend on.
- [`docs/how-to.md`](../docs/how-to.md) Part 3: how a roll of film becomes a page, in plain
  language. Part 5 has the full list of programs the site runs.
- [`docs/negatives-pipeline.md`](../docs/negatives-pipeline.md): the film maths in depth.
