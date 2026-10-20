#!/bin/bash
# Gives a Claude Code cloud session what `mix test` needs: Erlang/OTP 27 and
# Elixir 1.19 from Nix (Ubuntu's apt Elixir is too old for this project's
# config), Hex from GitHub, then the project's deps compiled for test.
#
# `mix deps.get` needs repo.hex.pm, which the environment's network policy
# must allow. Without it the tools are still installed and the hook says why
# the deps are missing instead of failing the session.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

NIX=/nix/var/nix/profiles/default/bin
export PATH="$NIX:$PATH"
export LANG=C.UTF-8 LC_ALL=C.UTF-8 ELIXIR_ERL_OPTIONS="+fnu"

if ! command -v elixir >/dev/null || ! elixir --version 2>/dev/null | grep -q "Elixir 1.19"; then
  nix --extra-experimental-features 'nix-command flakes' profile add \
    nixpkgs#beam.packages.erlang_27.erlang \
    nixpkgs#beam.packages.erlang_27.elixir_1_19
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export PATH=\"$NIX:\$PATH\""
    echo 'export LANG=C.UTF-8 LC_ALL=C.UTF-8 ELIXIR_ERL_OPTIONS="+fnu"'
  } >>"$CLAUDE_ENV_FILE"
fi

# Hex comes from GitHub because builds.hex.pm may be closed to this network.
if ! ls "$HOME"/.mix/archives/hex-* >/dev/null 2>&1; then
  mix archive.install github hexpm/hex branch latest --force
fi

if mix deps.get; then
  MIX_ENV=test mix deps.compile
  MIX_ENV=test mix compile
else
  echo "session-start: mix deps.get failed; allow repo.hex.pm in the environment's network settings" >&2
fi

# film-develop's tests and the colour test model (tools/film-develop).
python3 -m pip install --quiet --break-system-packages numpy pytest >/dev/null 2>&1 || true
