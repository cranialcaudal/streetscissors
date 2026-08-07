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

echo "==> Assets (minify + digest)"
# assets.deploy, not assets.build: it minifies AND runs phx.digest, which
# rewrites priv/static/cache_manifest.json. The endpoint sets
# cache_static_manifest when PUBLIC_DEPLOY is on, so ~p"/assets/..." resolves
# through that manifest — if it is older than the files in priv/static, every
# page silently loads the previous build's stylesheet. Regenerating it here is
# what makes enabling the manifest safe.
mix assets.deploy

# Old digests accumulate forever otherwise (114 of them by the first run of
# this step). Keep the current version plus one, so a client mid-request
# against the previous deploy still gets a hit.
mix phx.digest.clean --age 3600 --keep 1

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
    #
    # Check what a browser actually loads: pull the href out of the rendered
    # homepage rather than guessing the URL. With cache_static_manifest on that
    # is a digested path, so this also proves the manifest is in step with
    # priv/static — a stale manifest is silent, and points at the old build.
    href=$(curl -s --max-time 15 http://localhost:4000/ \
      | grep -oE '/assets/css/app[^"]*\.css' | head -1)
    if [ -z "$href" ]; then
      echo "    !! could not find the app.css link in the homepage HTML."
      exit 1
    fi

    on_disk=$(wc -c < "priv/static${href}")
    served=$(curl -s --compressed --max-time 15 "http://localhost:4000${href}" | wc -c)
    if [ "$on_disk" = "$served" ]; then
      echo "    ${href} matches disk (${served} bytes)"
    else
      echo "    !! ${href} served ${served} bytes but disk has ${on_disk} — stale asset is being served."
      exit 1
    fi

    exit 0
  fi
  sleep 5
done

echo "    !! did not come up — check: journalctl --user -u streetscissors.service -n 50"
exit 1
