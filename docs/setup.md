# Setting up a machine

This guide takes a computer with nothing on it to a working copy of the site: the code running
on your own machine, the tests passing, and, if you want them, every outside program the site
uses. It assumes **Fedora Linux** (the site's own machine runs Fedora 43); for Ubuntu or Debian,
the package names are given where they differ.

You do not need to know Elixir to follow it. Each command is written out in full, with a line
saying what it does and how to tell that it worked.

If you only want to *understand* the site, read [`how-to.md`](how-to.md) instead: it explains
what each part is for, in plain language, without installing anything.

---

## Contents

1. [What you will end up with](#1-what-you-will-end-up-with)
2. [The essentials: Erlang, Elixir, git](#2-the-essentials-erlang-elixir-git)
3. [Getting the code and running the tests](#3-getting-the-code-and-running-the-tests)
4. [Running the site on your machine](#4-running-the-site-on-your-machine)
5. [The optional programs, one by one](#5-the-optional-programs-one-by-one)
6. [Running it for real](#6-running-it-for-real)
7. [When something goes wrong](#7-when-something-goes-wrong)

---

## 1. What you will end up with

The site is written in **Elixir**, a programming language that runs on **Erlang**'s virtual
machine (the "BEAM"). It uses **Phoenix**, a web framework for Elixir, and stores its data in
**SQLite**, a database that is just one file on disk. That is all the site needs to start.

Some pages also use outside programs: ffmpeg for video, ImageMagick for pictures, GIMP for
contact sheets, and others. **Each one is optional.** Without it, the page that needs it says
what is missing, and the rest of the site carries on. The table below lists every one, so you
can decide what to install.

| Program | Needed for | Fedora install | Check it worked |
|---|---|---|---|
| Erlang + Elixir | Everything (required) | `sudo dnf install elixir erlang` | `elixir --version` |
| git | Getting the code (required) | `sudo dnf install git` | `git --version` |
| rsync, ImageMagick, sqlite3 | The test suite (required for `mix test` to pass), and backups, pictures and looking inside the database | `sudo dnf install rsync ImageMagick sqlite` | `rsync --version`, `magick -version`, `sqlite3 --version` |
| ffmpeg | Captain's logs (video and audio), the cutting room, exercise films | RPM Fusion: see §5.1 | `ffmpeg -version` |
| ImageMagick | Photo previews, share cards, the scanner page, titles in the cutting room | `sudo dnf install ImageMagick` | `magick -version` |
| GIMP 3 | Building contact sheets | `flatpak install flathub org.gimp.GIMP` | `flatpak run org.gimp.GIMP --version` |
| The film tools | The negatives archive and the scanner page | `tools/install.sh` | `film-develop --help` |
| SANE (`scanimage`) | Driving a flatbed scanner | `sudo dnf install sane-backends` | `scanimage -L` |
| LightCraft | The print editor (`/admin/darkroom`) | `tools/install.sh --lightcraft` (needs Rust) | `lightcraft-cli --version` |
| Repair models | The print editor's Repair tab | `tools/install.sh --repair` | `ls ~/.local/share/film-repair` |
| R + Quarto | The emissions charts and the training report | §5.7 | `Rscript --version`, `quarto --version` |
| Node.js + Chrome | Filming the exercise figures | `sudo dnf install nodejs` + Google Chrome | `node --version`, `google-chrome --version` |
| unzip | Apple Health imports | `sudo dnf install unzip` | `unzip -v` |
| Caddy | Serving the site to the internet (production only) | `sudo dnf install caddy` | `caddy version` |

---

## 2. The essentials: Erlang, Elixir, git

Open a terminal and run:

```bash
sudo dnf install elixir erlang git rsync ImageMagick sqlite
```

`dnf` is Fedora's package manager; `sudo` runs it as the administrator, so it will ask for your
password. This installs Erlang, Elixir and git, plus three small programs the test suite uses
for real: `rsync` (the backup tests copy files with it), ImageMagick (the picture tests) and the
`sqlite3` command (the backup tests open the snapshots they make).

Elixir expects your terminal to use UTF-8. A Fedora or Ubuntu desktop already does; in a bare
container or a minimal server, add `export LANG=C.UTF-8` to your shell first, or Elixir prints a
warning about "latin1" and some text handling misbehaves.

Check:

```bash
elixir --version
```

You should see `Elixir 1.19` or newer (the project needs at least 1.15; it is developed on 1.19).
If your system's Elixir is older, install a newer one with
[asdf](https://asdf-vm.com) or [mise](https://mise.jdx.dev), or with Nix as the cloud setup script
does (`.claude/hooks/session-start.sh`).

**Ubuntu / Debian:** the packaged Elixir is usually too old. Use one of the version managers
above.

Elixir has its own package manager, **Hex**, which downloads the libraries the site uses. Install
it once:

```bash
mix local.hex --force
```

`mix` is Elixir's build tool: you will use it for almost everything below.

---

## 3. Getting the code and running the tests

```bash
git clone https://github.com/cranialcaudal/streetscissors.git
cd streetscissors
mix setup
```

`mix setup` does four things, in order (they are listed in `mix.exs`, under `aliases`):

1. `deps.get` downloads the Elixir libraries into `deps/`.
2. `ecto.setup` creates the development database (`tmp/db/web_dev.db`), builds its tables
   from the migrations in `priv/repo/migrations/`, and runs `priv/repo/seeds.exs`.
3. `assets.setup` downloads the two small programs that build the stylesheet and the browser
   code (Tailwind and esbuild).
4. `assets.build` compiles the code and builds the stylesheet and the browser code.

The first run takes a few minutes. Then run the tests:

```bash
mix test
```

You should see about 1,570 tests and `0 failures` at the end (a few are "skipped": they need a
program from §5 you have not installed, and say so). The tests never need the
real content or any of the optional programs: they use invented sample content in
`test/support/fixtures/`, and small stand-in programs for ffmpeg, LightCraft and the rest in
`test/support/`. A few tests that need a real program (ffmpeg, node) skip themselves when it is
missing.

**Before you say a change is done**, run the full check the project uses:

```bash
mix precommit
```

It compiles with warnings treated as errors, removes unused libraries from the lock file, formats
the code, and runs every test.

---

## 4. Running the site on your machine

```bash
mix phx.server
```

Then open <http://localhost:4000> in a browser. Stop the server with Ctrl+C twice.

**What you will see:** a working site with no content. The real writing, photographs and training
plan are not in the repository (see "Private by default" in the README). To see the pages with
something on them, point the site at the test suite's sample content:

```bash
BLOG_PATH=test/support/fixtures/blog \
FITNESS_PATH=test/support/fixtures/fitness \
NEGATIVES_PATH=test/support/fixtures/negatives \
mix phx.server
```

Each variable tells one part of the site where to read from. The same variables point the live
site at the real folders.

**The admin side** is at <http://localhost:4000/admin>. The development password is `dev-admin`
(set in `config/dev.exs`). In production the password comes from the `ADMIN_PASSWORD` setting
and the site refuses to start without one.

**On a machine that is also running the live site**, port 4000 is taken: start the development
server with `PORT=4001 mix phx.server`. Its database and backups are kept apart from the live
site's, and it sends no webmentions (`config/dev.exs`).

**The `.env` file** is for production. A development server does not read it: if you want to try
an optional integration (Komoot, mail) while developing, set its variable in the terminal the same
way as above. [`.env.example`](../.env.example) lists every variable and what it does.

---

## 5. The optional programs, one by one

Install only what you need. Each section says which page uses the program and what happens
without it.

### 5.1 ffmpeg (video and audio)

Used by: the captain's logs (every recording is converted to one MP4 or M4A file), the cutting
room (rendering a cut), and filming the exercise figures.

Fedora's own ffmpeg leaves out some formats for patent reasons; the full one comes from
[RPM Fusion](https://rpmfusion.org):

```bash
sudo dnf install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
sudo dnf install ffmpeg --allowerasing
ffmpeg -version
```

(Ubuntu: `sudo apt install ffmpeg`.)

Without it: recordings stay "pending" and the admin shows why.

### 5.2 ImageMagick (pictures)

Used by: the web-sized copies of photographs, the share cards a link shows on social media, the
scanner page's cutting and measuring, and the titles in the cutting room.

```bash
sudo dnf install ImageMagick
magick -version
```

The site calls it as `magick` (ImageMagick 7). Ubuntu's older packages may only have `convert`;
install ImageMagick 7 from its website if so.

### 5.3 GIMP and the film tools (the negatives archive)

The film tools in [`tools/film/`](../tools/film/) scan a roll, develop it and lay out its contact
sheet. The contact sheet is laid out by GIMP, run without its window. Install GIMP 3 and open it
once (so it creates its settings folder), then install the tools:

```bash
flatpak install flathub org.gimp.GIMP     # or: sudo dnf install gimp
flatpak run org.gimp.GIMP                 # open it once, then close it
tools/install.sh
film-develop --help
```

`tools/install.sh` links the three programs into `~/.local/bin` and the two GIMP scripts into
GIMP's scripts folder; its opening comment explains each step. `film-develop` needs only Python 3,
which Fedora already has, and ImageMagick (§5.2).

Then tell the site where your negatives folder is, in `.env` for production or in the terminal
for development: `NEGATIVES_PATH=/path/to/Negatives`. [`tools/film/README.md`](../tools/film/README.md)
describes the folder's layout and the whole scanning workflow.

### 5.4 SANE (a flatbed scanner)

Used by: the scanner page (`/admin/scanner`). The site was built with an Epson Perfection V550
and its transparency unit.

```bash
sudo dnf install sane-backends
scanimage -L            # lists the scanners SANE can see
```

Then set where each film holder's strips sit on the glass, in `.env`: `SCANNER_AREA_35MM` and
`SCANNER_AREA_120` (`.env.example` explains the format). The scanner page's Setup tab shows what
it found.

### 5.5 LightCraft (the print editor)

Used by: the print editor (`/admin/darkroom`), for every slider, crop and dust spot.

It is built from source with Rust. Install Rust first (this downloads and runs Rust's official
installer), open a new terminal, then build:

```bash
curl https://sh.rustup.rs -sSf | sh
sudo dnf install gcc
tools/install.sh --lightcraft
lightcraft-cli --version
```

[`tools/lightcraft/README.md`](../tools/lightcraft/README.md) explains why the version is pinned.

### 5.6 The repair models (the print editor's Repair tab)

Two AI models that fix scratches, dust and scanner lines. About 4 GB of downloads; no graphics
card needed.

```bash
tools/install.sh --repair
```

[`tools/repair/README.md`](../tools/repair/README.md) explains what each model does and why the
larger one runs with a memory limit.

### 5.7 R and Quarto (charts and the training report)

Used by: the commuting-emissions charts in one blog post, and the weekly training report.

```bash
sudo dnf install R
Rscript -e 'install.packages(c("jsonlite","dplyr","tidyr","ggplot2","DBI","RSQLite"), repos="https://cloud.r-project.org")'
```

Quarto is not packaged for Fedora. Download the Linux `.tar.gz` from
<https://quarto.org/docs/download/>, then:

```bash
mkdir -p ~/.local/opt/quarto
tar -xzf quarto-*-linux-amd64.tar.gz -C ~/.local/opt/quarto --strip-components=1
ln -s ~/.local/opt/quarto/bin/quarto ~/.local/bin/quarto
quarto --version
```

[`analysis/README.md`](../analysis/README.md) explains what each script does and how to run it by
hand.

### 5.8 Node.js and Chrome (filming the exercise figures)

Each exercise in the wiki can show a short film of a 3D figure doing it. The films are made once,
on the workbench, by `mix fitness.film`, which drives a headless Google Chrome with a small Node.js
program (`priv/figure/render.mjs`) and hands the frames to ffmpeg.

```bash
sudo dnf install nodejs
# Google Chrome: https://www.google.com/chrome/ (the .rpm), or set CHROME_BIN to another Chrome
node --version && google-chrome --version
```

Only one film can be made at a time. Without these, the wiki shows the flat drawing instead of
the film.

---

## 6. Running it for real

Running the site on the internet is a different job from developing it: a compiled release
instead of `mix phx.server`, two systemd services, Caddy in front for HTTPS, backups and
monitoring. Everything for that is in [`ops/`](../ops/), and the manual walks through it step by
step:

- [`how-to.md`](how-to.md) **Part 6** ("How it is run"): the two services, a deploy, taking one
  back, migrations, logs, certificates.
- [`how-to.md`](how-to.md) **Part 7** ("Keeping it safe"): backups and restoring them.
- [`../ops/README.md`](../ops/README.md): what each file in `ops/` is, and how to install it.

In short: copy `.env.example` to `.env` and fill it in, install the unit files from
`ops/systemd/`, and deploy with `ops/redeploy.sh`.

---

## 7. When something goes wrong

| What you see | What it usually means | What to do |
|---|---|---|
| `mix setup` fails on `deps.get` | No internet, or Hex is not installed | Check the connection; run `mix local.hex --force` |
| `could not compile dependency :exqlite` | No C compiler, which the SQLite library needs | `sudo dnf install gcc make` |
| `eaddrinuse` when starting the server | Something else is on port 4000 | `PORT=4001 mix phx.server` |
| The site starts but every page is empty | No content folders set | See §4: point it at the sample content |
| A test fails with `:enoent` naming a program | A test that needs a real program found none | Install it (§5), or read the test: most skip themselves when the program is missing |
| `film-develop: command not found` | `~/.local/bin` is not on your `PATH` | Log out and back in, or add `export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` |
| The contact sheet step says GIMP has no scripts folder | GIMP has never been opened | Open GIMP once, close it, run `tools/install.sh` again |

For anything else, the manual's Part 6 has a longer list ("When something is wrong"), and
`journalctl --user -u streetscissors` shows what the live site logged.
