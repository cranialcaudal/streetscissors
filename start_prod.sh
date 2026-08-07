#!/bin/bash
set -a
source "$(dirname "$0")/.env"
set +a

export PHX_SERVER=true
export PHX_HOST=streetscissors.com
export DATABASE_PATH=/home/cesar/streetscissors/street_scissors_prod.db
export MANUSCRIPTS_PATH="/home/cesar/Documents/Obsidian Vault/manuscripts"
export PORT=4000

_build/prod/rel/web/bin/web start
