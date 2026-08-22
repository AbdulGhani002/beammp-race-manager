#!/usr/bin/env bash
# Every key binding names a lua function as a string, so a typo in either the
# json or a rename in the lua fails silently in game: the key just does
# nothing. This walks the actions file and checks each target really exists.
#
#   bash tools/check_bindings.sh

set -u
actions="client/lua/ge/extensions/core/input/actions/race_manager.json"
fail=0

while read -r call; do
  mod=$(echo "$call" | sed -E 's/extensions\.raceManager_([a-zA-Z]+)\..*/\1/')
  fn=$(echo "$call" | sed -E 's/.*\.([a-zA-Z]+)\(\)/\1/')
  f="client/lua/ge/extensions/raceManager/${mod}.lua"

  if [ ! -f "$f" ]; then
    echo "MISSING MODULE  $call"
    fail=1
  elif ! grep -qE "function M\.${fn}\b" "$f"; then
    echo "MISSING FN      $call"
    fail=1
  fi
done < <(grep -oE 'extensions\.[a-zA-Z_]+\.[a-zA-Z]+\(\)' "$actions" | sort -u)

n=$(grep -cE '"onDown"' "$actions")
if [ "$fail" -eq 0 ]; then
  echo "all $n key bindings point at a function that exists"
else
  echo "some bindings are broken"
fi
exit $fail
