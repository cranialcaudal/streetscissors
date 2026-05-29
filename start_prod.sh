#!/bin/bash
export MIX_ENV=prod
export PHX_SERVER=true
export PHX_HOST=streetscissors.com
export SECRET_KEY_BASE=hySd1876kxzubhXn3vLZ1g4oplu7QPbFIwcvndaE5Cr5IMPtAJ1ofiDHB1mmLZlp
export DATABASE_PATH=/home/cesar/streetscissors/web/street_scissors_prod.db
export PORT=4000

# Run migrations if needed (for release)
# _build/prod/rel/web/bin/web eval "Web.Release.migrate"

# Start the server
_build/prod/rel/web/bin/web start
