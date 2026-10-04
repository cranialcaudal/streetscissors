#!/usr/bin/env bash
#
# Return the live site to the release it was running before the last deploy.
#
# ./redeploy.sh keeps the release that was serving as _build/prod/rel/web.previous
# before it builds over it. This swaps the two and restarts, so the previous
# build is live again in the few seconds a restart takes, without compiling
# anything. Run it a second time and the newer release is back: it is a swap,
# not a one-way door.
#
# What it does not do:
#
#   * It does not touch the checkout. The source is still the newer code; fix
#     it forward or `git revert`, then ./redeploy.sh as usual.
#   * It does not undo a database migration. The older release boots against
#     the schema as it now is. An added table or column is harmless to code
#     that does not know about it; one that was dropped or renamed is not, and
#     for that the answer is a snapshot (Web.Backup), not this script.
#   * It does not change content. Posts, the fitness vault and the negatives
#     are read from disk by whichever release is running.
#
# Usage:  ./rollback.sh
set -euo pipefail

cd "$(dirname "$0")"

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

REL=_build/prod/rel

if [ ! -x "$REL/web.previous/bin/web" ]; then
  echo "!! no previous release is kept at $REL/web.previous"
  echo "   ./redeploy.sh keeps one each time it runs while the site is answering."
  exit 1
fi

built() { date -r "$1/bin/web" '+%Y-%m-%d %H:%M'; }
echo "==> Swapping the release built $(built "$REL/web") for the one built $(built "$REL/web.previous")"

# Stopped first: the directory is moved out from under nothing.
systemctl --user stop streetscissors.service

mv "$REL/web" "$REL/web.swap"
mv "$REL/web.previous" "$REL/web"
mv "$REL/web.swap" "$REL/web.previous"

systemctl --user start streetscissors.service

echo "==> Wait for health"
# The homepage rather than /health: the release being returned to may be
# older than that endpoint.
for _ in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:4000/ || true)
  if [ "$code" = "200" ]; then
    echo "    up (localhost:4000 -> 200), serving the release built $(built "$REL/web")"
    echo "    ./rollback.sh again returns to the one built $(built "$REL/web.previous")"
    exit 0
  fi
  sleep 2
done

echo "!! the site did not come up on the previous release either"
systemctl --user status streetscissors.service --no-pager | tail -20
echo "!! ./rollback.sh again swaps back."
exit 1
