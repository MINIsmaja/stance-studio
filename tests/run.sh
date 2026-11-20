#!/usr/bin/env bash
# Offline tests for Stance Studio (needs luajit and the game installed).
#   tests/run.sh            run all Lua tests against mod/
set -uo pipefail
cd "$(dirname "$0")"
export G="${G:-$HOME/.local/share/Steam/steamapps/common/BeamNG.drive}"
export MOD="${MOD:-$(cd .. && pwd)/mod}"
status=0
for t in stance_test photo_test; do
  out=$(luajit "$t.lua" 2>&1); last=$(echo "$out" | tail -1)
  echo "$t: $(echo "$out" | grep -c '^PASS') passed, $last"
  echo "$out" | grep '^FAIL' && status=1
done
echo "mesh_consistency (rim offset from its wheel, B is a deliberately wrong control):"
luajit mesh_consistency.lua 2>&1 | sed 's/^/  /'
exit $status
