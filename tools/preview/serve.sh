#!/usr/bin/env bash
# Runs the interface in a normal browser, with made up state standing in for
# the server, so a layout problem is found here rather than in the game.
#
#   bash tools/preview/serve.sh          then open http://127.0.0.1:8777
#
# It has already paid for itself: it caught sectors being labelled with the
# wrong gate, and a player list whose speed and ping columns sat outside the
# panel because two different things shared a class name. Neither shows up in
# a test and neither is visible reading the code.
#
# The scenes are idle, armed, running, waiting and results, on the buttons at
# the bottom left or as #armed on the url.

set -eu

port=${1:-8777}
root="$(cd "$(dirname "$0")/../.." && pwd)"
stage="${TMPDIR:-/tmp}/rm-preview"
angular="$stage/angular.min.js"

mkdir -p "$stage/ui/modules/apps/RaceManager"

# the real files, not copies that can drift
cp "$root"/client/ui/modules/apps/RaceManager/app.css \
   "$root"/client/ui/modules/apps/RaceManager/app.html \
   "$root"/client/ui/modules/apps/RaceManager/app.js \
   "$root"/client/ui/modules/apps/RaceManager/logo-shield.png \
   "$root"/client/ui/modules/apps/RaceManager/logo-round.png \
   "$stage/ui/modules/apps/RaceManager/"
cp "$root/tools/preview/index.html" "$stage/index.html"

# angular is the game's, not ours, so it is fetched rather than committed
if [ ! -f "$angular" ]; then
  echo "fetching angular"
  curl -sS -L --max-time 60 -o "$angular" \
    https://ajax.googleapis.com/ajax/libs/angularjs/1.8.3/angular.min.js
fi

echo "serving $stage on http://127.0.0.1:$port"
echo "the browser caches hard here, so reload with a query string: ?f=2"
cd "$stage"
python -m http.server "$port" --bind 127.0.0.1
