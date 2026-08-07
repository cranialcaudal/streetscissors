#!/usr/bin/env bash
#
# Redeploy the live site (streetscissors.com).
#
# The site runs a compiled MIX_ENV=prod OTP release under the systemd --user
# unit `streetscissors.service`. Two things about that shape this script:
#
#   1. Assets must be built BEFORE `mix release`, because a release packages
#      priv/ into itself. Building them afterwards changes the checkout and not
#      the thing actually being served.
#   2. `mix release --overwrite` replaces the release directory underneath the
#      running BEAM, which can then fail to load a module it had not loaded yet.
#      So the restart follows immediately, and the health gate below is what
#      proves the new build actually serves.
#
# What is NOT here any more, and why: the old dev-mode deploy needed
# PUBLIC_DEPLOY=true set identically at compile time and run time, with an
# isolated MIX_BUILD_PATH, because a mismatch made Phoenix refuse to boot and
# crash-loop the site. Production config is no longer driven by a compile-time
# environment variable — config/prod.exs is static and runtime.exs is evaluated
# at boot — so that whole class of failure is gone.
#
# Usage:  ./redeploy.sh
set -euo pipefail

cd "$(dirname "$0")"

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export MIX_ENV=prod

echo "==> Assets (minify + digest)"
# assets.deploy minifies and runs phx.digest, rewriting cache_manifest.json.
# config/prod.exs sets cache_static_manifest, so ~p"/assets/..." resolves
# through that manifest — if it were older than priv/static, every page would
# silently load the previous build's stylesheet.
mix assets.deploy

# Old digests accumulate forever otherwise. Keep the current version plus one,
# so a client mid-request against the previous deploy still gets a hit.
mix phx.digest.clean --age 3600 --keep 1

echo "==> Build release"
mix release --overwrite

echo "==> Restart"
systemctl --user restart streetscissors.service

echo "==> Wait for health"
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:4000/ || true)
  if [ "$code" = "200" ]; then
    echo "    up (localhost:4000 -> 200)"

    # These must not be reachable in production.
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
    # and the whole site rendered with the old design.
    #
    # Check what a browser actually loads: pull the href out of the rendered
    # homepage rather than guessing the URL. That is a digested path, so this
    # also proves the manifest is in step with priv/static — a stale manifest
    # is silent, and points at the old build.
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

    # The release reads its database from DATABASE_PATH in the unit file. If
    # that ever resolves somewhere unexpected, SQLite silently creates an empty
    # file and the site comes up looking wiped rather than failing — so assert
    # the data is really there.
    rides=$(curl -s --max-time 15 http://localhost:4000/fitness/rides \
      | grep -c 'href="/fitness/rides/[0-9]' || true)
    if [ "$rides" -gt 0 ]; then
      echo "    database has content (${rides} rides rendered)"
    else
      echo "    !! no rides rendered — check DATABASE_PATH in the systemd unit."
      exit 1
    fi

    exit 0
  fi
  sleep 2
done

echo "!! site did not come up on localhost:4000"
systemctl --user status streetscissors.service --no-pager | tail -20
exit 1
