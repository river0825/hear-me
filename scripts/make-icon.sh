#!/bin/zsh
# Regenerate Resources/AppIcon.icns from scripts/make-icon.swift (pure CoreGraphics, no assets).
set -euo pipefail
ROOT="$(builtin cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
swiftc -O "$ROOT/scripts/make-icon.swift" -o "$TMP/icon"
"$TMP/icon" "$TMP/AppIcon.iconset" >/dev/null
iconutil -c icns "$TMP/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
cp "$TMP/AppIcon-1024.png" "$ROOT/docs/evidence/ui/app-icon-1024.png"
echo "wrote $ROOT/Resources/AppIcon.icns"
