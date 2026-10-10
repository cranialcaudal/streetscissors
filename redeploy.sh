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

echo "==> Keep the release that is serving now"
# The one command a bad deploy needs is ./rollback.sh, and it can only return
# to a release that still exists. `mix release --overwrite` rebuilds the
# directory in place, so the one that is running is copied aside first.
#
# Only when the site is answering. If the last deploy is the thing that broke
# it, the copy already kept is the good one, and a second attempt at deploying
# must not replace it with the broken release.
#
# --reflink=auto: on btrfs the copy shares its blocks with the original, so it
# costs neither the time nor the 80 MB.
if [ -d _build/prod/rel/web ]; then
  serving=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:4000/ || true)
  if [ "$serving" = "200" ]; then
    rm -rf _build/prod/rel/web.previous
    cp -a --reflink=auto _build/prod/rel/web _build/prod/rel/web.previous
    echo "    kept as _build/prod/rel/web.previous"
  else
    echo "    the site is not answering (${serving:-nothing}); leaving the kept release as it is"
  fi
fi

echo "==> Build release"
mix release --overwrite

# A restart kills a scan in progress and the run of singles behind it (it did,
# twice, on 2026-10-07). So the restart waits for the scanner to be idle, asked
# at this moment and not before the build, and gives up rather than wait for ever.
echo "==> Wait for the scanner"
# The build above replaced the release's files, cookie included, so the node
# that is serving is asked through the copy kept of it. No answer means it is
# not up, so not scanning.
ASK="_build/prod/rel/web.previous/bin/web"
[ -x "$ASK" ] || ASK="_build/prod/rel/web/bin/web"
scanner_busy() {
  systemctl --user is-active --quiet streetscissors.service || return 1
  out=$("$ASK" rpc 'IO.write(inspect(Web.Scanner.Bed.status().job != nil))' 2>/dev/null) || return 1
  [ "$out" = "true" ]
}
waited=0
while scanner_busy; do
  if [ "$waited" -ge 900 ]; then
    echo "    the scanner has been busy for 15 minutes; not restarting. Run this again when it is free." >&2
    exit 1
  fi
  [ "$waited" -eq 0 ] && echo "    a scan is running; waiting for it to finish"
  sleep 5; waited=$((waited + 5))
done
echo "    idle"

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

    # Colocated hooks are extracted when Elixir compiles and bundled by esbuild,
    # so a build that bundles before compiling ships without them. The HTML
    # still renders; the browser only logs "unknown hook" — which is how the
    # Activities shelves once went live with dead buttons. Every hook the
    # compiler extracted must be named in the JS a browser actually loads.
    js_href=$(curl -s --max-time 15 http://localhost:4000/ \
      | grep -oE '/assets/js/app[^"]*\.js' | head -1)
    if [ -z "$js_href" ]; then
      echo "    !! could not find the app.js script in the homepage HTML."
      exit 1
    fi

    served_js=$(curl -s --compressed --max-time 15 "http://localhost:4000${js_href}")
    hooks=$(grep -oE 'imp_[a-z0-9]+\["[^"]+"\]' _build/prod/phoenix-colocated/web/index.js 2>/dev/null \
      | sed -E 's/.*\["(.*)"\]/\1/' || true)
    for hook in $hooks; do
      if grep -qF "\"${hook}\"" <<< "$served_js"; then
        echo "    hook ${hook} is bundled"
      else
        echo "    !! colocated hook ${hook} is missing from ${js_href} — was JS bundled before compile?"
        exit 1
      fi
    done

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
echo "!! ./rollback.sh returns to the release that was serving before this deploy."
exit 1
