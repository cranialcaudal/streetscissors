#!/usr/bin/env bash
# Builds and installs the print editor's engine, lightcraft-cli, at the commit
# the site was measured against (Web.Darkroom.Film's Temp and Tint figures were
# measured at 43a47e5; change both together, and run
# test/web/darkroom_film_test.exs against the new build).
#
#   tools/lightcraft/install.sh            build LIGHTCRAFT_REF and install to ~/.local/bin
#   LIGHTCRAFT_REF=<sha> tools/lightcraft/install.sh
#
# The engine comes from our fork (cranialcaudal/lightcraft), which carries the
# film operations (docs/colour/contracts.md); until the fork exists, upstream.
# The checkout is kept in ~/.cache/lightcraft so a rebuild only fetches.
set -euo pipefail

REPO="${LIGHTCRAFT_REPO:-https://github.com/cranialcaudal/lightcraft}"
UPSTREAM="https://github.com/storytold/lightcraft"
REF="${LIGHTCRAFT_REF:-43a47e5}"
SRC="${LIGHTCRAFT_SRC:-$HOME/.cache/lightcraft}"
BIN="${LIGHTCRAFT_BIN_DIR:-$HOME/.local/bin}"

if [ ! -d "$SRC/.git" ]; then
  git clone "$REPO" "$SRC" 2>/dev/null || git clone "$UPSTREAM" "$SRC"
fi

git -C "$SRC" fetch --quiet origin
git -C "$SRC" checkout --quiet --detach "$REF"

(cd "$SRC" && cargo build --release -p lightcraft-cli)
strip "$SRC/target/release/lightcraft-cli"
mkdir -p "$BIN"
install -m 0755 "$SRC/target/release/lightcraft-cli" "$BIN/lightcraft-cli.new"
mv "$BIN/lightcraft-cli.new" "$BIN/lightcraft-cli"

echo "lightcraft-cli $(git -C "$SRC" rev-parse --short HEAD) installed in $BIN"
