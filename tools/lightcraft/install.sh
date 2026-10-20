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
  if ! git clone "$REPO" "$SRC" 2>/dev/null; then
    # Said out loud: upstream has no film operations, and a build from it
    # would pass for ours until a print came out wrong.
    echo "warning: could not clone $REPO; building from upstream ($UPSTREAM) instead." >&2
    git clone "$UPSTREAM" "$SRC"
  fi
fi

origin="$(git -C "$SRC" remote get-url origin)"
if [ "$origin" != "$REPO" ]; then
  echo "note: $SRC is a checkout of $origin, not $REPO." >&2
  echo "      Delete it to clone afresh:  rm -rf $SRC" >&2
fi

git -C "$SRC" fetch --quiet origin
git -C "$SRC" checkout --quiet --detach "$REF"

# --locked: the versions in the pinned commit's Cargo.lock, never newer ones
# resolved today, so the same REF always builds the same engine.
(cd "$SRC" && cargo build --release --locked -p lightcraft-cli)
strip "$SRC/target/release/lightcraft-cli"
mkdir -p "$BIN"
install -m 0755 "$SRC/target/release/lightcraft-cli" "$BIN/lightcraft-cli.new"
mv "$BIN/lightcraft-cli.new" "$BIN/lightcraft-cli"

echo "lightcraft-cli $(git -C "$SRC" rev-parse --short HEAD) from $origin installed in $BIN"
