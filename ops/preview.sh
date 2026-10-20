#!/bin/bash
#
# A look at the working tree before it is deployed: a development server on
# http://127.0.0.1:4100, beside the live site on 4000, reading a fresh copy of
# the live database.
#
#   ops/preview.sh            copy the database, then serve
#   ops/preview.sh --keep     serve the copy made last time
#
# PREVIEW=1 (config/dev.exs) turns off everything the live site does on its
# own: cron, queued jobs, boot snapshots, the drive watcher, encodes, the
# monitor, Komoot, mail and the scanner. It sends no webmentions and pings no
# search engine. What it does share with the live site is the checkout:
# content/ is the same folder, so a post saved in the preview's admin is saved
# for real. Look, don't write. Stop it with Ctrl-C.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA="$(dirname "$ROOT")/streetscissors-data"
LIVE_DB="$DATA/streetscissors.db"
COPY="$ROOT/tmp/db/preview.db"

cd "$ROOT"

if [ "${1:-}" != "--keep" ] || [ ! -f "$COPY" ]; then
  if [ ! -f "$LIVE_DB" ]; then
    echo "No live database at $LIVE_DB to copy." >&2
    exit 1
  fi
  mkdir -p "$(dirname "$COPY")"
  rm -f "$COPY" "$COPY-wal" "$COPY-shm"
  # VACUUM INTO reads a consistent copy while the live site keeps writing; a
  # plain cp of a database in WAL mode can catch it half way.
  sqlite3 "file:$LIVE_DB?mode=ro" "VACUUM INTO '$COPY'"
  echo "Copied the live database to tmp/db/preview.db."
fi

if [ -f "$ROOT/.env" ]; then
  set -a
  source "$ROOT/.env"
  set +a
fi

# After .env, so nothing in it can point the preview at live ground.
unset DATABASE_PATH BACKUP_PATH CONTENT_BACKUP_PATH INDEXNOW_KEY
unset BACKUP_MIRROR_PATH PHOTOS_MIRROR_PATH CONTENT_MIRROR_PATH UPLOADS_MIRROR_PATH
export UPLOADS_PATH="${UPLOADS_PATH:-$DATA/uploads}"
export PREVIEW=1
export PORT=4100
export MIX_ENV=dev

echo "Preview on http://127.0.0.1:4100 (admin password: dev-admin)"
exec mix phx.server
