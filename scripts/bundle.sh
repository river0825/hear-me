#!/bin/zsh
# Build a release binary and wrap it as HearMe.app (no Xcode project needed).
set -euo pipefail
ROOT="$(builtin cd "$(dirname "$0")/.." && pwd)"
builtin cd "$ROOT"
swift build -c release 2>&1 | tail -3
APP="$ROOT/build/HearMe.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/HearMe" "$APP/Contents/MacOS/HearMe"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
fi
# CI passes the tag (v0.1.0) and run number so the bundle carries the release version.
if [[ -n "${HEARME_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${HEARME_VERSION#v}" "$APP/Contents/Info.plist"
fi
if [[ -n "${HEARME_BUILD:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $HEARME_BUILD" "$APP/Contents/Info.plist"
fi
# Signing, in order of preference:
#   1. HEARME_SIGN_IDENTITY (+ optional HEARME_SIGN_KEYCHAIN), as CI sets them;
#   2. "Developer ID Application" in ~/Library/Keychains/apple-signing.keychain-db (Apple Developer team
#      437258HXBJ; set up by hq/ios/setup-developer-id.sh) — hardened runtime + timestamp, notarizable;
#   3. the self-signed "HearMe Dev" identity in ~/Library/Keychains/hearme-dev.keychain-db (stable
#      designated requirement, so TCC grants survive rebuilds, but Gatekeeper still complains);
#   4. ad-hoc (permissions must be re-granted after every rebuild).
APPLE_KEYCHAIN="${HEARME_APPLE_KEYCHAIN:-$HOME/Library/Keychains/apple-signing.keychain-db}"
DEV_KEYCHAIN="$HOME/Library/Keychains/hearme-dev.keychain-db"
IDENTITY="${HEARME_SIGN_IDENTITY:-}"
KEYCHAIN="${HEARME_SIGN_KEYCHAIN:-}"
if [[ -z "$IDENTITY" && -f "$APPLE_KEYCHAIN" ]]; then
  PASS="${HEARME_APPLE_KEYCHAIN_PASSWORD:-}"
  if [[ -z "$PASS" ]]; then
    PASS="$(gpg --batch --quiet --pinentry-mode loopback --passphrase '' --try-secret-key 0xE4FB09AEA16397BD \
            --decrypt "$HOME/.local/share/gopass/stores/root/services/apple/distribution-cert/password.gpg" 2>/dev/null || true)"
  fi
  [[ -n "$PASS" ]] && security unlock-keychain -p "$PASS" "$APPLE_KEYCHAIN" 2>/dev/null || true
  if security find-identity -v -p codesigning "$APPLE_KEYCHAIN" 2>/dev/null | grep -q "Developer ID Application"; then
    IDENTITY="Developer ID Application"; KEYCHAIN="$APPLE_KEYCHAIN"
  fi
fi
if [[ -z "$IDENTITY" && -f "$DEV_KEYCHAIN" ]]; then
  security unlock-keychain -p "" "$DEV_KEYCHAIN" 2>/dev/null || true
  IDENTITY="HearMe Dev"; KEYCHAIN="$DEV_KEYCHAIN"
fi
KC_ARGS=(); [[ -n "$KEYCHAIN" ]] && KC_ARGS=(--keychain "$KEYCHAIN")
if [[ "$IDENTITY" == Developer\ ID* ]]; then
  codesign --force --options runtime --timestamp --entitlements "$ROOT/Resources/HearMe.entitlements" \
    --sign "$IDENTITY" "${KC_ARGS[@]}" --identifier xyz.riverdm.hearme "$APP"
elif [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" "${KC_ARGS[@]}" --identifier xyz.riverdm.hearme "$APP" 2>/dev/null \
    || { echo "signing with $IDENTITY failed, falling back to ad-hoc"; codesign --force --sign - --identifier xyz.riverdm.hearme "$APP" >/dev/null; }
else
  codesign --force --sign - --identifier xyz.riverdm.hearme "$APP" >/dev/null
fi
# Untrusted self-signed identities print no Authority= line; never let this summary fail the script.
codesign -dv "$APP" 2>&1 | grep -E "^Authority=|^Signature=|^Signed Time=" | head -1 || true
echo "built: $APP"
