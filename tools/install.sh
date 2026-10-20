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
#   `tools/install.sh --doctor` installs nothing: it lists every outside
#   program the site runs, where it was found, its version, and the PATH the
#   live site's service sees, which is the one that matters.
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

# Work from this folder, wherever the script was started from. (--help reads
# this file by its own name, after the cd.)
cd "$(dirname "$0")"
SELF="$(basename "$0")"

# One line per program: found or missing, where, and the first line of its
# version. Exits 1 if anything the site needs is missing.
doctor() {
  local missing=0 unit_path
  unit_path="$(systemctl --user show streetscissors.service -p Environment 2>/dev/null |
    tr ' ' '\n' | sed -n 's/^PATH=//p' || true)"
  if [ -n "$unit_path" ]; then
    echo "The service's PATH: $unit_path"
  else
    unit_path="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
    echo "The service is not installed here; checking the PATH it would have: $unit_path"
  fi
  echo

  check() {
    local name="$1" flag="$2" need="$3" where version
    where="$(PATH="$unit_path" command -v "$name" 2>/dev/null || true)"
    if [ -z "$where" ]; then
      printf '  %-28s missing (%s)\n' "$name" "$need"
      missing=1
      return
    fi
    version="$("$where" $flag 2>&1 | head -n 1 || true)"
    printf '  %-28s %s  %s\n' "$name" "$where" "$version"
  }

  check ffmpeg -version "captain's logs, the cutting room"
  check ffprobe -version "captain's logs"
  check magick -version "web-sized photos, share cards"
  check gimp --version "contact sheets"
  check scanimage --version "the scanner studio"
  check film-develop --help "the scanner studio: tools/install.sh"
  check digital-contact-sheet-maker --help "the scanner studio: tools/install.sh"
  check negatives --help "the archive: tools/install.sh"
  check lightcraft-cli --version "the print editor: tools/install.sh --lightcraft"
  check quarto --version "the fitness report, the year as a book"
  check sqlite3 --version "backups, ops/preview.sh"
  check rsync --version "backups of the negatives and media"
  check timeout --version "time limits on the film tools"

  local repair="${FILM_REPAIR_HOME:-$HOME/.local/share/film-repair}"
  for venv in venv sd-venv; do
    if [ -x "$repair/$venv/bin/python" ]; then
      printf '  %-28s %s\n' "repair $venv" "$repair/$venv"
    else
      printf '  %-28s missing (Repair tab: tools/install.sh --repair)\n' "repair $venv"
    fi
  done

  return "$missing"
}

want_lightcraft=no
want_repair=no
for arg in "$@"; do
  case "$arg" in
    --lightcraft) want_lightcraft=yes ;;
    --repair) want_repair=yes ;;
    --all) want_lightcraft=yes; want_repair=yes ;;
    --doctor) doctor; exit $? ;;
    -h|--help) sed -n '2,51p' "$SELF"; exit 0 ;;
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
