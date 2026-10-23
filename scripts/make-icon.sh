#!/bin/zsh
# Regenerate Resources/AppIcon.icns.
#   default:            mask the AI artwork assets/ai/out/icon-a.png (Codex image_generation, see assets/ai/manifest.json)
#   make-icon.sh vector: draw the fallback vector icon with scripts/make-icon.swift (no assets)
#   make-icon.sh <png>:  mask any 1024x1024 full-bleed artwork
set -euo pipefail
ROOT="$(builtin cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
MODE="${1:-$ROOT/assets/ai/out/icon-a.png}"
if [[ "$MODE" == "vector" ]]; then
  swiftc -O "$ROOT/scripts/make-icon.swift" -o "$TMP/icon"
  "$TMP/icon" "$TMP/AppIcon.iconset" >/dev/null
else
  swiftc -O "$ROOT/scripts/mask-icon.swift" -o "$TMP/mask-icon"
  "$TMP/mask-icon" "$MODE" "$TMP" >/dev/null
fi
iconutil -c icns "$TMP/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
cp "$TMP/AppIcon-1024.png" "$ROOT/docs/evidence/ui/app-icon-1024.png"
cp "$TMP/AppIcon.iconset/icon_32x32.png" "$ROOT/docs/evidence/ui/app-icon-32.png"
echo "wrote $ROOT/Resources/AppIcon.icns"
