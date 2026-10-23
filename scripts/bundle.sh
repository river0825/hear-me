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
# Sign with the self-signed "HearMe Dev" identity when its keychain exists: the designated requirement
# (identifier + certificate hash) then stays the same across rebuilds, so Accessibility/microphone grants survive.
# Falls back to ad-hoc (permissions must be re-granted after every rebuild).
KEYCHAIN="$HOME/Library/Keychains/hearme-dev.keychain-db"
IDENTITY="${HEARME_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" && -f "$KEYCHAIN" ]]; then
  security unlock-keychain -p "" "$KEYCHAIN" 2>/dev/null || true
  IDENTITY="HearMe Dev"
fi
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --identifier xyz.riverdm.hearme "$APP" 2>/dev/null \
    || { echo "signing with $IDENTITY failed, falling back to ad-hoc"; codesign --force --sign - --identifier xyz.riverdm.hearme "$APP" >/dev/null; }
else
  codesign --force --sign - --identifier xyz.riverdm.hearme "$APP" >/dev/null
fi
# Untrusted self-signed identities print no Authority= line; never let this summary fail the script.
codesign -dv "$APP" 2>&1 | grep -E "^Authority=|^Signature=|^Signed Time=" | head -1 || true
echo "built: $APP"
