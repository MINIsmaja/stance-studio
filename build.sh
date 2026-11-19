#!/usr/bin/env bash
# Builds dist/stancestudio.zip from mod/.
#   ./build.sh          zip what is in mod/
#   ./build.sh --sync   first copy the unpacked mod from your BeamNG user folder into mod/
set -euo pipefail
cd "$(dirname "$0")"
if [ "${1:-}" = "--sync" ]; then
  src="${BEAMNG_USER:-$HOME/.local/share/BeamNG/BeamNG.drive/current}/mods/unpacked/stancestudio"
  rsync -a --delete "$src/" mod/
fi
mkdir -p dist
rm -f dist/stancestudio.zip
(cd mod && zip -rq -X ../dist/stancestudio.zip .)
echo "built dist/stancestudio.zip"
