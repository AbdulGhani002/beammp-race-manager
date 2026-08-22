#!/usr/bin/env bash
# Compile every plan in docs/plans and drop a copy in Downloads.
#
#   bash tools/build_plans.sh
#
# Tectonic pulls what it needs on first run and caches it, so the first build
# is slow and the rest are not. No TeX install to maintain.

set -u
TEC="${TECTONIC:-$HOME/bin/tectonic.exe}"
OUT="${OUT_DIR:-$HOME/Downloads}"

[ -x "$TEC" ] || { echo "tectonic not found at $TEC"; exit 1; }

for tex in docs/plans/*.tex; do
  [ -e "$tex" ] || continue
  name=$(basename "$tex" .tex)
  echo "building $name"
  "$TEC" -X compile "$tex" >/dev/null 2>&1 || { echo "  FAILED"; exit 1; }
  cp "docs/plans/$name.pdf" "$OUT/BeamMP-${name}.pdf"
  echo "  -> docs/plans/$name.pdf  and  $OUT/BeamMP-${name}.pdf"
done
