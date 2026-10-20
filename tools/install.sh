#!/usr/bin/env bash
#
# tools/install.sh — put the site's helper programs where the site can find them.
#
# WHAT THIS DOES
#
#   The website does not do everything itself. For some jobs it starts another
#   program and reads what that program prints (the manual, docs/how-to.md,
#   lists them under "Programs the site runs"). Some of those programs are
#   ordinary packages you install with your system's package manager (ffmpeg,
#   ImageMagick, GIMP). The ones written for this site live in this folder, and
#   this script makes them available:
#
#     1. The film tools (tools/film/): `negatives`, `film-develop` and
#        `digital-contact-sheet-maker` are linked into ~/.local/bin, and the
#        two GIMP scripts into GIMP's own scripts folder. This is quick and
#        always done.
#
#     2. LightCraft (tools/lightcraft/install.sh), the print editor's engine.
#        It is compiled from source with Rust, which takes several minutes, so
#        it is only built when you ask:   tools/install.sh --lightcraft
#
#     3. The repair models (tools/repair/install.sh), for the print editor's
#        Repair tab: two Python environments and about 2.5 GB of model files.
#        Also only when you ask:          tools/install.sh --repair
#
#   `tools/install.sh --all` does all three.
#
# WHY LINKS AND NOT COPIES
#
#   ~/.local/bin/film-develop is a symbolic link pointing back into this
#   repository. That means the repository is the only copy: edit
#   tools/film/bin/film-develop and the change is live at once, for you and
#   for the website. There is never an old copy somewhere else to forget about.
#   (tools/film/install.sh --copy copies instead, if you ever need that.)
#
# SAFE TO RUN AGAIN
#
#   Running it twice does no harm; each step replaces what the last run put
#   there.
#
# BEFORE YOU RUN IT
#
#   GIMP 3 must have been opened once, so that ~/.config/GIMP/<version>/scripts
#   exists. On Fedora:  sudo dnf install gimp && gimp   (then close it).
#   ~/.local/bin should be on your PATH (it is by default on Fedora and Ubuntu).
#
set -euo pipefail

# Work from this folder, wherever the script was started from.
cd "$(dirname "$0")"

want_lightcraft=no
want_repair=no
for arg in "$@"; do
  case "$arg" in
    --lightcraft) want_lightcraft=yes ;;
    --repair) want_repair=yes ;;
    --all) want_lightcraft=yes; want_repair=yes ;;
    -h|--help) sed -n '2,47p' "$0"; exit 0 ;;
    *) echo "tools/install.sh: unknown option '$arg' (try --help)" >&2; exit 2 ;;
  esac
done

echo "==> 1. The film tools (tools/film/)"
film/install.sh

if [ "$want_lightcraft" = yes ]; then
  echo "==> 2. LightCraft, the print editor's engine (tools/lightcraft/)"
  lightcraft/install.sh
else
  echo "==> 2. LightCraft: skipped (add --lightcraft to build it)"
fi

if [ "$want_repair" = yes ]; then
  echo "==> 3. The repair models (tools/repair/)"
  repair/install.sh
else
  echo "==> 3. Repair models: skipped (add --repair to install them)"
fi

echo
echo "Done. To check that the film tools are found, run:  film-develop --help"
