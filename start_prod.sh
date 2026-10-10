#!/bin/bash
#
# Start the MIX_ENV=prod release by hand, in a terminal, with the environment
# the systemd unit gives it. The supervised path is the unit
# (`streetscissors.service`; a copy is kept in ops/systemd/). This is for the
# rare case of wanting the release's own output in front of you, with the unit
# stopped.
#
# Build it first:  MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix release
#
# The paths below have to say what the unit says, so a change to one is a
# change to both. They once did not: this file went on naming web_dev.db as
# the live database after the data moved out of the checkout. Had it been run,
# it would have served the development database to the public and filed
# snapshots of it among the real backups.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BESIDE="$(dirname "$ROOT")"
DATA="$BESIDE/streetscissors-data"
BACKUPS="$BESIDE/streetscissors-backups"
DRIVE="/run/media/$(id -un)/Third/streetscissors-backups"

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

# A second copy would migrate the database and take its boot backup before it
# found port 4000 taken.
if systemctl --user is-active --quiet streetscissors.service; then
  echo "streetscissors.service is running, so this would be a second copy of the site." >&2
  echo "Stop it first (systemctl --user stop streetscissors), or leave it and use:" >&2
  echo "  journalctl --user -u streetscissors -f     its output" >&2
  echo "  _build/prod/rel/web/bin/web remote         a console inside it" >&2
  exit 1
fi

# SQLite makes an empty database where it finds none, and the site comes up
# looking wiped.
if [ ! -f "$DATA/streetscissors.db" ]; then
  echo "No database at $DATA/streetscissors.db; not starting." >&2
  exit 1
fi

export LANG=en_US.UTF-8
# ~/.local/bin holds the film pipeline's tools, which the scanner page runs.
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
export PHX_SERVER=true
export PHX_HOST=streetscissors.com
export PORT=4000

set -a
source "$ROOT/.env"
set +a

# After .env, as in the unit, so that nothing in it can point these elsewhere.
export DATABASE_PATH="$DATA/streetscissors.db"
export RIDE_THUMBS_PATH="$DATA/ride_thumbs"
export UPLOADS_PATH="$DATA/uploads"
export BLOG_PATH="$ROOT/content/blog"
export FITNESS_PATH="$ROOT/content/fitness"
export BACKUP_PATH="$BACKUPS/db"
export CONTENT_BACKUP_PATH="$BACKUPS/content"
export BACKUP_MIRROR_PATH="$DRIVE/db"
export PHOTOS_MIRROR_PATH="$DRIVE/negatives"
export CONTENT_MIRROR_PATH="$DRIVE/content"
export UPLOADS_MIRROR_PATH="$DRIVE/uploads"
export MONITOR_UNITS=caddy-streetscissors.service

exec "$ROOT/_build/prod/rel/web/bin/web" start
