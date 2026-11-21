#!/usr/bin/env bash
# Offline tests for Stance Studio (needs luajit and the game installed).
#   tests/run.sh            run all tests against mod/
# The .vue check runs when node and ~/.cache/stance-studio-vuecheck (see tools/check_vue.cjs) exist.
set -uo pipefail
cd "$(dirname "$0")"
export G="${G:-$HOME/.local/share/Steam/steamapps/common/BeamNG.drive}"
export MOD="${MOD:-$(cd .. && pwd)/mod}"
status=0
for t in stance_test photo_test fun_test hook_test mp_test tandem_test; do
  out=$(luajit "$t.lua" 2>&1); last=$(echo "$out" | tail -1)
  echo "$t: $(echo "$out" | grep -c '^PASS') passed, $last"
  echo "$out" | grep '^FAIL' && status=1
done
echo "mesh_consistency (rim offset from its wheel, B is a deliberately wrong control):"
luajit mesh_consistency.lua 2>&1 | sed 's/^/  /'
if command -v node >/dev/null && [ -d "${VUECHECK_MODULES:-$HOME/.cache/stance-studio-vuecheck/node_modules}" ]; then
  if out=$(node tools/check_vue.cjs "$MOD" 2>&1); then echo "vue: $(echo "$out" | tail -1)"; else echo "$out" | grep -v '^ok'; status=1; fi
else
  echo "vue: skipped (no node or no ~/.cache/stance-studio-vuecheck)"
fi
exit $status
