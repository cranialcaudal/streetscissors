#!/usr/bin/env bash
# Installs the film pipeline:
#   bin/*      -> ~/.local/bin  (plus the film-intake alias symlink)
#   gimp/*.scm -> newest ~/.config/GIMP/<version>/scripts/
#
# Symlinks by default, so this repo stays the source of truth and edits
# here are live immediately. Use --copy to copy the files instead.
set -euo pipefail
cd "$(dirname "$0")"
MODE=link
[ "${1:-}" = "--copy" ] && MODE=copy

GIMP_SCRIPTS=$(ls -d ~/.config/GIMP/*/scripts 2>/dev/null | sort -V | tail -1)
if [ -z "$GIMP_SCRIPTS" ]; then
  echo "error: no ~/.config/GIMP/<version>/scripts directory found" >&2
  exit 1
fi
mkdir -p ~/.local/bin

place() {  # src dest
  if [ "$MODE" = copy ]; then
    cp "$1" "$2"
  else
    ln -sf "$(realpath "$1")" "$2"
  fi
  echo "installed $2"
}

for f in bin/*; do
  chmod +x "$f"
  place "$f" ~/.local/bin/"$(basename "$f")"
done
for f in gimp/*.scm; do
  place "$f" "$GIMP_SCRIPTS/$(basename "$f")"
done
ln -sfn ~/.local/bin/negatives ~/.local/bin/film-intake
echo "done ($MODE mode). film-intake -> negatives alias refreshed."
