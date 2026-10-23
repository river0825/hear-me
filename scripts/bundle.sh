#!/bin/zsh
# Build a release binary and wrap it as ShuoXie.app (no Xcode project needed).
set -euo pipefail
ROOT="$(builtin cd "$(dirname "$0")/.." && pwd)"
builtin cd "$ROOT"
swift build -c release 2>&1 | tail -3
APP="$ROOT/build/ShuoXie.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/ShuoXie" "$APP/Contents/MacOS/ShuoXie"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
fi
# Ad-hoc signature is enough for TCC prompts; a stable identity would keep permissions across rebuilds.
IDENTITY="${SHUOXIE_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --identifier xyz.riverdm.shuoxie "$APP" >/dev/null
echo "built: $APP"
