#!/bin/zsh
# Notarize build/HearMe.app (must already be signed with "Developer ID Application" + hardened runtime)
# and staple the ticket, so Gatekeeper opens it without the "unidentified developer" dance.
# Credentials: an App Store Connect API key, from env (HEARME_ASC_KEY_P8 = path to the .p8,
# HEARME_ASC_KEY_ID, HEARME_ASC_ISSUER_ID) or, on the dev Mac, decrypted from gopass
# services/apple/asc-api-key/{p8,key-id,issuer-id} with the AI Agent GPG key.
set -euo pipefail
ROOT="$(builtin cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/HearMe.app"
[[ -d "$APP" ]] || { echo "no $APP — run scripts/bundle.sh first" >&2; exit 1; }
# Capture first: with pipefail, `grep -q` closing the pipe early makes codesign die of SIGPIPE.
SIGINFO="$(codesign -dv --verbose=2 "$APP" 2>&1 || true)"
[[ "$SIGINFO" == *"Authority=Developer ID Application"* ]] || { echo "$APP is not signed with Developer ID Application; notarization would be rejected" >&2; exit 1; }

WORK="$(mktemp -d)"; chmod 700 "$WORK"; trap 'rm -rf "$WORK"' EXIT
decrypt() {
  gpg --batch --quiet --pinentry-mode loopback --passphrase '' --try-secret-key 0xE4FB09AEA16397BD \
      --decrypt "$HOME/.local/share/gopass/stores/root/services/apple/asc-api-key/$1.gpg"
}
KEY="${HEARME_ASC_KEY_P8:-}"
KEY_ID="${HEARME_ASC_KEY_ID:-}"
ISSUER="${HEARME_ASC_ISSUER_ID:-}"
if [[ -z "$KEY" ]]; then
  KEY="$WORK/AuthKey.p8"; decrypt p8 > "$KEY"
  [[ -n "$KEY_ID" ]] || KEY_ID="$(decrypt key-id)"
  [[ -n "$ISSUER" ]] || ISSUER="$(decrypt issuer-id)"
fi

ZIP="$WORK/HearMe.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "submitting $(du -h "$ZIP" | cut -f1) to the notary service…"
xcrun notarytool submit "$ZIP" --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER" --wait --timeout 30m --output-format json > "$WORK/result.json" || true
cat "$WORK/result.json"
STATUS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status",""))' "$WORK/result.json")"
ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("id",""))' "$WORK/result.json")"
if [[ "$STATUS" != "Accepted" ]]; then
  echo "notarization status: $STATUS" >&2
  [[ -n "$ID" ]] && xcrun notarytool log "$ID" --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER" >&2 || true
  exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vv "$APP" 2>&1 || true
echo "notarized and stapled: $APP"
