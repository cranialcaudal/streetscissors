#!/usr/bin/env bash
#
# Redeploy the live site (streetscissors.com).
#
# The site runs as `mix phx.server` under MIX_ENV=dev via the systemd --user
# unit `streetscissors.service`, with PUBLIC_DEPLOY=true making config/dev.exs
# behave as production config. Two things about that are easy to get wrong by
# hand, and this script exists so they cannot be:
#
#   1. PUBLIC_DEPLOY flips COMPILE-TIME config (code_reloader, debug_errors,
#      dev_routes). Mix does not recompile when only an env var changes, so the
#      compile must be forced with the flag set. A mismatch makes Phoenix's
#      compile-env validator refuse to boot — correct, but it crash-loops and
#      the site goes down.
#   2. Assets must be rebuilt BEFORE the restart. `priv/static` is what gets
#      served; nothing rebuilds it at boot.
#
# The service compiles into its own MIX_BUILD_PATH (_build/deploy) so ordinary
# local `mix compile` / `mix test` runs can never clobber it.
#
# Usage:  ./redeploy.sh
set -euo pipefail

cd "$(dirname "$0")"

BUILD_PATH=/home/cesar/streetscissors/_build/deploy
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

# Export the deploy environment ONCE, before any mix invocation. `mix
# assets.build` compiles the project too, so running it with a different
# PUBLIC_DEPLOY than the compile step is exactly how the build and the runtime
# end up disagreeing.
set -a
# shellcheck disable=SC1091
. ./.env
set +a
export PUBLIC_DEPLOY=true
export MIX_ENV=dev
export MIX_BUILD_PATH="$BUILD_PATH"

echo "==> Assets"
mix assets.build

echo "==> Compile (PUBLIC_DEPLOY=true, isolated build path)"
mix compile --force

echo "==> Restart"
systemctl --user restart streetscissors.service

echo "==> Wait for health"
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:4000/ || true)
  if [ "$code" = "200" ]; then
    echo "    up (localhost:4000 -> 200)"

    # The whole point of PUBLIC_DEPLOY: these must not be reachable.
    for path in /dev/dashboard /dev/mailbox; do
      dev_code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://localhost:4000${path}" || true)
      if [ "$dev_code" = "404" ]; then
        echo "    ${path} -> 404 (closed)"
      else
        echo "    !! ${path} -> ${dev_code} — EXPECTED 404. Dev routes are exposed."
        exit 1
      fi
    done

    # Serve the stylesheet we just built, not a stale one. A months-old
    # app.css.gz once shadowed the real app.css for every gzip-capable client
    # (i.e. every browser) and the whole site rendered with the old design.
    # Ask the way a browser does — with compression — and compare to disk.
    on_disk=$(wc -c < priv/static/assets/css/app.css)
    served=$(curl -s --compressed --max-time 15 http://localhost:4000/assets/css/app.css | wc -c)
    if [ "$on_disk" = "$served" ]; then
      echo "    app.css matches disk (${served} bytes)"
    else
      echo "    !! app.css served ${served} bytes but disk has ${on_disk} — stale asset is being served."
      exit 1
    fi

    exit 0
  fi
  sleep 5
done

echo "    !! did not come up — check: journalctl --user -u streetscissors.service -n 50"
exit 1
