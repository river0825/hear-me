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
# The public relay drops an idle offer after ~3 hours ("EOF", exit 1). Re-offer until someone
# actually receives it (croc exits 0) or HEARME_CROC_TRIES attempts have passed.
TRIES="${HEARME_CROC_TRIES:-16}"
for ((i = 1; i <= TRIES; i++)); do
  if croc --yes send --code "$CODE" "$ROOT/build/HearMe.zip"; then
    echo "sent (attempt $i, $(date '+%Y-%m-%d %H:%M'))"
    exit 0
  fi
  echo "relay dropped the offer (attempt $i/$TRIES, $(date '+%Y-%m-%d %H:%M')); re-offering in 5s"
  sleep 5
done
echo "gave up after $TRIES attempts" >&2
exit 1
