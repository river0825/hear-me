#!/bin/zsh
# Zip build/HearMe.app and offer it over croc with a fixed code phrase, so the receiving side
# can always run the same command: croc $HEARME_CROC_CODE
set -euo pipefail
ROOT="$(builtin cd "$(dirname "$0")/.." && pwd)"
CODE="${HEARME_CROC_CODE:-hearme-river-mac}"
[[ -d "$ROOT/build/HearMe.app" ]] || "$ROOT/scripts/bundle.sh"
rm -f "$ROOT/build/HearMe.zip"
ditto -c -k --keepParent "$ROOT/build/HearMe.app" "$ROOT/build/HearMe.zip"
echo "receiver runs:  croc $CODE"
exec croc --yes send --code "$CODE" "$ROOT/build/HearMe.zip"
