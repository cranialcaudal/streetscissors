#!/bin/bash
#
# Start the MIX_ENV=prod release by hand. The supervised path is the systemd
# user unit `streetscissors.service`; this is for running the release in a
# terminal to check it.
#
# Build it first:  MIX_ENV=prod mix assets.deploy && MIX_ENV=prod mix release
set -a
source "$(dirname "$0")/.env"
set +a

export PHX_SERVER=true
export PHX_HOST=streetscissors.com

# The live database. This previously pointed at street_scissors_prod.db, a
# relic from the retired container stack that is seven migrations behind and
# has no rides table at all — starting the release would have served an empty
# site and then migrated the wrong file. That file is now renamed
# .retired-2026-07-17 and nothing points at it.
#
# Note the container stack is different: docker-compose.yml's
# /data/street_scissors_prod.db is a path inside a named volume, not this repo,
# and is correct in that context.
export DATABASE_PATH=/home/cesar/streetscissors/web_dev.db

# File-based content lives in the checkout, not in the release. Without these
# every fitness and blog page renders empty — runtime.exs only overrides the
# defaults when they are set.
export BLOG_PATH=/home/cesar/streetscissors/content/blog
export FITNESS_PATH=/home/cesar/streetscissors/content/fitness

# Audio uploads must land outside the release: `mix release` replaces priv/ on
# every build, which would delete them.
export UPLOADS_PATH=/home/cesar/streetscissors/uploads

export PORT=4000

_build/prod/rel/web/bin/web start
